#!/usr/bin/env python3
"""Add the next unhandled project from the CSV, using headless Sonnet for judgement.

One project per invocation (cron-friendly). Flow:

    select -> invoke `claude -p` (Sonnet) -> verify with Bazel -> commit+push -> record

The orchestrator is the *trusted gate*: it re-runs `bazel build`/`test` itself and
only lands a project when Bazel agrees. Headless Sonnet does the judgement work
(pin a commit, pick a toolchain, write BUILD.bazel + smoke.sh, iterate to green or
defer with a reason) but runs no git. Every attempted project ends up "handled"
(landed or deferred) so it is never retried.

Usage:
    add_next_project.py                 # add the next unhandled project
    add_next_project.py --dry-run       # just print which project is next
    add_next_project.py --repo <url>    # force a specific CSV project (for testing)
    add_next_project.py --no-push       # commit locally but skip `git push`
"""

import argparse
import csv
import json
import os
import re
import subprocess
import sys
import time
from datetime import datetime, timezone
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
AUTO_DIR = REPO_ROOT / "automation"
CSV_PATH = REPO_ROOT / "top1000repos-strict.csv"
STATE_PATH = AUTO_DIR / "state.json"
PROMPT_PATH = AUTO_DIR / "prompt.md"
RESULT_PATH = AUTO_DIR / ".result.json"
LOGS_DIR = AUTO_DIR / "logs"
PRIORITY_PATH = AUTO_DIR / "priority.txt"

# Languages we have a cached //toolchains:*_rootfs for. A pending project in any
# other language is pre-filtered (never sent to claude): the prompt forbids
# building a new toolchain, so claude could only ever defer it. Reversible — add
# a toolchain + a mapping here and those projects re-enter the queue automatically.
LANG_TOOLCHAIN = {
    "javascript": "node", "typescript": "node",
    "python": "python", "go": "go", "rust": "rust",
    "shell": "shell", "c": "c", "c++": "c",
}

MODEL = os.environ.get("CLAUDE_MODEL", "sonnet")
BUDGET_SECONDS = int(os.environ.get("CLAUDE_BUDGET_SECONDS", "5400"))  # 90 min default
BAZEL = os.environ.get("BAZEL", "bazel")
# Trailer reflects who actually authored the change: the headless Sonnet pipeline.
COAUTHOR = "Co-Authored-By: Claude (headless Sonnet via automation) <noreply@anthropic.com>"


# --------------------------------------------------------------------------- util

def log(msg):
    print(f"[{datetime.now(timezone.utc).strftime('%H:%M:%S')}] {msg}", flush=True)


def normalize_url(url):
    u = (url or "").strip().lower()
    u = re.sub(r"\.git$", "", u)
    return u.rstrip("/")


def run(cmd, **kw):
    """Run a command, return CompletedProcess (text)."""
    return subprocess.run(cmd, cwd=REPO_ROOT, text=True, capture_output=True, **kw)


def git(*args):
    return run(["git", *args])


# --------------------------------------------------------------------------- state

def load_state():
    if STATE_PATH.exists():
        return json.loads(STATE_PATH.read_text())
    return {}


def save_state(state):
    STATE_PATH.write_text(json.dumps(state, indent=2, sort_keys=True) + "\n")


def landed_repos_from_build():
    """Repos with a project dir are authoritatively landed (read straight from BUILD)."""
    repos = set()
    for build in REPO_ROOT.glob("projects/*/BUILD.bazel"):
        m = re.search(r'repo\s*=\s*"([^"]+)"', build.read_text())
        if m:
            repos.add(normalize_url(m.group(1)))
    return repos


def handled_set(state):
    handled = landed_repos_from_build()
    for url, rec in state.items():
        if rec.get("status") in ("landed", "deferred"):
            handled.add(normalize_url(url))
    return handled


# --------------------------------------------------------------------------- select

def read_csv_rows():
    with open(CSV_PATH, newline="") as f:
        return list(csv.DictReader(f))


