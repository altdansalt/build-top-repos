You are adding one project to a Bazel repo that **reproducibly builds, tests, and
smoke-tests popular open-source projects inside a pinned container**. You are
running headless and autonomous. Work entirely within the repo at the current
working directory. Do NOT run any `git` command — a separate harness handles git,
verification, and recording. Your job is to produce the project files, get Bazel
green (or cleanly defer), and write a result file.

## The project to add
- repo_url:        {{REPO_URL}}
- language:        {{LANGUAGE}}
- description:     {{DESCRIPTION}}
- rank_code_size:  {{RANK}}   ← use this exact number as the `#` in the README ledger row
- evidence:        {{EVIDENCE}}

## Learn the pattern first (do this before writing anything)
1. Read `README.md` in full — especially **The working recipe**, **Build / test
   model**, **Repo layout**, the **recurring lessons** paragraph under Status, and
   **Notes / decisions**. The deferral conventions and gotchas are all there.
2. Read `harness/defs.bzl` for the exact `repo_build` / `repo_test` / `repo_smoke`
   macro signatures.
3. Read a couple of existing projects whose language matches this one, as
   templates — both their `BUILD.bazel` and `smoke.sh`:
   - Python: `projects/black`  (Go: `projects/fzf`, `projects/echo`)
   - Rust:   `projects/rtk`     (C/C++: `projects/jq`, `projects/redis`, `projects/btop`)
   - JS/TS:  `projects/husky`   (Shell: `projects/pyenv`)

## What "adding a project" means
Create `projects/<name>/BUILD.bazel` and (when it lands) `projects/<name>/smoke.sh`,
following the established shape exactly:

- `<name>` is a short, lowercase, filesystem-safe slug for the project.
- `repo_build(name, repo, commit, build, toolchain)` — pick a **specific recent
  upstream commit SHA** to pin (`git ls-remote {{REPO_URL}}` for the default-branch
  HEAD is fine). `build` is a single shell command run in the container.
- `repo_test(name, built, test, toolchain)` — the project's own suite, run against
  the built artifact. Prefer an **offline / core** subset; exclude tests that need
  the network, a TTY, root, or services. Omit this target entirely if the suite
  can't run reproducibly here (this is how "test deferred" is expressed).
- `repo_smoke(name, built, toolchain)` + a `smoke.sh` — a **black-box** end-user
  exercise of the built program (the built tree is at `$PROJECT` inside the
  container). Keep it small and deterministic. Landing **requires** an honest smoke.
- `toolchain` must be one of the **already-cached** toolchains — choose by language:
  `//toolchains:node_rootfs` (JS/TS), `//toolchains:python_rootfs`,
  `//toolchains:go_rootfs`, `//toolchains:rust_rootfs`, `//toolchains:shell_rootfs`,
  `//toolchains:c_rootfs` (C/C++). Do not invent a new toolchain.

Apply the recurring lessons from the README (keep `.git`; provide `/etc/hosts`
localhost / tzdata / `git safe.directory` when a suite needs them; pin
contemporaneous tool versions when deps are unpinned; prefer the offline subset).

## Build and verify with Bazel (iterate until green)
- `bazel build //projects/<name>`                      → produces `<name>.built.tar`
- `bazel test //projects/<name>:<name>_smoke`           → smoke must pass
- `bazel test //projects/<name>:<name>_test`            → if you declared a test
Iterate on the build/test/smoke commands until they pass. The landing bar is:
**build succeeds + smoke passes + any declared test passes.** Test may be deferred.

## When to DEFER instead of land
Defer (do not force it) when the project is a GUI/desktop/browser/Electron app with
no meaningful headless run, needs a **new toolchain** we don't have cached (browsers,
OCR engines, CUDA, Android SDK, etc.), vendors a huge multi-GB build, or otherwise
can't be built+smoked reproducibly with the cached toolchains. Toolchain investment
is a human decision — defer rather than build one.

- **Test-only deferral** (project still lands): just omit `repo_test`, and note the
  reason in the README ledger row.
- **Whole-project deferral**: create **no** `projects/<name>/` directory. Only add a
  short deferral paragraph + ledger row to `README.md` explaining why.

## Update the README
Either way, update `README.md`: add a row to the **Project ledger** table (use the
`rank_code_size` value given above as the `#`), and if it landed,
bump the "**N projects landed**" count in the Status section. Match the existing
table format and tone. For deferrals, add a short explanatory paragraph like the
existing ones.

## Finally: write the result file (REQUIRED)
Write `{{RESULT_PATH}}` as JSON, then stop. Do not run git. Schema:

```json
{
  "repo_url": "{{REPO_URL}}",
  "project": "<slug or null if whole-project deferral>",
  "status": "landed" | "deferred",
  "pinned_commit": "<sha or null>",
  "targets": {"build": "pass|fail|absent", "test": "pass|absent|deferred", "smoke": "pass|absent"},
  "commit_subject": "Add <name> (...)  — or —  Defer <name> (...)",
  "commit_body": "1-3 line summary in the style of existing git commits",
  "reasoning": "why it landed as shaped, or why it was deferred"
}
```

The harness will independently re-run Bazel to confirm your result before
committing, so be honest: if it doesn't actually build+smoke green, mark it
deferred with the reason rather than claiming it landed.
