#!/usr/bin/env bash
# Build step (invoked by the repo_build genrule -> `bazel build`).
#
# Clones the project at a pinned commit, runs the project's `build` command in a
# container, and captures the whole post-build working tree as <out> (a tarball).
# The tree is the uniform, language-agnostic artifact: it always exists, and it's
# exactly what a reproducibility diff compares.
#
# Flags: --crun --genconfig --toolchain --repo --commit --name --build --out
set -euo pipefail

CRUN= GENCFG= TOOLCHAIN= REPO= COMMIT= NAME= BUILD= OUT=
for arg in "$@"; do
  case "$arg" in
    --crun=*)      CRUN="${arg#*=}" ;;
    --genconfig=*) GENCFG="${arg#*=}" ;;
    --toolchain=*) TOOLCHAIN="${arg#*=}" ;;
    --repo=*)      REPO="${arg#*=}" ;;
    --commit=*)    COMMIT="${arg#*=}" ;;
    --name=*)      NAME="${arg#*=}" ;;
    --build=*)     BUILD="${arg#*=}" ;;
    --out=*)       OUT="${arg#*=}" ;;
    *) echo "build_artifact: unknown arg: $arg" >&2; exit 2 ;;
  esac
done

CRUN="$(realpath "$CRUN")"
GENCFG="$(realpath "$GENCFG")"
TOOLCHAIN="$(realpath "$TOOLCHAIN")"
OUT_ABS="$(realpath -m "$OUT")"   # genrule output path; may not exist yet

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
ROOT="$WORK/rootfs"
mkdir -p "$ROOT" "$WORK/out" "$ROOT/out"

tar -xzf "$TOOLCHAIN" -C "$ROOT"
cp /etc/resolv.conf "$ROOT/etc/resolv.conf"

git clone --quiet "$REPO" "$WORK/src"
git -C "$WORK/src" checkout --quiet "$COMMIT"
rm -rf "$WORK/src/.git"
mkdir -p "$ROOT/work"
cp -a "$WORK/src" "$ROOT/work/$NAME"

# Run the build, then tar the post-build tree to the /out bind mount.
INNER="set -e; cd /work/$NAME; $BUILD; cd /work; tar -czf /out/built.tar $NAME"
ARGS_JSON="$(python3 -c 'import json,sys; print(json.dumps(["/bin/sh","-c",sys.argv[1]]))' "$INNER")"
MNT_JSON="$(python3 -c 'import json,sys; print(json.dumps([{"destination":"/out","type":"bind","source":sys.argv[1],"options":["bind","rw"]}]))' "$WORK/out")"

python3 "$GENCFG" "$CRUN" "$WORK" "/work/$NAME" "$ARGS_JSON" "$MNT_JSON"
"$CRUN" --root "$WORK/state" run -b "$WORK" "build-$NAME"

mv "$WORK/out/built.tar" "$OUT_ABS"
