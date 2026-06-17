#!/usr/bin/env bash
# Test step (invoked by the repo_test sh_test -> `bazel test`).
#
# Restores the build artifact (the post-build tree) into a fresh container and
# runs the project's `test` command against it -- no rebuild. The script's exit
# code is the test verdict, so Bazel reports green/red.
#
# Flags: --crun --genconfig --toolchain --built --name --test
set -euo pipefail

CRUN= GENCFG= TOOLCHAIN= BUILT= NAME= TEST=
for arg in "$@"; do
  case "$arg" in
    --crun=*)      CRUN="${arg#*=}" ;;
    --genconfig=*) GENCFG="${arg#*=}" ;;
    --toolchain=*) TOOLCHAIN="${arg#*=}" ;;
    --built=*)     BUILT="${arg#*=}" ;;
    --name=*)      NAME="${arg#*=}" ;;
    --test=*)      TEST="${arg#*=}" ;;
    *) echo "test_in_container: unknown arg: $arg" >&2; exit 2 ;;
  esac
done

CRUN="$(realpath "$CRUN")"
GENCFG="$(realpath "$GENCFG")"
TOOLCHAIN="$(realpath "$TOOLCHAIN")"
BUILT="$(realpath "$BUILT")"

WORK="$(mktemp -d -p "${TEST_TMPDIR:-${TMPDIR:-/tmp}}")"
# Container processes create files owned by mapped sub-uids; a plain rm can't
# remove sub-uid-owned dirs. Re-enter a userns (subuids mapped) to clean up.
trap 'unshare --user --map-root-user --map-auto rm -rf "$WORK" 2>/dev/null || rm -rf "$WORK"' EXIT
ROOT="$WORK/rootfs"
mkdir -p "$ROOT" "$ROOT/work"

tar -xzf "$TOOLCHAIN" -C "$ROOT"
cp /etc/resolv.conf "$ROOT/etc/resolv.conf"
# Restore the post-build tree: built.tar contains <name>/...
tar -xzf "$BUILT" -C "$ROOT/work"

INNER="set -e; \
git config --global user.email build@local; \
git config --global user.name build; \
git config --global init.defaultBranch main; \
git config --global --add safe.directory '*'; \
cd /work/$NAME; $TEST"
ARGS_JSON="$(python3 -c 'import json,sys; print(json.dumps(["/bin/sh","-c",sys.argv[1]]))' "$INNER")"

python3 "$GENCFG" "$CRUN" "$WORK" "/work/$NAME" "$ARGS_JSON"
# Don't exec: the EXIT trap must run to clean up $WORK. set -e propagates a
# nonzero crun exit (test failure) to our exit, and the trap fires either way.
"$CRUN" --root "$WORK/state" run -b "$WORK" "test-$NAME"
