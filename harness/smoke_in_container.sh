#!/usr/bin/env bash
# Smoke step (invoked by the repo_smoke sh_test -> `bazel test`).
#
# Black-box, end-user smoke test: restore the build artifact, then run an
# author-written smoke.sh that uses the program as a user would (install it,
# drive its CLI over a fresh sample). The built tree is at $PROJECT inside the
# container; the smoke script's exit code is the verdict.
#
# Flags: --crun --genconfig --toolchain --built --name --smoke
set -euo pipefail

CRUN= GENCFG= TOOLCHAIN= BUILT= NAME= SMOKE=
for arg in "$@"; do
  case "$arg" in
    --crun=*)      CRUN="${arg#*=}" ;;
    --genconfig=*) GENCFG="${arg#*=}" ;;
    --toolchain=*) TOOLCHAIN="${arg#*=}" ;;
    --built=*)     BUILT="${arg#*=}" ;;
    --name=*)      NAME="${arg#*=}" ;;
    --smoke=*)     SMOKE="${arg#*=}" ;;
    *) echo "smoke_in_container: unknown arg: $arg" >&2; exit 2 ;;
  esac
done

CRUN="$(realpath "$CRUN")"
GENCFG="$(realpath "$GENCFG")"
TOOLCHAIN="$(realpath "$TOOLCHAIN")"
BUILT="$(realpath "$BUILT")"
SMOKE="$(realpath "$SMOKE")"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
ROOT="$WORK/rootfs"
mkdir -p "$ROOT" "$ROOT/work"

tar -xzf "$TOOLCHAIN" -C "$ROOT"
cp /etc/resolv.conf "$ROOT/etc/resolv.conf"
tar -xzf "$BUILT" -C "$ROOT/work"          # restores /work/<name>
cp "$SMOKE" "$ROOT/work/smoke.sh"          # author-written smoke script

# PROJECT points the smoke script at the restored build tree.
INNER="set -e; \
git config --global user.email build@local; \
git config --global user.name build; \
git config --global init.defaultBranch main; \
PROJECT=/work/$NAME sh /work/smoke.sh"
ARGS_JSON="$(python3 -c 'import json,sys; print(json.dumps(["/bin/sh","-c",sys.argv[1]]))' "$INNER")"

python3 "$GENCFG" "$CRUN" "$WORK" "/work/$NAME" "$ARGS_JSON"
exec "$CRUN" --root "$WORK/state" run -b "$WORK" "smoke-$NAME"
