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
  priority.txt          lands-first queue (high-confidence projects, attempted first)
  state.json            durable handled-record (deferrals; landed are read from BUILD)
  logs/                 per-run transcripts (gitignored)
  tail.sh               follow logs: tail.sh [cron|claude|raw]
```

```
python3 automation/add_next_project.py --dry-run   # show the next project, do nothing
automation/run.sh                                  # add the next one (commits + pushes)
automation/run.sh --no-push                         # ... but keep the commit local
```

Install on cron (the flock guard makes overlapping ticks exit immediately):

```
*/10 * * * * /home/exedev/build-top-repos/automation/run.sh >> /home/exedev/build-top-repos/automation/logs/cron.log 2>&1
```

**Selection** picks the next *unhandled, buildable* project (handled = repos with a
`projects/<name>/` dir, read from each `BUILD.bazel`'s `repo =` line, ∪ deferrals in
`state.json`), ordered **lands-first**: repos listed in `priority.txt` come before
the rest, which follow CSV order. Two filters keep ticks productive:

- **Toolchain pre-filter.** A pending project whose `language` has no cached
  toolchain (C#/Java/Ruby/Zig/Clojure/Dart/V/…) is skipped without spending a
  claude call — the prompt forbids building new toolchains, so it could only defer.
  Reversible: add a toolchain + a `LANG_TOOLCHAIN` entry and it re-enters the queue.
- **`priority.txt`.** A curated list of high-confidence lands attempted first, so
  early ticks do real porting instead of grinding through predictable deferrals
  (GUI/desktop/heavy apps still cost a tick — Sonnet judges those case by case).

Set `CLAUDE_BUDGET_SECONDS` to change the per-project time budget (default 5400s).

## Status

**73 projects landed, 22 deferred** (see ledger). Six cached language toolchains:
`node` (26), `python`, `go` (1.26), `rust` (1.96 + clippy/rustfmt), `shell`
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
| 626 | sniffnet | Rust | — | — | — | ⏸️ deferred |
| 620 | lossless-cut | TS | — | — | — | ⏸️ deferred |
| 617 | echo | Go | `go build ./...` | `go test ./...` | in-process route serves a request | ✅✅ |
| 612 | OCRmyPDF | Python | — | — | — | ⏸️ deferred |
| 611 | alacritty | Rust | — | — | — | ⏸️ deferred |
| 610 | tabby | TS | — | — | — | ⏸️ deferred |
| 606 | fzf | Go | `go build` | `go test ./src/...` | `fzf --filter` over piped input | ✅✅ |
| 581 | scrcpy | C | — | — | — | ⏸️ deferred |
| 564 | starship | Rust | `cargo build` | (deferred: module tests need full dev env) | `starship --version` + `prompt` | ✅⏸️ |
| 562 | btop | C++ | `make` (g++-14, C++23) | (no upstream test runner) | `btop --version`/`--help` | ✅✅ |
| 558 | rich | Python | venv + `pip install` | `pytest` (~960 tests) | render a table + `python -m rich` demo | ✅✅ |
| 556 | one-api | Go | apt gcc+sqlite3-dev; placeholder `web/build`; CGO `go build` | (deferred: integration suite needs live DB + Redis) | `one-api --version`/`--help` | ✅⏸️ |
| 551 | glances | Python | venv + `pip install` | `pytest tests/test_core.py` (52) | `--version` + one-shot CPU reading | ✅✅ |
| 506 | mole | Shell/Go | `go build` (analyze-go + status-go) | `go test ./...` (status pkg + internal; darwin tests auto-skipped) | `status-go --json` → JSON with cpu+memory fields | ✅✅ |
| 504 | gpt4free | Python | venv + `pip install` | (deferred: all tests require live AI provider endpoints) | `import g4f` + Client + Provider | ✅⏸️ |
| 499 | qlib | Python | apt python3-dev+g++; venv + cython/numpy<2.0 + `pip --no-build-isolation` | (deferred: all tests need downloaded financial market data) | `import qlib` + Cython rolling/expanding extensions | ✅⏸️ |
| 492 | hexo | TS/npm | `npm ci && tsc -b` | `npm test` (1274; FORCE_COLOR for ANSI assertions) | `hexo version` + `hexo help` | ✅✅ |
| 489 | uptime-kuma | JS/npm | `npm ci && npm run build` (vite) | (deferred: test suite drives the live server via integration tests; no offline unit subset) | start Node.js server → HTTP response on port 3001 | ✅⏸️ |
| 485 | rtk | Rust | `cargo build` | `cargo test` (2199) | `rtk --version`/`--help` | ✅✅ |
| 479 | scrapy | Python | venv + `pip install` | (deferred: twisted/network suite) | `scrapy version` + `startproject` | ✅⏸️ |
| 467 | dokku | Shell/Go | compile Go common plugin helpers (prop, common) | (deferred: all 108 bats + Go tests require a running Docker daemon) | `dokku version` via bash CLI with minimal env | ✅⏸️ |
| 464 | manim | Python | apt libcairo2-dev/libpango1.0-dev/pkgconf/python3-dev; venv + `pip install`; bundle runtime .so into `.libs/` | (deferred: test suite renders animations and is coupled to snapshot comparisons) | `manim --version` + Cairo render SmokeCircle scene to PNG (headless) | ✅⏸️ |
| 461 | Xray-core | Go | `go build` | (deferred: needs geoip/geosite data) | `xray version` | ✅⏸️ |
| 452 | raylib | C | apt X11+GL dev headers; `cmake -B build -DBUILD_EXAMPLES=OFF && cmake --build -j8` | (deferred: all test programs open a window; no offline unit subset) | verify `libraylib.a`; compile + run raymath.h vector/matrix math | ✅⏸️ |
| 442 | new-api | Go | placeholder `web/{default,classic}/dist`; `go build` (pure Go; glebarez/sqlite) | `go test` (common, dto, billingexpr, setting subset) | `new-api --version`/`--help` | ✅✅ |
| 440 | ultralytics | Python | apt libgl1+libglib2.0-0; CPU-only torch+torchvision from whl index; venv + pip install; bundle libGL/glib .so into .libs/ | (deferred: all tests download model weights; no offline subset) | `yolo --version`/`--help` | ✅⏸️ |
| 435 | syncthing | Go | `go run build.go build` | `go test -short ./lib/...` (40 pkgs) | `syncthing --version` | ✅✅ |
| 422 | sing-box | Go | `go build` | (deferred: netlink/real-TLS integ.) | `sing-box version`/`--help` | ✅⏸️ |
| 419 | browser-use | Python | venv + `pip install` | (deferred: needs Playwright browser + LLM API keys) | `import browser_use` + version | ✅⏸️ |
| 407 | mempalace | Python | venv + `pip install` | (deferred: some tests download ChromaDB ONNX model ~79 MB at test time; no offline marker) | `mempalace --version`/`--help` | ✅⏸️ |
| 404 | textual | Python | venv + `pip install` | `pytest` (~3005; excl. snapshot/optional) | run a headless Textual app via pilot | ✅✅ |
| 400 | openpilot | Python | — | — | — | ⏸️ deferred |
| 398 | 3x-ui | Go | apt gcc+sqlite3-dev; stub `internal/web/dist`; CGO `go build` | `go test -count=1 ./...` (103 files; in-memory SQLite; mocked HTTP) | `3x-ui -v` | ✅✅ |
| 391 | imhex | C++ | — | — | — | ⏸️ deferred |
| 386 | v2ray-core | Go | `go build` | (deferred: needs geoip/geosite data) | `v2ray version`/`help` | ✅⏸️ |
| 382 | xx-net | Python | venv + `pip install` (pyOpenSSL/babel/jinja2) | (deferred: all tests hit live proxy or external net; no offline subset) | version + noarch lib imports (utils/dnslib/xlog) | ✅⏸️ |
| 366 | babel | TS/Yarn | yarn install + `set-module-type.js` + `gulp build-vendor` + `gulp build-no-bundle` (7.x pinned; Node 22.14.0 incompat with Babel 8) | (deferred: Jest + git-fetched test262/TS/Flow corpus; no offline subset) | `--version` + `@babel/core` `transformSync` | ✅⏸️ |
| 364 | freqtrade | Python | venv + `pip install -r requirements.txt` (ta-lib==0.6.8 ships manylinux wheels) | `pytest` (~3800 offline; excl. exchange_online/freqai/optimize/plot/pip-audit; mocked exchange) | `freqtrade --version`/`--help` | ✅✅ |
| 361 | parcel | JS/Yarn | yarn install (Yarn 4 bundled) + npm-fetch prebuilt `@parcel/rust-linux-x64-gnu` (yarn.lock maps it to empty workspace stub; override with real npm pkg) | (deferred: `test:unit` includes `cargo test`; mocha alone unclear without native build from source) | `--version` + bundle a trivial Node.js project | ✅⏸️ |
| 343 | dioxus | Rust | apt libgit2-dev+pkg-config; `cargo build -p dioxus-cli` | (deferred: wasm32/browser/tool-download suite; no offline subset) | `dx --version`/`--help` | ✅⏸️ |
| 357 | black | Python | venv + `pip install` | `pytest` (~465) | format `x=1` → `x = 1` via the CLI | ✅✅ |
| 311 | cli/cli | Go | `go build` | (deferred: root-permission tests) | `gh --version`/`--help` | ✅⏸️ |
| 249 | yt-dlp | Python | venv + `pip install` | `pytest -m "not download"` (~886) | `yt-dlp --version`/`--help` | ✅✅ |
| 257 | webpack | JS/npm | `npm install` | jest unit suite (63 tests; `--testPathPatterns unittest`) | bundle a two-file JS project via the JS API; run the bundle | ✅✅ |
| 215 | redis | C | `make` | (deferred: Tcl integration suite) | start server → ping + set/get | ✅⏸️ |
| 133 | ruff | Rust | `cargo build` | (deferred: huge workspace suite) | `ruff --version` + lint a snippet | ✅⏸️ |
| 45 | cpython | C | `./configure && make` | (deferred: huge regression suite) | run built `python` (version + eval) | ✅⏸️ |
| 319 | esbuild | Go | `go build` | `go test ./...` | minify `let x = 1 ;` → `let x=1;` | ✅✅ |
| 154 | uv | Rust | `cargo build --bin uv` | (deferred: integration-heavy, network-required) | `uv --version`/`--help`/`uv pip --help` | ✅⏸️ |
| 381 | helix | Rust | `cargo build` | (deferred: TUI integration suite) | `hx --version`/`--help` | ✅⏸️ |
| 371 | fish | Rust | `cargo build` | (deferred: CMake-driven test suite; no clean offline subset) | `fish --version` + `fish -c 'echo ...'` | ✅⏸️ |
| 146 | gemini-cli | TS/npm | `npm ci && node scripts/build.js` | (deferred: snapshot+docker+TTY-coupled suite) | `gemini --version`/`--help` | ✅⏸️ |
| 218 | ollama | Go+C++ | — | — | — | ⏸️ deferred |
| 195 | qdrant | Rust | `apt cmake+protoc && cargo build --bin qdrant` | (deferred: integration tests need live server + REST/gRPC endpoints) | `qdrant --version`/`--help` | ✅⏸️ |
| 105 | tinygrad | Python | venv + `pip install` + numpy | (deferred: unit suite needs CLANG/GPU backend or torch; gguf tests fetch models) | tensor add via `DEV=PYTHON` numpy backend | ✅⏸️ |
| 373 | json | C++ | `cmake -DJSON_BuildTests=ON && cmake --build -j8` | `ctest` unit suite (~150 tests, all offline) | compile snippet + parse/dump round-trip | ✅✅ |
| 153 | numpy | Python | apt gcc/ninja/python3-dev; venv + `scipy-openblas64` + `pip --no-build-isolation` | (deferred: thousands of tests; no fast offline subset) | `import numpy`; array add + dot product | ✅⏸️ |
| 75 | duckdb | C++ | `cmake -DCMAKE_BUILD_TYPE=Release -DCMAKE_CXX_COMPILER=g++-14 -DBUILD_UNITTESTS=OFF && cmake --build -j8` | (deferred: large C++ test suite) | `duckdb --version` + SQL queries | ✅⏸️ |
| 19 | php-src | C | apt re2c; buildconf + configure (no libxml/sqlite3/dom; HEAD removed pre-gen lexers + bundled SQLite) + make | (deferred: ~15 000-test suite) | `sapi/cli/php --version` + eval PHP expressions | ✅⏸️ |
| 244 | zellij | Rust | apt cmake+perl; `cargo build --no-default-features --features vendored_curl,web_server_capability` (pre-compiled WASM plugins embedded from assets) | (deferred: integration suite drives TUI sessions via fake PTY; no offline unit subset) | `zellij --version`/`--help` | ✅⏸️ |
| 563 | openscreen | TS | — | — | — | ⏸️ deferred |
| 353 | qbittorrent | C++ | — | — | — | ⏸️ deferred |
| 344 | zen-browser | JS | — | — | — | ⏸️ deferred |
| 342 | pixijs | TS | — | — | — | ⏸️ deferred |
| 322 | ecc | JS/npm | `npm install` | CI validators (agents/commands/rules/skills/hooks/catalog/registry; deferred: hooks+Python-invoking tests need python3) | `ecc --help` + `ecc catalog` | ✅⏸️ |
| 315 | astro | TS/pnpm | pnpm@11.5.0 install + turbo build (`astro` + `@astrojs/*`; tsc + WASM compiler copy) | (deferred: integration tests need Playwright browser; e2e needs Firefox/Chrome) | `astro --version` + build a minimal static page (WASM compiler + Vite pipeline) | ✅⏸️ |
| 314 | autogen | Python | venv + `pip install` (monorepo: autogen-core + autogen-agentchat from `python/packages/`) | `pytest` autogen-core unit suite (215; excl. code-executor/model-context/regressions) | `import autogen_core`/`autogen_agentchat` + version + basic API objects | ✅✅ |
| 303 | spacy | Python | apt python3-dev+g++; venv + `pip install` + explicit click (typer 0.12+ dropped click as hard dep; spaCy code imports it directly) | (deferred: test suite fixtures load NLP models; no clean offline subset) | `spacy info` + blank-model tokenization from /tmp | ✅⏸️ |
| 300 | aseprite | C++ | — | — | — | ⏸️ deferred |
| 299 | kitty | Python | — | — | — | ⏸️ deferred |
| 288 | electron | C++ | — | — | — | ⏸️ deferred |
| 287 | spacedrive | Rust | — | — | — | ⏸️ deferred |
| 278 | astrbot | Python | venv + `pip install` | (deferred: async pytest-asyncio suite across IM-platform adapters and LLM providers; many tests mock extensively but asyncio-mode tuning and service coupling make offline subset risky) | `astrbot --version` + pipeline stage bootstrap | ✅⏸️ |
| 271 | hoppscotch | TS/pnpm | pnpm@10.33.4 install (--ignore-scripts skips native backend deps) + build @hoppscotch/data, @hoppscotch/js-sandbox, @hoppscotch/cli | (deferred: vitest suite exercises faraday-cage/QuickJS sandbox execution; no clean offline subset) | `hopp --ver` + `--help` (test command listed) | ✅⏸️ |
| 253 | meteor | JS/npm | apt curl; `(cd tools/unit-tests && npm install) && METEOR_ALLOW_SUPERUSER=1 ./meteor --arch` — downloads pre-built dev bundle (~160 MB: Node 22 + Meteor tool packages) from CloudFront | 3 Jest unit tests (tools/cli/examples, tools/runners/run-app, tools/utils/utils; all heavy deps mocked) | `./meteor --arch` → `os.linux.x86_64` via dev_bundle/bin/node + tools/index.js | ✅✅ |
| 247 | immich | TS/pnpm | pnpm@11.6.0 filtered install (`--filter @immich/cli...`; 315 pkgs; `--ignore-scripts` skips server-only bcrypt/sharp) + SDK `tsc` + CLI `vite build` (rolldown; 693 kB bundle) | `vitest run` (42; file-crawl utils + upload-command mocks; all offline) | `immich --version`/`--help` | ✅✅ |
| 240 | continue | TS/npm | packages/* `npm install + tsc` in dep order (config-types, llm-info, terminal-security, fetch, config-yaml, openai-adapters); core `npm install` (70 deps; esbuild inlines source); CLI `npm install + node build.mjs` (esbuild → 12.7 MB ESM bundle) | (deferred: vitest 16-file suite mocks API calls but TypeScript resolution across core's 70 transitive deps risks container failures; no clean offline subset) | `cn --version`/`--help` | ✅⏸️ |
| 239 | goose | Rust | apt pkg-config+libsqlite3-dev; `cargo build --bin goose --no-default-features --features portable-default` (skips local-inference/llama-cpp-2 + system-keyring/dbus; pure-Rust feature set) | (deferred: all tests require live LLM API keys; no offline subset) | `goose --version`/`--help` | ✅⏸️ |
| 238 | podman | Go | `CGO_ENABLED=0 go build -tags remote,exclude_graphdriver_btrfs,containers_image_openpgp` (remote-client variant; vendored deps; pure-Go) | (deferred: suite requires running container daemon, root/deep userns, cgroups v2, and kernel services; no offline unit subset) | `podman --version`/`--help` | ✅⏸️ |
| 220 | obs-studio | C | — | — | — | ⏸️ deferred |

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

**sniffnet — deferred (GUI network monitor; needs libpcap + GTK + display).** sniffnet
is an iced/wgpu GUI application that captures packets via libpcap. On Linux, compiling
it requires `libpcap-dev` (pcap crate), `libgtk-3-dev` (rfd native-file-dialog crate),
and X11/Wayland dev headers (winit/iced) — none present in `rust_rootfs`. The app opens
a graphical window for all normal operation; there is no headless mode. Same category as
alacritty, pake, and tabby.

**scrcpy — deferred (Android GUI client; needs Android SDK + display).** scrcpy has two halves: a Java server APK (built with Gradle + Android SDK, deployed to the device via adb) and a C client (built with meson, links SDL2 for display and FFmpeg for video decoding). Neither half is buildable without new tooling — the server requires the Android SDK (not present in any cached toolchain) and the client requires SDL2 headers plus FFmpeg/libav dev packages not in `c_rootfs`. At runtime the client opens a window mirroring the device screen; there is no headless or CLI mode. Requires a connected Android device or emulator for any meaningful operation.

**lossless-cut — deferred (Electron GUI video editor; no headless mode).** lossless-cut
is an Electron + React desktop application built with `electron-vite`. Its renderer
targets Chrome APIs (`chrome148`), its `postinstall` step downloads native Electron
binaries via `electron-builder install-app-deps`, and the packaged app opens a GUI
window for all normal operation — lossless video/audio editing. There is no CLI or
headless mode. Same category as tabby, pake, and alacritty.

**ollama — deferred (CGo + cmake/C++ build; needs combined Go+C++ toolchain).** Ollama's
main binary imports `runner`, which in turn imports `x/imagegen` and `x/mlxrunner` — both
packages contain CGo directives (`#cgo LDFLAGS: -lstdc++`) and depend on C headers generated
by `go generate ./...`. Compiling those requires `g++` and the generated wrapper headers.
Additionally, the `llama/server` component is built separately via CMake before the Go
link step. Neither `go_rootfs` (no C++ compiler or cmake) nor `c_rootfs` (no Go) covers
the full build; a new combined `go_c_rootfs` toolchain holding Go + cmake + g++ would be
required. That toolchain investment is a human decision — deferred.

**openscreen — deferred (Electron screen-recording GUI app; native screen-capture modules).** openscreen is a screen-recording and demo-creation app (alternative to Screen Studio). Its repo contains `CMakeLists.txt` and `Package.swift` (native macOS screen-capture modules built around AVFoundation/ScreenCaptureKit) alongside a `package.json` Electron frontend — the classic Electron + native addon shape. The app opens a GUI window for recording and editing; there is no headless or CLI mode. Same category as lossless-cut, tabby, pake, and alacritty.

**openpilot — deferred (automotive ADAS OS; 22+ vendored native libs; no headless CLI).** openpilot is an open-source operating system for driver-assistance systems, designed to run on comma.ai hardware (comma 3/3X) and interface with a car's CAN bus via panda. Its `pyproject.toml` declares no scripts or entry-points — there is no `openpilot --version` or standalone CLI. The build pulls 22+ vendored C/C++ libraries (FFmpeg, Eigen, ZeroMQ, libjpeg, compiler toolchains) from a custom upstream repository, plus `pycapnp` (requires compiled capnproto headers) and a MetaDrive simulator for tools — effectively a multi-GB native build chain on top of the Python layer. No meaningful headless smoke exists: normal operation manages multiple ADAS subprocesses talking to car hardware, and the test suite requires hardware replay data or hardware-in-the-loop. Deferred pending a purpose-built toolchain that vendors the native deps.

**imhex — deferred (Dear ImGui GUI hex editor; OpenGL + GLFW + display required).** ImHex is a graphical hex editor built on Dear ImGui with OpenGL 3.3 and GLFW for window management. Compiling it requires a large set of GUI dev headers (libgl-dev, libglew-dev, libglfw3-dev, and many more) plus dozens of C++ libraries fetched via CMake FetchContent during configuration. The application initialises an OpenGL context and GLFW window before doing anything useful — running it without a display server fails immediately at context creation; there is no `--version` early-exit, headless mode, or standalone CLI. Same category as alacritty and sniffnet.

**zen-browser/desktop — deferred (full Firefox-fork browser; no headless CLI; browser toolchain required).** zen-browser is a graphical web browser based on Firefox ESR, built with the Mozilla build system (mach/configure/make). Building it requires bootstrapping clang, a specific Python version, Rust, Node.js, and a large set of C/C++ libraries — the full build downloads gigabytes of dependencies and takes multiple hours. The resulting application is a display-server-dependent GUI browser; there is no CLI entry point and no headless operation mode (the `--version` flag is not available without a running display). Same category as playwright-mcp (browser toolchain required) and alacritty.

**qBittorrent — deferred (Qt6 runtime dep; needs c_qt_rootfs toolchain).** qBittorrent's
headless variant (`qbittorrent-nox`) avoids a display server but still uses Qt6 internally:
`libQt6Core.so.6` is an unconditional dependency and itself transitively requires the
~36 MB ICU data library (`libicudata.so.74`) plus `libQt6Network`, `libQt6Sql`,
`libQt6Xml`, and `libtorrent-rasterbar` at runtime. None of these are in `c_rootfs`.
Bundling them at build time would produce an oversized artifact (~80-100 MB of shared
libs); running `apt-get install` inside the smoke step risks the 300 s `sh_test`
timeout (ICU data alone is ~36 MB to download). Ubuntu's Qt6 packages do not ship
static libraries, so static linking without building Qt6 from source is not available.
A dedicated `c_qt_rootfs` toolchain baking Qt6 + libtorrent-rasterbar is the right
investment — deferred until that toolchain is built.

**pixijs — deferred (browser WebGL graphics library; Electron test runner; no headless mode).** PixiJS is a 2D WebGL/Canvas rendering engine for browsers. Its test suite uses `@pixi/jest-electron` (a custom Jest runner that boots Electron to provide a real WebGL + Canvas 2D context) — incompatible with `node_rootfs`. The built output (`lib/index.js`, `dist/pixi.min.js`) targets browsers: importing it in plain Node.js immediately fails on missing `window`/`document`/`WebGLRenderingContext` APIs. There is no CLI entrypoint, no server-side/headless rendering mode, and no honest smoke possible without a browser context. Same category as playwright-mcp (browser toolchain required).

**aseprite — deferred (GUI pixel art editor; X11 display required even in batch mode).** Aseprite is an animated sprite editor whose GUI framework (laf) unconditionally opens an X11 display connection at program startup on Linux — before `main()` even calls `app_main()`. The laf `common/main.cpp` entry point runs `const os::X11 x11;` which calls `XOpenDisplay(nullptr)` regardless of whether `--batch` mode is requested. Without a `$DISPLAY` set, this crashes immediately, making even `aseprite --version` impossible in our headless container. While the binary compiles fine with X11 dev headers (libx11-dev + libxcursor-dev + libxi-dev + libxrandr-dev, all installable from the snapshot), there is no honest smoke without a virtual framebuffer (Xvfb). The default Skia rendering backend also requires prebuilt Skia binaries (~150 MB, not in any Ubuntu package); `LAF_BACKEND=none` avoids Skia but not the X11 runtime requirement. Same category as alacritty, imhex, and tabby.

**kitty — deferred (GPU terminal emulator; OpenGL + X11 required at build and runtime).** kitty is a GPU-accelerated terminal emulator whose C extension (`fast_data_types.so`) links against `libGL.so`, `libX11.so`, and associated X11 libs. Building requires `libgl-dev`, `libx11-dev`, `libxrandr-dev`, `libxi-dev`, `libfontconfig-dev`, and GLFW C sources — an extensive apt set not present in `python_rootfs`. Crucially, `kitty/main.py` performs top-level imports that load `fast_data_types.so` before argument parsing, so even `kitty --version` would fail at dynamic-linker startup in the smoke container (where libGL/libX11 are absent). Bundling the full GL+X11+GLFW stack is technically possible but involves far more transitive libs than e.g. manim's Cairo bundle, with no meaningful headless operation to demonstrate at the end — kitty's entire purpose is to open a GPU-rendered terminal window. Same category as alacritty (OpenGL terminal).

**electron — deferred (Chromium+Node.js desktop runtime; depot_tools/gclient multi-GB build chain required).** electron/electron is the Electron framework itself — it merges Chromium and Node.js into a single distributable runtime. Building it from source requires Google's `depot_tools` (`gn` + `ninja`) and `gclient sync` to check out the full Chromium source tree (~20 GB of C++), then a multi-hour compilation step not covered by any cached toolchain (`c_rootfs` has autotools/cmake/g++ but not gn/ninja or the Chromium build infrastructure). Even if compiled, the resulting binary is a full browser runtime that opens a Chromium window for all meaningful operation — `electron --version` works but is not an honest smoke without the build first succeeding. Same build-chain category as zen-browser (Mozilla build system) and code-server (vendors all of VS Code).

**spacedrive — deferred (Tauri desktop GUI file explorer; WebkitGTK + GTK3 required).** Spacedrive is a cross-platform file explorer built on Tauri v1, with a React/TypeScript frontend and a Rust virtual-distributed-filesystem backend (`sd-core`). On Linux, Tauri requires `libwebkit2gtk-4.0-dev` (or `libwebkit2gtk-4.1-dev`) and `libgtk-3-dev` for compilation — none are present in `rust_rootfs`. The application's primary interface is a graphical desktop window; there is no CLI or headless server mode that constitutes an honest smoke. The multi-stack build (Rust + pnpm/Node.js for the frontend, Tauri CLI) additionally requires a combined toolchain that neither `rust_rootfs` nor `node_rootfs` alone provides. Same category as pake (Tauri) and alacritty (OpenGL terminal).

**obs-studio — deferred (GUI desktop studio; Qt6 + FFmpeg + X11/Wayland required).** OBS Studio is a screen-recording and live-streaming desktop application built around a Qt6 GUI. Its CMake build unconditionally requires Qt6 (`libqt6*-dev`), FFmpeg libraries (`libavcodec-dev`, `libavformat-dev`, `libavutil-dev`, `libswresample-dev`), X11 or Wayland display headers, and a large set of audio/video capture libs (PulseAudio, V4L2, libx264, etc.) — none of which are in `c_rootfs`. The application initializes a Qt `QApplication` before any argument processing, requiring a live display connection for even `obs --version`; there is no headless or CLI operation mode. Providing the required Qt6 + FFmpeg + display stack would require a dedicated `c_qt_rootfs` toolchain (similar to what qbittorrent needs). Same category as aseprite (X11 required at startup), imhex (OpenGL + display), and qbittorrent (Qt6 runtime dep).

**GUI / heavy-system-dep deferrals.** alacritty (OpenGL terminal), tabby
(Electron), lossless-cut (Electron), pake (Tauri), and imhex (Dear ImGui hex
editor) are GUI apps with no meaningful headless run. OCRmyPDF is feasible but
heavy: it needs OCR engines (tesseract, ghostscript, unpaper, qpdf, …) and a
large real-OCR test suite — revisitable if we invest in an OCR toolchain.

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
