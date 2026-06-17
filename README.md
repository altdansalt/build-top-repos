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
toolchains/BUILD.bazel    //toolchains:{node,python,go}_rootfs  (cached, apt-baked)
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

## Status

### Done
- **Bazel workspace skeleton**: `.bazelversion` (9.1.1), `.bazelrc` (Bzlmod-only),
  `MODULE.bazel` with all four inputs pinned + `rules_shell`.
- **Container runtime via Bazel**: `crun` 1.28 static binary via pinned `http_file`.
- **Rootless run** with multi-id mapping + capabilities.
- **Cached toolchain rootfs** (`//toolchains:node_rootfs`): ubuntu-base + Node +
  CA, with git/time/ca-certs baked in via one apt pass against the pinned
  snapshot. Bazel caches it; apt runs once, not per project.
- **husky — build + test split, both green**: `bazel build //projects/husky`
  produces `husky.built.tar` (post-build tree incl. `npm pack` output);
  `bazel test //projects/husky:husky_test` restores it and runs husky's 12-script
  suite against the packed artifact (no rebuild) → PASSED.
- **gulp — first project with real deps, green**: build = `npm install`
  (node_modules captured into the 8.5M artifact, no lockfile → first
  non-deterministic case); test = `npm test` (eslint pretest + `nyc mocha`),
  **42 mocha tests passing**, 100% coverage. `bazel test //projects/...` = 2/2.

### Project ledger
| # | project | lang | build | test | smoke | result |
|---|---|---|---|---|---|---|
| 877 | husky | JS/npm | `npm pack` | 12-script suite vs packed tgz | install tgz → `husky init` → hook fires | ✅✅ |
| 867 | gulp | JS/npm | `npm install` | `npm test` (eslint + 42 mocha) | install gulp → run a gulpfile task | ✅✅ |
| 857 | playwright-mcp | TS/npm | (no-op; `echo OK`) | `playwright test` (Chrome) | — | ⏸️ deferred |
| 826 | sherlock | Python | venv + `pip install` | `pytest -m "not online"` (14 pass) | `sherlock --version`/`--help` | ✅✅ |
| 767 | cheat.sh | Python | venv + `pip install -r` | `pytest lib/` (1 trivial test) | — | ⏸️ deferred |
| 761 | zx | JS/TS | esbuild + tsc | (deferred: TTY/color-coupled) | `zx -v` + run a zx script | ✅⏸️ |
| 756 | dive | Go | `go build` | `go test` (all pkgs but docker-cli) | analyze image tarball → JSON | ✅✅ |

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

### Next
1. Continue the CSV: `repo_build` + `repo_test` + `repo_smoke` per project,
   learning as we go. Heavy/browser/GUI projects → cache the weight in a toolchain.
2. Optional **reproducibility check** target: build twice, diff the artifact hash.
3. Per-project `apt` deps and non-Node toolchains (Python, Go, C/C++) — likely a
   second cached toolchain or per-project package lists.
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