def buildable(row):
    """True if we have a cached toolchain for this project's language."""
    return row.get("language", "").strip().lower() in LANG_TOOLCHAIN


def load_priority():
    """Lands-first list: normalized repo_urls attempted before CSV order."""
    if not PRIORITY_PATH.exists():
        return []
    out = []
    for line in PRIORITY_PATH.read_text().splitlines():
        line = line.split("#", 1)[0].strip()
        if line:
            out.append(normalize_url(line))
    return out


def select_next(rows, handled, priority, force_repo=None):
    """Pick the next project to attempt. Returns (row_or_None, prefiltered_list).

    Ordering: priority-list entries first (in listed order), then the rest in CSV
    order. Projects whose language has no cached toolchain are pre-filtered out
    (returned separately for logging) rather than sent to claude.
    """
    if force_repo:  # --repo bypasses the filter/priority (force any CSV row)
        target = normalize_url(force_repo)
        return next((r for r in rows if normalize_url(r["repo_url"]) == target), None), []

    prefiltered, candidates = [], []
    for idx, row in enumerate(rows):
        u = normalize_url(row["repo_url"])
        if u in handled:
            continue
        if not buildable(row):
            prefiltered.append(row)
            continue
        prank = priority.index(u) if u in priority else len(priority)
        candidates.append((prank, idx, row))
    candidates.sort(key=lambda t: (t[0], t[1]))
    return (candidates[0][2] if candidates else None), prefiltered


# --------------------------------------------------------------------------- claude

def render_prompt(row):
    tmpl = PROMPT_PATH.read_text()
    repl = {
        "{{REPO_URL}}": row["repo_url"],
        "{{LANGUAGE}}": row.get("language", ""),
        "{{DESCRIPTION}}": row.get("description", ""),
        "{{RANK}}": row.get("rank_code_size", ""),
        "{{EVIDENCE}}": row.get("evidence", ""),
        "{{RESULT_PATH}}": str(RESULT_PATH.relative_to(REPO_ROOT)),
    }
    for k, v in repl.items():
        tmpl = tmpl.replace(k, v)
    return tmpl


def invoke_claude(prompt, log_path):
    """Run headless Sonnet, streaming the transcript to log_path. Returns exit code."""
    cmd = [
        "timeout", str(BUDGET_SECONDS),
        "claude", "-p", prompt,
        "--model", MODEL,
        "--permission-mode", "bypassPermissions",
        "--output-format", "stream-json", "--verbose",
    ]
    log(f"invoking claude ({MODEL}, budget {BUDGET_SECONDS}s) -> {log_path.name}")
    with open(log_path, "w") as lf:
        lf.write(f"# claude invocation {datetime.now(timezone.utc).isoformat()}\n")
        lf.write(f"# model={MODEL} budget={BUDGET_SECONDS}s\n\n")
        lf.flush()
        proc = subprocess.Popen(
            cmd, cwd=REPO_ROOT, text=True,
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
        )
        for line in proc.stdout:
            lf.write(line)
            lf.flush()
        return proc.wait()


def read_result():
    if RESULT_PATH.exists():
        try:
            return json.loads(RESULT_PATH.read_text())
        except json.JSONDecodeError:
            return None
    return None


# --------------------------------------------------------------------------- verify

def detect_new_project_dir():
    """Fallback when .result.json is missing: a newly added projects/<name>/ dir."""
    cp = git("status", "--porcelain")
    names = set()
    for line in cp.stdout.splitlines():
        path = line[3:].strip().strip('"')
        m = re.match(r"projects/([^/]+)/", path)
        if m:
            names.add(m.group(1))
    return sorted(names)


def bazel_targets(project):
    cp = run([BAZEL, "query", f'kind("sh_test", //projects/{project}:*)'])
    return [t.strip() for t in cp.stdout.splitlines() if t.strip().startswith("//")]


