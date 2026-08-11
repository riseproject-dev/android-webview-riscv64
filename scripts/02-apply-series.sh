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

# The series moves the SwiftShader gitlink to an unmerged Gerrit patchset. gclient
# resolves SwiftShader from DEPS and will not fetch that object, so the gitlink
# would point at something absent.
git -C third_party/swiftshader fetch "$SWIFTSHADER_REMOTE" "$SWIFTSHADER_GERRIT_REF"
git -C third_party/swiftshader checkout --detach "$SWIFTSHADER_COMMIT"

# third_party/ffmpeg is a separate repository, so the fork cannot carry its part
# of the change. The patch includes the generated riscv64 configuration, which is
# required: the build_ffmpeg.py change in the series only makes regenerating it
# possible, it does not produce it.
git -C third_party/ffmpeg apply --3way \
	"$REPO_ROOT/patches/0001-ffmpeg-support-android-riscv64.patch"

echo
echo "series applied on top of $(git rev-parse --short HEAD)"
echo "next: scripts/03-build.sh"
