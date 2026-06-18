# Reproducible builds of top open-source projects

A data-driven experiment: can we **reliably and reproducibly build** popular
open-source projects inside container images, where every tool the build touches
is pinned and fetched through Bazel rather than borrowed from the host?

The target projects live in [`top1000repos-strict.csv`](top1000repos-strict.csv),
ordered by ascending code size. We start with the smallest and work up, recording
what builds, what doesn't, and why.

## Ground rules

- **Bazel for everything.** The only host tools we rely on are `git` and `gh`
  (to fetch source) plus Bazel itself (bootstrapped via `bazelisk`). Container
  runtime, base images, language toolchains, compilers — all enter through Bazel,
  pinned by `sha256`/digest so fetches are byte-for-byte reproducible.
- **The build runs in a container.** The host's gcc/node/python/etc. must never
  leak into a project build. The orchestration layer (clone, assemble an OCI
  bundle, invoke the runtime) runs on the host as a thin harness; the *build
  itself* sees only pinned, container-provided tools.
- **Document as we go** — here, until it grows unwieldy.

## Environment (observed)

| Thing | Value |
|---|---|
| OS | Ubuntu 24.04.4, kernel 6.12, x86_64 |
| Bazel | 9.1.1 via bazelisk (`.bazelversion`), Bzlmod-only |
| Host tools used | `git`, `gh` |
| User namespaces | enabled (`user.max_user_namespaces` > 0) |
| Rootless id-mapping | **multi-id** via `newuidmap`/`newgidmap` (one-time host install of `uidmap`, see below) |

### One-time host setup (agreed exception to "git + gh only")

```
sudo apt-get install -y uidmap   # provides newuidmap/newgidmap (setuid root)
```

This is the *only* host change beyond git/gh. It enables proper multi-id rootless
mapping (container uid/gid 0 → host 1000 size 1, then 1..65536 → host
100000..165535), so package managers that `chown` to non-root ids work normally.

## Architecture

```
git/gh ──clone──▶ project source (pinned commit)
                                            │
Bazel ──http_file (pinned sha256)──▶ crun (OCI runtime, static binary)
      ──http_*    (pinned sha256)──▶ base rootfs + language toolchains
                                            │
                          harness assembles an OCI bundle
                          (rootfs + config.json + bind-mounted source)
                                            │
                          crun run ─▶ build/test executes inside,
                                       seeing only pinned tools
                                            │
                                   pass/fail + logs ─▶ data
```

## Pinned artifacts (all via Bazel `http_*`, by sha256)

| Artifact | Version | sha256 |
|---|---|---|
| crun (OCI runtime, static) | 1.28 | `2aa6b70…d01d42` |
| Ubuntu base rootfs | 24.04.3 amd64 | `6bc2cde…1874f9` |
| Node (linux-x64) | 22.14.0 | `69b09db…0437ec` |
| CA bundle (curl.se) | 2025-05-20 | `ab3ee36…4bf5db` |

System packages (git, time, …) come from a **frozen apt snapshot**:
`https://snapshot.ubuntu.com/ubuntu/20260601T000000Z`. The snapshot date + apt's
GPG signature verification make package installs reproducible; transport is https
(hence the pinned CA bundle, since the base ships none).

## The working recipe (validated end-to-end)

An OCI bundle = pinned `rootfs/` (ubuntu-base + Node overlaid at `/opt/node`,
CA bundle seeded, apt pointed at the snapshot) + a generated `config.json`:

- **multi-id mapping** (`uidMappings`/`gidMappings`: 0→1000 size 1, then
  1→100000 size 65536) — needs `newuidmap`/`newgidmap` on host.
- **full-ish capability set** (`CAP_CHOWN`, `CAP_DAC_OVERRIDE`, `CAP_SETUID/GID`,
  …) — the `crun spec --rootless` default omits `CAP_CHOWN`, which breaks dpkg.
- **host network shared** (drop the `network` namespace) so `apt`/`npm` can fetch.
- **writable root** (`root.readonly = false`).
- apt config `APT::Sandbox::User "root";` — apt's privilege-drop to `_apt` fails
  under userns, so disable it.

Inside, the build sees only pinned tools.

## Build / test model

We split the two, the Bazel-idiomatic way:

- **`bazel build //projects/<name>`** runs the project's **build** command in the
  container and captures the whole post-build working tree as
  `<name>.built.tar` — a *declared Bazel artifact*, cached and keyed on the pinned
  commit + build command + toolchain. The whole tree is the uniform,
  language-agnostic artifact: it always exists, and it's exactly what a
  reproducibility diff would compare.
- **`bazel test //projects/<name>:<name>_test`** restores that artifact into a
  *fresh* container and runs the **test** command against it — no rebuild. The
  test's exit code is the verdict, so Bazel reports green/red. `bazel test //...`
  becomes a health check across every project.