def verify_landed(project):
    """Re-derive truth from Bazel. Returns (ok: bool, report: dict)."""
    report = {"build": None, "smoke": None, "tests": {}}
    log(f"verify: bazel build //projects/{project}")
    build = run([BAZEL, "build", f"//projects/{project}"])
    report["build"] = build.returncode == 0
    if not report["build"]:
        report["build_err"] = build.stderr[-2000:]
        return False, report

    targets = bazel_targets(project)
    smoke_targets = [t for t in targets if t.endswith("_smoke")]
    test_targets = [t for t in targets if t.endswith("_test")]
    report["smoke_target_exists"] = bool(smoke_targets)

    for t in test_targets:
        log(f"verify: bazel test {t}")
        cp = run([BAZEL, "test", t])
        report["tests"][t] = cp.returncode == 0

    if smoke_targets:
        log(f"verify: bazel test {smoke_targets[0]}")
        cp = run([BAZEL, "test", smoke_targets[0]])
        report["smoke"] = cp.returncode == 0

    ok = (report["build"]
          and report["smoke"] is True
          and all(report["tests"].values()))
    return ok, report


# --------------------------------------------------------------------------- git out

def working_tree_paths():
    cp = git("status", "--porcelain")
    return [line[3:].strip().strip('"') for line in cp.stdout.splitlines() if line.strip()]


def commit_and_push(subject, body, push):
    msg = subject + "\n\n" + body.rstrip() + "\n\n" + COAUTHOR
    cp = git("commit", "-m", msg)
    if cp.returncode != 0:
        log(f"git commit failed:\n{cp.stdout}\n{cp.stderr}")
        return None, False
    sha = git("rev-parse", "HEAD").stdout.strip()
    log(f"committed {sha[:9]}: {subject}")
    if not push:
        return sha, False
    p = git("push", "origin", "HEAD:main")
    pushed = p.returncode == 0
    log("pushed to origin/main" if pushed else f"push FAILED (commit kept locally):\n{p.stderr}")
    return sha, pushed


def reset_clean():
    git("reset", "--hard", "HEAD")
    git("clean", "-fd")  # -fd only; gitignored logs/.result.json are preserved


# --------------------------------------------------------------------------- main

