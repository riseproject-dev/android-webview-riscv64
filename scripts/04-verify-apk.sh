#!/usr/bin/env bash
# Check that the built APK is what it claims to be, before shipping it into an
# AOSP tree. Every check here is cheap and has caught something real.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source-path=SCRIPTDIR
. "$HERE/config.sh"

APK="${1:-$WORKSPACE/src/$OUT_DIR/$APK_RELPATH}"
if [ ! -f "$APK" ]; then
	die "no APK at $APK"
fi

TMP="$(mktemp -d "${APK}.verification.XXXXXX")"
echo "verification artifacts: $TMP"

echo "apk:    $APK"
echo "size:   $(stat -c %s "$APK") bytes"
echo "sha256: $(sha256sum "$APK" | cut -d' ' -f1)"

unzip -tq "$APK" >/dev/null || die "APK is not a readable zip"

# One ABI and one only: a stray lib/arm64-v8a means the wrong target was built.
abis="$(unzip -Z1 "$APK" 'lib/*/*' | cut -d/ -f2 | sort -u)"
echo "abis:   $(echo "$abis" | tr '\n' ' ')"
if [ "$abis" != "riscv64" ]; then
	die "expected exactly lib/riscv64, got: $(echo "$abis" | tr '\n' ' ')"
fi

unzip -oq "$APK" 'lib/riscv64/libwebviewchromium.so' -d "$TMP"
SO="$TMP/lib/riscv64/libwebviewchromium.so"
echo "so:     $(stat -c %s "$SO") bytes"
echo "so sha: $(sha256sum "$SO" | cut -d' ' -f1)"

# Trust the ELF header, not the path the file came from.
machine="$(readelf -h "$SO" | sed -n 's/^ *Machine: *//p')"
echo "machine: $machine"
case "$machine" in
*RISC-V*) ;;
*) die "libwebviewchromium.so is not RISC-V: $machine" ;;
esac

# Package identity, when aapt2 is around. targetSdkVersion is not cosmetic: it is
# the floor WebViewUpdateService enforces before it will accept a provider.
if command -v aapt2 >/dev/null 2>&1; then
	badging="$(aapt2 dump badging "$APK")"
	pkg="$(printf '%s\n' "$badging" | sed -n "s/^package: name='\([^']*\)'.*/\1/p")"
	ver="$(printf '%s\n' "$badging" | sed -n "s/^package:.*versionName='\([^']*\)'.*/\1/p")"
	tsdk="$(printf '%s\n' "$badging" | sed -n "s/^targetSdkVersion:'\([^']*\)'/\1/p")"
	native="$(printf '%s\n' "$badging" | sed -n "s/^native-code: //p" | tr -d "'")"
	echo "package: $pkg"
	echo "version: $ver"
	echo "targetSdk: $tsdk"
	echo "native:  $native"
	if [ "$pkg" != "com.android.webview" ]; then
		die "expected package com.android.webview, got $pkg"
	fi
	if [ "$native" != "riscv64" ]; then
		die "expected native-code riscv64 only, got $native"
	fi
	if [ -n "$tsdk" ] && [ "$tsdk" -lt 33 ]; then
		die "targetSdkVersion $tsdk is below the WebViewUpdateService floor of 33"
	fi
else
	echo "aapt2 not found, skipping package identity checks"
fi

# The APK and the .so can keep byte-identical sizes across a real code change,
# because ELF alignment padding absorbs small deltas. Compare the sha256 above
# against the previous build; size alone proves nothing.
echo
echo "OK"
