#!/usr/bin/env bash
# Create the workspace and check out Chromium at the pinned revision.
# Budget ~80 GB of disk and a long first sync.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source-path=SCRIPTDIR
. "$HERE/config.sh"

mkdir -p "$WORKSPACE"
cd "$WORKSPACE"

if [ ! -d depot_tools/.git ]; then
	git clone "$DEPOT_TOOLS_REMOTE" depot_tools
fi
git -C depot_tools checkout --detach "$DEPOT_TOOLS_COMMIT"
export PATH="$WORKSPACE/depot_tools:$PATH"

# checkout_riscv64 is what pulls the riscv64 sysroot and toolchain entries out of
# DEPS. Without it the build fails late, on a missing sysroot, with nothing
# pointing back at this file. managed:False keeps gclient from moving src off the
# pinned revision on every sync.
gclient_spec="$(cat <<EOF
solutions = [
  {
    "name": "src",
    "url": "$CHROMIUM_REMOTE",
    "managed": False,
    "custom_deps": {},
    "custom_vars": {
      "checkout_riscv64": True,
      "checkout_android": True,
    },
  },
]
target_os = ["android"]
EOF
)"
if ! printf '%s\n' "$gclient_spec" | cmp -s - .gclient; then
	if [ -e .gclient ]; then
		gclient_backup="$(mktemp .gclient.before-rise.XXXXXX)"
		cp -p .gclient "$gclient_backup"
		echo "previous gclient configuration saved to $WORKSPACE/$gclient_backup"
	fi
	printf '%s\n' "$gclient_spec" > .gclient
fi

if [ ! -d src/.git ]; then
	git init -q src
	git -C src remote add origin "$CHROMIUM_REMOTE"
fi
git -C src remote set-url origin "$CHROMIUM_REMOTE"

# Fetching the pinned commit directly keeps the clone small. Not every server
# allows a fetch by SHA, so fall back to the official release tag.
if ! git -C src fetch --depth 1 origin "$CHROMIUM_COMMIT" 2>/dev/null; then
	echo "fetch by SHA refused, falling back to $CHROMIUM_FETCH_REF" >&2
	git -C src fetch --depth 1 origin "$CHROMIUM_FETCH_REF"
fi
git -C src checkout --detach "$CHROMIUM_COMMIT"

gclient sync

echo
echo "workspace ready: $WORKSPACE"
echo "next: scripts/02-apply-series.sh"
