#!/usr/bin/env bash
# Pinned inputs for the riscv64 Android WebView build.
# Single source of truth: the other scripts read this file and hardcode nothing.
#
# Sourced, never executed.
# shellcheck disable=SC2034  # every value here is consumed by a sourcing script

# Upstream Chromium, at the revision last verified on hardware.
# See the status table in README.md before changing this pair.
CHROMIUM_REMOTE="https://chromium.googlesource.com/chromium/src.git"
CHROMIUM_COMMIT="4744b886309d987d292e43232776d2206cccb13d"  # 151.0.7922.108
CHROMIUM_FETCH_REF="refs/tags/151.0.7922.108"

# The riscv64 series, carried as commits on the BayLibre Chromium fork.
SERIES_REMOTE="https://github.com/BayLibre/chromium.git"
SERIES_BRANCH="spacemit-riscv64-m151"

# depot_tools is pinned: a newer gclient can resolve DEPS differently.
DEPOT_TOOLS_REMOTE="https://chromium.googlesource.com/chromium/tools/depot_tools.git"
DEPOT_TOOLS_COMMIT="533321c34e1c3ba816bc5e820004fffe5b7fe4ad"

WORKSPACE="${WORKSPACE:-$PWD/workspace}"
OUT_DIR="out/riscv64"
NINJA_TARGET="system_webview_64_apk"
APK_RELPATH="apks/SystemWebView64.apk"

die() {
	printf 'error: %s\n' "$*" >&2
	exit 1
}
