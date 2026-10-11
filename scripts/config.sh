#!/usr/bin/env bash
# Pinned inputs for the riscv64 Android WebView build.
# Single source of truth: the other scripts read this file and hardcode nothing.
#
# Sourced, never executed.
# shellcheck disable=SC2034  # every value here is consumed by a sourcing script

# Official Chromium release, followed by the local RISC-V patch series.
# See the status table in README.md before changing this pair.
CHROMIUM_REMOTE="https://chromium.googlesource.com/chromium/src.git"
CHROMIUM_COMMIT="4744b886309d987d292e43232776d2206cccb13d"  # 151.0.7922.108
CHROMIUM_FETCH_REF="refs/tags/151.0.7922.108"

SERIES_COMMIT="0139499e9c33d18e27a0499ead341ca649f069e2"

# depot_tools is pinned: a newer gclient can resolve DEPS differently.
DEPOT_TOOLS_REMOTE="https://chromium.googlesource.com/chromium/tools/depot_tools.git"
DEPOT_TOOLS_COMMIT="533321c34e1c3ba816bc5e820004fffe5b7fe4ad"
export DEPOT_TOOLS_UPDATE=0

WORKSPACE="${WORKSPACE:-$PWD/workspace}"
OUT_DIR="out/riscv64"
NINJA_TARGET="system_webview_64_apk"
APK_RELPATH="apks/SystemWebView64.apk"

die() {
	printf 'error: %s\n' "$*" >&2
	exit 1
}
