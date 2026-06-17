"""Macros for declaring a per-project reproducible build + test.

  repo_build(name, repo, commit, build)
      `bazel build //projects/<name>` -> <name>.built.tar, the whole post-build
      working tree captured from inside the container. Cached by Bazel, keyed on
      the pinned commit + build command + toolchain.

  repo_test(name, built, test)
      `bazel test //projects/<name>:<name>_test` -> restores that artifact into a
      fresh container, runs `test` against it (no rebuild), reports green/red.

  repo_smoke(name, built, smoke = "smoke.sh")
      `bazel test //projects/<name>:<name>_smoke` -> restores the artifact and
      runs an author-written smoke.sh that drives the program as an end user
      would (install it, run its CLI over a fresh sample). The built tree is at
      $PROJECT inside the container. A separate file (not an inline command) so
      it can use any quoting and ship sample fixtures.

Build commands are single-quoted into the genrule cmd, so a build command
containing a single quote won't work yet (handle when we hit one).
"""

load("@rules_shell//shell:sh_test.bzl", "sh_test")

_CRUN = "@crun//file"
_GENCONFIG = "//harness:gen_config.py"
_TOOLCHAIN = "//toolchains:node_rootfs"

def repo_build(name, repo, commit, build, toolchain = _TOOLCHAIN):
    native.genrule(
        name = name,
        srcs = [
            _CRUN,
            _GENCONFIG,
            "//harness:build_artifact.sh",
            toolchain,
        ],
        outs = [name + ".built.tar"],
        cmd = "bash $(location //harness:build_artifact.sh)" +
              " --crun=$(location %s)" % _CRUN +
              " --genconfig=$(location %s)" % _GENCONFIG +
              " --toolchain=$(location %s)" % toolchain +
              " --repo='%s'" % repo +
              " --commit='%s'" % commit +
              " --name='%s'" % name +
              " --build='%s'" % build +
              " --out=$@",
        # Invokes crun (user namespaces) + git clone; Bazel's sandbox blocks both.
        local = 1,
        tags = ["requires-network", "no-sandbox"],
    )

def repo_test(name, built, test, toolchain = _TOOLCHAIN):
    sh_test(
        name = name + "_test",
        srcs = ["//harness:test_in_container.sh"],
        data = [_CRUN, _GENCONFIG, toolchain, built],
        args = [
            "--crun=$(rootpath %s)" % _CRUN,
            "--genconfig=$(rootpath %s)" % _GENCONFIG,
            "--toolchain=$(rootpath %s)" % toolchain,
            "--built=$(rootpath %s)" % built,
            "--name=" + name,
            "--test='%s'" % test,
        ],
        tags = ["requires-network", "no-sandbox", "local", "external"],
    )

def repo_smoke(name, built, smoke = "smoke.sh", toolchain = _TOOLCHAIN):
    sh_test(
        name = name + "_smoke",
        srcs = ["//harness:smoke_in_container.sh"],
        data = [_CRUN, _GENCONFIG, toolchain, built, smoke],
        args = [
            "--crun=$(rootpath %s)" % _CRUN,
            "--genconfig=$(rootpath %s)" % _GENCONFIG,
            "--toolchain=$(rootpath %s)" % toolchain,
            "--built=$(rootpath %s)" % built,
            "--name=" + name,
            "--smoke=$(rootpath %s)" % smoke,
        ],
        tags = ["requires-network", "no-sandbox", "local", "external"],
    )
