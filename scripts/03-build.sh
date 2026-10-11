#!/usr/bin/env bash
# Configure and build the riscv64 SystemWebView APK.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source-path=SCRIPTDIR
. "$HERE/config.sh"
REPO_ROOT="$(cd "$HERE/.." && pwd)"

if [ ! -d "$WORKSPACE/src/.git" ]; then
	die "no checkout at $WORKSPACE/src -- run 01-fetch.sh first"
fi
cd "$WORKSPACE/src"
export PATH="$WORKSPACE/depot_tools:$PATH"

# A protobuf newer than 3.20 in ~/.local shadows the one Chromium's generated
# _pb2.py files expect, and compile_resources dies with "Descriptors cannot not be
# created directly". Ignoring user site-packages is enough; nothing needs removing.
export PYTHONNOUSERSITE=1
export GOCACHE="${GOCACHE:-$WORKSPACE/.cache/go-build}"

mkdir -p "$OUT_DIR"
cp "$REPO_ROOT/args.gn" "$OUT_DIR/args.gn"
gn gen "$OUT_DIR"
ninja -C "$OUT_DIR" "$NINJA_TARGET"

echo
echo "APK: $WORKSPACE/src/$OUT_DIR/$APK_RELPATH"
echo "next: scripts/04-verify-apk.sh"
