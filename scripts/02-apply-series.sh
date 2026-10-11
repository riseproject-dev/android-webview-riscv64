#!/usr/bin/env bash
# Replay the bundled riscv64 commits on the official Chromium revision.
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

python3 "$HERE/apply-chromium-series.py"
[[ "$(git rev-parse HEAD)" == "$SERIES_COMMIT" ]] ||
	die "the bundled series does not match its pinned commit"

# gclient owns these sub-repositories; a later sync reverts their patches.
apply_dependency_patch() {
	local repository="$1" patch="$2"
	shift 2
	if git -C "$repository" apply --reverse --check "$patch" 2>/dev/null; then
		printf 'Already applied: %s\n' "${patch##*/}"
	else
		git -C "$repository" apply "$@" "$patch"
	fi
}

# SwiftShader still defaults to LLVM 10, whose jitlink has no
# InProcessMemoryManager::Create(). LLVMJIT.cpp forces the non-legacy object
# linking layer on riscv, so without this the build does not compile. A gitlink
# move in chromium/src would not work: gclient resolves SwiftShader from DEPS and
# ignores the gitlink.
apply_dependency_patch third_party/swiftshader \
	"$REPO_ROOT/patches/0002-swiftshader-default-to-llvm16.patch"

# ffmpeg: the patch carries the generated riscv64 configuration, which is
# required. The build_ffmpeg.py change in the series enables regeneration,
# but does not produce the configuration during a normal Chromium build.
apply_dependency_patch third_party/ffmpeg \
	"$REPO_ROOT/patches/0001-ffmpeg-support-android-riscv64.patch" --3way

# cpuinfo casts its cpu_set_t* to unsigned long* for __riscv_hwprobe(), which is
# the glibc signature, on a code path that only builds on Android. Dead code until
# android riscv64 was enabled; fatal with M151's clang.
apply_dependency_patch third_party/cpuinfo/src \
	"$REPO_ROOT/patches/0003-cpuinfo-fix-hwprobe-cpu_set-type-on-bionic.patch"

echo
echo "series applied on top of $(git rev-parse --short HEAD)"
echo "next: scripts/03-build.sh"