- **`bazel test //projects/<name>:<name>_smoke`** restores the artifact and runs
  an author-written `projects/<name>/smoke.sh` that drives the program *as an end
  user would* — install it, run its CLI over a fresh sample. This is black-box:
  it exercises the artifact as shipped, independent of the project's own suite
  (which may test internals or run a binary straight from source). The build tree
  is at `$PROJECT` inside the container.

Determinism is a *measurement*, not a gate: a build action produces its artifact
regardless. "Build twice, diff the tar hash → reproducible?" is a self-contained
check we can layer on later, and a build is only as reproducible as its inputs are
pinned (lockfiles / frozen dep fetches come per-project, as needed).

## Repo layout

```
MODULE.bazel              pinned inputs (crun, ubuntu-base, node, cacert) + rules_shell
harness/
  gen_config.py           generate an OCI config.json from `crun spec` + our mutations
  assemble_toolchain.sh   build a cached toolchain rootfs (one apt pass; +opt Node)
  build_artifact.sh       build step: clone, run build cmd, capture post-build tree
  test_in_container.sh    test step: restore artifact, run test cmd -> exit verdict
  smoke_in_container.sh   smoke step: restore artifact, run author smoke.sh
  defs.bzl                repo_build() + repo_test() + repo_smoke() macros
toolchains/BUILD.bazel    //toolchains:{node,python,go,rust,shell,c}_rootfs  (cached, apt-baked)
projects/<name>/BUILD.bazel   repo_build() + repo_test() + repo_smoke() per project
projects/<name>/smoke.sh      author-written end-user smoke script
```

## Usage

```
bazel build //toolchains:node_rootfs       # one-time apt bake (cached afterwards)
bazel build //projects/husky               # -> bazel-bin/projects/husky/husky.built.tar
bazel test  //projects/husky:husky_test    # restore artifact, run suite -> PASSED/FAILED
bazel test  //projects/...                 # every project's test + smoke = health check
```