def record(state, url, status, push, **fields):
    state[normalize_url(url)] = {
        "status": status,
        "ts": datetime.now(timezone.utc).isoformat(),
        **fields,
    }
    save_state(state)
    git("add", str(STATE_PATH.relative_to(REPO_ROOT)))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry-run", action="store_true", help="print the next project and exit")
    ap.add_argument("--repo", help="force a specific CSV repo_url (for testing)")
    ap.add_argument("--no-push", action="store_true", help="commit but do not push")
    args = ap.parse_args()
    push = not args.no_push

    LOGS_DIR.mkdir(exist_ok=True)
    state = load_state()
    rows = read_csv_rows()
    handled = handled_set(state)
    priority = load_priority()
    log(f"{len(handled)} projects handled; selecting next (lands-first, "
        f"{len(priority)} prioritized)")

    row, prefiltered = select_next(rows, handled, priority, force_repo=args.repo)
    if prefiltered:
        sample = ", ".join(f"{r['repo_url'].split('/')[-1]} [{r['language']}]"
                           for r in prefiltered[:4])
        log(f"pre-filtered {len(prefiltered)} pending project(s) with no cached "
            f"toolchain (skipped, not sent to claude): {sample}"
            + (" …" if len(prefiltered) > 4 else ""))
    if row is None:
        log("no buildable unhandled project found — all done (or --repo not in CSV)")
        return 0
    url = row["repo_url"]
    via = "priority" if normalize_url(url) in priority else "CSV order"
    log(f"next: {url}  ({row.get('language')}, rank_code_size={row.get('rank_code_size')}, via {via})")
    log(f"  desc: {row.get('description')}")

    if args.dry_run:
        return 0

    # Make sure we start from a clean tree on the default branch.
    if working_tree_paths():
        log("working tree is dirty — refusing to start; clean it first")
        return 1

    # Fresh slate for the result contract, then hand off to Sonnet.
    RESULT_PATH.unlink(missing_ok=True)
    slug = re.sub(r"[^a-z0-9]+", "-", url.lower()).strip("-")
    stamp = datetime.now(timezone.utc).strftime("%Y%m%d-%H%M%S")
    log_path = LOGS_DIR / f"{stamp}-{slug}.log"

    rc = invoke_claude(render_prompt(row), log_path)
    log(f"claude exited rc={rc}")
    result = read_result() or {}

    # Determine the project name (result contract, else a new projects/ dir).
    project = result.get("project")
    if not project:
        candidates = detect_new_project_dir()
        project = candidates[0] if candidates else None
    claimed = result.get("status")
    changed = working_tree_paths()
    log(f"claude claimed status={claimed!r} project={project!r}; {len(changed)} paths changed")

    # ---- Outcome: claude timed out / errored with nothing usable -> failed.
    if rc != 0 and not changed:
        log("claude failed and made no changes — recording as deferred (could not land)")
        reset_clean()
        record(state, url, "deferred", push,
               reason=f"could not land: claude rc={rc}, no changes", log=log_path.name)
        commit_and_push(f"Record {slug} as deferred (automation could not land)",
                        f"Headless add of {url} produced no usable result (rc={rc}).\n"
                        f"See automation/logs/{log_path.name}.", push)
        return 0

    # ---- Outcome: a project dir exists -> must pass the Bazel gate to land.
    if project and (REPO_ROOT / "projects" / project).is_dir():
        ok, report = verify_landed(project)
        log(f"verification: {'PASS' if ok else 'FAIL'} {json.dumps(report)}")
        if ok:
            record(state, url, "landed", push, project=project,
                   commit=result.get("pinned_commit"), log=log_path.name)
            git("add", "-A")
            subject = result.get("commit_subject") or f"Add {project}"
            body = result.get("commit_body") or f"Automated add of {url}."
            sha, pushed = commit_and_push(subject, body, push)
            log(f"LANDED {project} ({sha[:9] if sha else 'no-commit'}, pushed={pushed})")
            return 0
        # Built tree did not pass the gate -> discard and defer.
        log("project did not pass the gate — discarding and recording as deferred")
        reset_clean()
        record(state, url, "deferred", push,
               reason=f"could not land: verification failed {json.dumps(report)[:300]}",
               log=log_path.name)
        commit_and_push(f"Record {slug} as deferred (automation could not land)",
                        f"Headless add of {url} built a project that failed verification.\n"
                        f"See automation/logs/{log_path.name}.", push)
        return 0

    # ---- Outcome: clean deferral (Sonnet chose to defer; only README touched).
    non_doc = [p for p in changed if p not in ("README.md",)
               and not p.startswith("automation/")]
    if claimed == "deferred" and not non_doc:
        reason = result.get("reasoning") or "deferred by judgement"
        record(state, url, "deferred", push, reason=reason, log=log_path.name)
        git("add", "README.md")
        subject = result.get("commit_subject") or f"Defer {slug}"
        body = result.get("commit_body") or f"Deferred {url}: {reason}"
        sha, pushed = commit_and_push(subject, body, push)
        log(f"DEFERRED {slug} ({sha[:9] if sha else 'no-commit'}, pushed={pushed})")
        return 0

    # ---- Anything else (messy/partial) -> discard, record deferred, move on.
    log("unclear/partial outcome — discarding changes and recording as deferred")
    reset_clean()
    record(state, url, "deferred", push,
           reason=f"could not land: unclear outcome (claimed={claimed}, "
                  f"project={project}, changed={len(changed)})",
           log=log_path.name)
    commit_and_push(f"Record {slug} as deferred (automation could not land)",
                    f"Headless add of {url} produced an unclear result.\n"
                    f"See automation/logs/{log_path.name}.", push)
    return 0


if __name__ == "__main__":
    sys.exit(main())
