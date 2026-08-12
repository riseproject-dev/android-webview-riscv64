#!/usr/bin/env bash
# Put the riscv64 series on top of the pinned Chromium revision.
#
# Run this after 01-fetch.sh. Re-running `gclient sync` afterwards reverts the
# two sub-repository steps below, so re-run this script if you ever do.
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

if ! git remote get-url baylibre >/dev/null 2>&1; then
	git remote add baylibre "$SERIES_REMOTE"
fi
git remote set-url baylibre "$SERIES_REMOTE"
git fetch baylibre "$SERIES_BRANCH"
git checkout -B riscv64-series "baylibre/$SERIES_BRANCH"

# The two changes below belong to sub-repositories, which a chromium/src fork
# cannot carry. gclient owns these directories, so a later `gclient sync` reverts
# them and this script has to run again.

# SwiftShader still defaults to LLVM 10, whose jitlink has no
# InProcessMemoryManager::Create(). LLVMJIT.cpp forces the non-legacy object
# linking layer on riscv, so without this the build does not compile. A gitlink
# move in chromium/src would not work: gclient resolves SwiftShader from DEPS and
# ignores the gitlink.
git -C third_party/swiftshader apply \
	"$REPO_ROOT/patches/0002-swiftshader-default-to-llvm16.patch"

# ffmpeg: the patch carries the generated riscv64 configuration, which is
# required. The build_ffmpeg.py change in the series only makes regenerating it
# possible, it does not produce it. --3way because the generated config was
# produced against an older ffmpeg revision than the one DEPS pins today.
git -C third_party/ffmpeg apply --3way \
	"$REPO_ROOT/patches/0001-ffmpeg-support-android-riscv64.patch"

# cpuinfo casts its cpu_set_t* to unsigned long* for __riscv_hwprobe(), which is
# the glibc signature, on a code path that only builds on Android. Dead code until
# android riscv64 was enabled; fatal with M151's clang.
git -C third_party/cpuinfo/src apply \
	"$REPO_ROOT/patches/0003-cpuinfo-fix-hwprobe-cpu_set-type-on-bionic.patch"

echo
echo "series applied on top of $(git rev-parse --short HEAD)"
echo "next: scripts/03-build.sh"