The toolchain genrule and the build genrule run `local` + `requires-network` (they
invoke crun and git/apt, which Bazel's sandbox would block). Build targets start
from the cached toolchain, so Node projects do no apt. Test targets are tagged
`external` (always re-run) so the health check reflects reality, not a cached pass.

## Automated project addition

`automation/` works down the CSV unattended, one project per run. Headless
`claude` (Sonnet) does the judgement-heavy part (pin a commit, pick a toolchain,
write `BUILD.bazel` + `smoke.sh`, iterate to green or defer); the orchestrator owns
everything deterministic — selection, an **independent Bazel verification gate**,
git, and bookkeeping. It never trusts the agent's self-report: it re-runs
`bazel build` + the declared `sh_test` targets itself and only lands a project when
Bazel agrees (build green + smoke passes + any declared test passes). Anything that
can't land is recorded as `deferred` and never retried.

```
automation/
  add_next_project.py   select -> invoke claude -> verify -> commit/push -> record
  run.sh                cron wrapper (flock so ticks never overlap; sets PATH)
  prompt.md             the headless task template (repo conventions + the project)
  state.json            durable handled-record (deferrals; landed are read from BUILD)
  logs/                 per-run transcripts (gitignored)
```

```
python3 automation/add_next_project.py --dry-run   # show the next project, do nothing
automation/run.sh                                  # add the next one (commits + pushes)
automation/run.sh --no-push                         # ... but keep the commit local
```

Install on cron (the flock guard makes overlapping ticks exit immediately):

```
*/30 * * * * /home/exedev/build-top-repos/automation/run.sh >> /home/exedev/build-top-repos/automation/logs/cron.log 2>&1
```

The "next" project is the first CSV row not already handled — handled = repos with
a `projects/<name>/` dir (read from each `BUILD.bazel`'s `repo =` line) ∪ deferrals
in `state.json`. Set `CLAUDE_BUDGET_SECONDS` to change the per-project time budget
(default 5400s).

## Status

**30 projects landed, 6 deferred** (see ledger). Six cached language toolchains:
`node` (24), `python`, `go` (1.26), `rust` (1.96 + clippy/rustfmt), `shell`
(bats), `c` (autotools + g++-14 + cmake). `bazel test //projects/...` is the
cross-project health check (build+test+smoke per project). Each landed project is
a `repo_build` + `repo_test`/`repo_smoke` in `projects/<name>/BUILD.bazel`.

Recurring lessons baked into the harness: keep `.git` (some suites locate fixtures
via `git rev-parse`); provide `/etc/hosts` localhost, `tzdata`, and `git
safe.directory` (tests assume them); pin contemporaneous tool versions when a
project's deps are unpinned (e.g. `pytest<8`, `setuptools<81`); prefer a project's
offline/core test subset over network/TTY/root-coupled tests.

### Project ledger
| # | project | lang | build | test | smoke | result |
|---|---|---|---|---|---|---|
| 877 | husky | JS/npm | `npm pack` | 12-script suite vs packed tgz | install tgz → `husky init` → hook fires | ✅✅ |
| 867 | gulp | JS/npm | `npm install` | `npm test` (eslint + 42 mocha) | install gulp → run a gulpfile task | ✅✅ |
| 857 | playwright-mcp | TS/npm | (no-op; `echo OK`) | `playwright test` (Chrome) | — | ⏸️ deferred |
| 834 | pake | Rust | — | — | — | ⏸️ deferred |
| 826 | sherlock | Python | venv + `pip install` | `pytest -m "not online"` (14 pass) | `sherlock --version`/`--help` | ✅✅ |
| 767 | cheat.sh | Python | venv + `pip install -r` | `pytest lib/` (1 trivial test) | — | ⏸️ deferred |
| 761 | zx | JS/TS | esbuild + tsc | (deferred: TTY/color-coupled) | `zx -v` + run a zx script | ✅⏸️ |
| 756 | dive | Go | `go build` | `go test` (all pkgs but docker-cli) | analyze image tarball → JSON | ✅✅ |
| 746 | rustlings | Rust | `cargo build` | `cargo test --workspace` | `rustlings --version`/`--help` | ✅✅ |
| 735 | pyenv | Shell | compile realpath shim | `bats` core suite (34 tests) | `pyenv version`/`commands`/`versions` | ✅✅ |
| 725 | code-server | TS | (vendors all of VS Code) | — | — | ⏸️ deferred |
| 699 | thefuck | Python | venv + `pip install` | `pytest` unit suite (~1900) | `thefuck --version`/`--help` | ✅✅ |
| 676 | httpie | Python | venv + `pip install` | (deferred: root/net/TTY-coupled) | `http --version` + `--offline` request | ✅⏸️ |
| 669 | jq | C | autoreconf + configure + make | `make check` (8/9 groups; tzdata) | `jq` filters (`.foo`, `add`) | ✅✅ |
| 666 | gin | Go | `go build ./...` | `go test ./...` (localhost via /etc/hosts) | in-process route serves a request | ✅✅ |
| 617 | echo | Go | `go build ./...` | `go test ./...` | in-process route serves a request | ✅✅ |
| 612 | OCRmyPDF | Python | — | — | — | ⏸️ deferred |
| 611 | alacritty | Rust | — | — | — | ⏸️ deferred |
| 610 | tabby | TS | — | — | — | ⏸️ deferred |
| 606 | fzf | Go | `go build` | `go test ./src/...` | `fzf --filter` over piped input | ✅✅ |
| 564 | starship | Rust | `cargo build` | (deferred: module tests need full dev env) | `starship --version` + `prompt` | ✅⏸️ |
| 562 | btop | C++ | `make` (g++-14, C++23) | (no upstream test runner) | `btop --version`/`--help` | ✅✅ |
| 558 | rich | Python | venv + `pip install` | `pytest` (~960 tests) | render a table + `python -m rich` demo | ✅✅ |
| 551 | glances | Python | venv + `pip install` | `pytest tests/test_core.py` (52) | `--version` + one-shot CPU reading | ✅✅ |
| 485 | rtk | Rust | `cargo build` | `cargo test` (2199) | `rtk --version`/`--help` | ✅✅ |
| 479 | scrapy | Python | venv + `pip install` | (deferred: twisted/network suite) | `scrapy version` + `startproject` | ✅⏸️ |
| 461 | Xray-core | Go | `go build` | (deferred: needs geoip/geosite data) | `xray version` | ✅⏸️ |
| 435 | syncthing | Go | `go run build.go build` | `go test -short ./lib/...` (40 pkgs) | `syncthing --version` | ✅✅ |
| 422 | sing-box | Go | `go build` | (deferred: netlink/real-TLS integ.) | `sing-box version`/`--help` | ✅⏸️ |
| 404 | textual | Python | venv + `pip install` | `pytest` (~3005; excl. snapshot/optional) | run a headless Textual app via pilot | ✅✅ |
| 357 | black | Python | venv + `pip install` | `pytest` (~465) | format `x=1` → `x = 1` via the CLI | ✅✅ |
| 311 | cli/cli | Go | `go build` | (deferred: root-permission tests) | `gh --version`/`--help` | ✅⏸️ |
| 249 | yt-dlp | Python | venv + `pip install` | `pytest -m "not download"` (~886) | `yt-dlp --version`/`--help` | ✅✅ |
| 215 | redis | C | `make` | (deferred: Tcl integration suite) | start server → ping + set/get | ✅⏸️ |
| 133 | ruff | Rust | `cargo build` | (deferred: huge workspace suite) | `ruff --version` + lint a snippet | ✅⏸️ |
| 45 | cpython | C | `./configure && make` | (deferred: huge regression suite) | run built `python` (version + eval) | ✅⏸️ |
| 319 | esbuild | Go | `go build` | `go test ./...` | minify `let x = 1 ;` → `let x=1;` | ✅✅ |

**playwright-mcp — deferred (needs a browser toolchain).** Spike confirmed
`npm ci` + `npx playwright install --with-deps` work against our snapshot apt, but
the browsers are **646M** (Chrome + chromium) vs **46M** of actual deps. The right
shape is a cached `playwright_rootfs` toolchain holding the browsers + system-deps
(downloaded once, shared by build+test), keeping the per-build artifact ~46M.
Deferred until we choose to invest in that toolchain.

**cheat.sh — deferred (server + data-fetch heavy).** Deps install (the
`PyICU`/`pycld2`/`polyglot` C-extensions build with `build-essential` +
`python3-dev` + `libicu-dev`), but the only reproducible test is one trivial unit
test; the real suite (`tests/run-tests.sh`) boots the cheat.sh server with redis
and needs `lib/fetch.py fetch-all` (cloning dozens of external cheat-sheet repos).
A custom toolchain to land one trivial test, with no honest offline smoke — skipped.

**code-server — deferred (vendors all of VS Code).** Its build (`ci/build/build-code-server.sh`)
compiles the bundled `microsoft/vscode` submodule — a multi-GB, long build. Out of
scope for now.

**pake — deferred (Tauri desktop GUI app; requires WebkitGTK).** Pake wraps web
pages into desktop apps via Tauri v2. On Linux, Tauri v2 requires
`libwebkit2gtk-4.1-dev`, `libgtk-3-dev`, and related GTK/display-server headers
for compilation — none are present in the `rust_rootfs` toolchain. The resulting
app creates an OS window to display the wrapped URL; no meaningful headless
execution exists. Same category as alacritty and tabby.

**GUI / heavy-system-dep deferrals.** alacritty (OpenGL terminal), tabby
(Electron), and pake (Tauri) are GUI apps with no meaningful headless run.
OCRmyPDF is feasible but heavy: it needs OCR engines (tesseract, ghostscript,
unpaper, qpdf, …) and a large real-OCR test suite — revisitable if we invest in
an OCR toolchain.

### Next
1. Keep working down the CSV: one `repo_build` + `repo_test`/`repo_smoke` per
   project — now driven by `automation/` (headless Sonnet + a Bazel verification
   gate) on a cron. Heavy/browser/GUI projects → cache the weight in a toolchain
   or defer.
2. Optional **reproducibility check** target: build twice, diff the artifact hash
   (turns the "determinism is measured" idea into data per project).
3. Revisit deferrals worth a toolchain investment: a browser toolchain
   (playwright-mcp) and an OCR toolchain (OCRmyPDF).
4. Consider `rules_oci` pull-by-digest as an optional fast path for common stacks.

## Notes / decisions

- **Why crun:** static binary, no host libc dependency, trivially pinnable as a
  single file — cleaner than building a runtime from source. Revisit if needed.
- **System deps = pinned base + snapshot apt** (chosen over pinned-tarballs-only
  and live-apt). Uniform across languages, reproducible to a snapshot date, low
  per-project effort.
- **Harness vs. build boundary:** host shell/python used to *orchestrate* is
  acceptable; host compilers/runtimes used to *build a project* are not.
- **Per-language toolchains, selected per project.** `repo_build/test/smoke` take
  a `toolchain` arg (default `//toolchains:node_rootfs`). Heavy shared weight
  (Node, Python, and later browsers/Rust) lives in a cached toolchain; per-build
  artifacts stay lean. Adding a language = one more `assemble_toolchain.sh`
  genrule with a different apt set.
- **Python pattern:** build into a `.venv` *inside* the project tree (so it's
  captured in the artifact); build and test both mount at `/work/<name>`, keeping
  the venv's absolute paths valid. Prefer a project's **offline** test subset when
  it has one — online tests that hit live services aren't reproducible.
- **Scratch lives under Bazel, and cleans itself.** Each action's working rootfs
  goes in a Bazel-managed dir (`$TEST_TMPDIR` for tests, `$TMPDIR` for genrules),
  not `/tmp`. Cleanup must handle files the container `chown`ed to mapped sub-uids
  — a plain `rm` (and even `bazel clean`, which runs as your uid) can't remove
  sub-uid-owned mode-700 dirs. The EXIT trap removes the rootfs via
  `unshare --user --map-root-user --map-auto rm -rf` (a userns where those sub-uids
  are mapped, so we're root over them). Runners must **not** `exec` crun, or the
  trap never fires. Net: nothing sub-uid-owned survives an action, so the tree
  stays clean and `bazel clean --expunge` works normally.
