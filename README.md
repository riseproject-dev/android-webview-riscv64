# android-webview-riscv64

Everything needed to rebuild the Android **WebView** APK for **riscv64**, and to
integrate it into an AOSP tree.

Chromium has no official riscv64 Android target. AOSP's `external/chromium-webview`
ships prebuilts for arm, arm64, x86 and x86_64 only, so a riscv64 Android image has
no WebView provider at all: every app that embeds a `WebView` fails to start. This
repository carries the recipe; the source changes themselves live as commits on a
Chromium fork (see [Where things live](#where-things-live)).

*Une version française de ce document est disponible : [README.fr.md](README.fr.md).*

## Status

| Item | State |
|---|---|
| Chromium 141.0.7366.3 (`refs/branch-heads/7366`) | **Verified on hardware** — SpacemiT K1 (X60), Android 17, `ro.vendor.api_level=202604`. Renders pages; renderer runs sandboxed (`Seccomp: 2`). |
| Chromium 151.0.7922.108 (M151 stable) | **In progress.** The series is being rebased; not yet compiled, not yet run. |
| Boards other than SpacemiT K1 | **Not tested.** The build is generic riscv64, but only the K1 has been booted. |
| Cuttlefish (`aosp_cf_riscv64_phone`) | **Not tested.** |
| riscv64 support upstream | **Not merged.** Two of the six commits are unmerged Gerrit changelists; the rest are local. |

Do not read "verified" as "supported". This is a working recipe, not a product.

## Where things live

The source changes are **commits on a fork**, not patch files:

- **[BayLibre/chromium](https://github.com/BayLibre/chromium)**, branch
  `spacemit-riscv64-m141` — the six riscv64 commits on top of the pinned upstream
  revision. Reviewable, bisectable and rebasable with `git rebase --onto`.
- **This repository** — the recipe: scripts, build configuration, AOSP glue,
  documentation, and the one change the fork cannot carry (see below).

`third_party/ffmpeg` is a separate git repository, so a `chromium/src` fork cannot
contain its changes. They live here instead, in
`patches/0001-ffmpeg-support-android-riscv64.patch`.

```
scripts/config.sh      every pinned revision, in one place
scripts/01-fetch.sh    workspace + Chromium checkout at the pin
scripts/02-apply-series.sh   the fork branch, SwiftShader, and the ffmpeg patch
scripts/03-build.sh    gn gen + ninja
scripts/04-verify-apk.sh     check the APK without a device
args.gn                the gn configuration that produced the verified APK
aosp/                  the device-tree glue (Android.bp, makefile snippet)
patches/               changes that belong to a repository other than chromium/src
```

## Host requirements

Measured on the machine that produced the verified APK, not estimated:

- Linux x86_64 build host. The build cross-compiles; no riscv64 hardware is needed.
- **76 GB** for the checkout, before `out/`. Budget **~150 GB** total.
- 64 GB RAM recommended.
- 2–6 h for a clean build, depending on core count.

## Build it

```
./scripts/01-fetch.sh
./scripts/02-apply-series.sh
./scripts/03-build.sh
./scripts/04-verify-apk.sh
```

The result is `workspace/src/out/riscv64/apks/SystemWebView64.apk`
(136,465,503 bytes for the verified build).

`WORKSPACE=/path/to/somewhere` relocates the checkout. Everything else is pinned in
`scripts/config.sh` — change revisions there and nowhere else.

One ordering constraint: **re-running `gclient sync` reverts the SwiftShader and
ffmpeg steps**, because both live in sub-repositories that gclient owns. Re-run
`02-apply-series.sh` after any sync.

## The series

| # | Commit | Origin |
|---|---|---|
| 1 | `sandbox: Add support for riscv64-linux` | [crrev.com/c/4935120](https://chromium-review.googlesource.com/c/chromium/src/+/4935120) PS11, by Andreas Schwab. Not merged. |
| 2 | `swiftshader: roll to a revision that defaults to LLVM 16` | [SwiftShader CL 75929](https://swiftshader-review.googlesource.com/c/SwiftShader/+/75929) PS2, by Levi Zim. Not merged. |
| 3 | `build/config: riscv64: build with -mstrict-align` | local |
| 4 | `android: do not apply the 32-bit version code offset on riscv64` | local |
| 5 | `cpuinfo: enable the riscv linux sources on android` | local, upstreamable as is |
| 6 | `ffmpeg: support the android-riscv64 build` | local (companion patch in `patches/`) |

Two of them deserve explanation.

**Commit 1 is not optional, in either direction.** Without it riscv64 does not
build: `sandbox/linux/bpf_dsl/seccomp_macros.h` ends its architecture chain with
`#error Unsupported target platform`, and `linux_syscalls.h` has no riscv64 include.
It is not dead weight at runtime either — the WebView renderer really does run with
`SECCOMP_MODE_FILTER`, so the policy has to know the riscv64 syscall numbering.

**Commit 3 exists because of a SIGBUS, not a preference.** The SpacemiT X60 traps on
misaligned vector accesses: `hwprobe` reports vector-misaligned as UNSUPPORTED, and
the kernel's misaligned handler emulates only unit-stride `vle`/`vse`, never strided
`vlse`. Without `-mstrict-align` the autovectorizer emits a strided `vlse64.v` with
misaligned elements (in `ui::GestureDetector`, among others) and WebView dies with
`SIGBUS`/`BUS_ADRALN` on the first `loadUrl`. Note the cost: the flag applies to
**every** riscv64 build, so hardware with working misaligned vector support pays for
alignment it does not need. There is no opt-out gn argument yet.

## Build configuration

Two entries in `args.gn` are not guessable, and both fail in ways that point
somewhere else:

- **`clang_use_default_sample_profile = false`** — there is no riscv64 AFDO profile.
  Without this the build stops on `chrome/android/profiles/afdo.prof ... missing and
  no known rule to make it`.
- **`PYTHONNOUSERSITE=1`**, exported by `03-build.sh` — a protobuf newer than 3.20 in
  `~/.local` shadows the one Chromium's generated `_pb2.py` modules expect, and
  `compile_resources.py` dies with *"Descriptors cannot not be created directly"*.
  This surfaces **after** the native library has built, which makes a host Python
  problem look like a WebView problem. Upstream's documented alternative,
  `PROTOCOL_BUFFERS_PYTHON_IMPLEMENTATION=python`, also works but parses in pure
  Python.

`chrome_pgo_phase = 0` (no riscv64 PGO profile), `treat_warnings_as_errors = false`
(riscv64 is not warning-clean upstream) and `use_remoteexec = use_siso = false` (no
RBE) round out the non-defaults.

## Integrating into an AOSP tree

Copy `aosp/webview/Android.bp` and the APK into your device tree, then add
`PRODUCT_PACKAGES += webview_riscv64` from `aosp/device-common.mk.snippet`.
`config_webview_packages.xml` already lists `com.android.webview` as
`availableByDefault` with no signature pin, so it becomes the default provider at
boot with no framework change.

Five constraints, each of which cost real debugging time:

- **Do not name the module `webview`** — it collides with the inert upstream module
  in `external/chromium-webview`.
- **`enforce_uses_libs: false` is required.** `android_app_import` enforces
  `<uses-library>` verification by default, which turns the APK's optional uses-libs
  (`android.ext.adservices`, for one) into Soong dependencies a device-tree module
  cannot see, and the build fails on visibility.
- **Put `PRODUCT_PACKAGES` in the common device makefile**, not a board one. The APK
  is riscv64-generic, not board specific.
- **Run `m installclean` between rebuilds**, or a stale `/product/app/webview/`
  survives and the image ships two `com.android.webview` providers.
- **If you version-control the APK, it needs Git LFS** (136 MB exceeds GitHub's
  100 MB blob limit). `repo sync` does **not** run `git lfs pull`, so a fresh sync
  leaves a 4 KB pointer where the APK should be and the build fails in `aapt2 dump
  badging`. This is the most likely integration failure for a third party.

Do not patch `external/chromium-webview` — that means forking an AOSP repository.
Keep the import device-local.

## Testing on a device

`com.android.webview` is an *updatable* system app, so you can test a rebuild
without reflashing and without `adb remount` (which on some images disables verity
and breaks `apexd` on the next boot):

```
apksigner sign --key <aosp>/build/make/target/product/security/testkey.pk8 \
  --cert <aosp>/build/make/target/product/security/testkey.x509.pem \
  --out signed.apk workspace/src/out/riscv64/apks/SystemWebView64.apk
adb install -r signed.apk
adb shell pm path com.android.webview   # now under /data/app/
adb shell am start -a android.intent.action.VIEW \
  -d data:text/html,HELLO -n org.chromium.webview_shell/.WebViewBrowserActivity
adb exec-out screencap -p > shot.png
```

The APK must be re-signed with the key the image was signed with. `default_dev_cert:
true` means AOSP re-signs the APK at build time with `testkey`, so an APK carrying
Chromium's own signature is rejected.

**The `/data` update outlives a flash.** With an unchanged versionCode it shadows the
new system APK, so after flashing run
`adb shell pm uninstall-system-updates com.android.webview` or you will keep testing
the old build.

## The Android 17 crash

A WebView built from Chromium between 2025-08-18 and 2025-09-04 crashes
deterministically on first use on any device whose `ro.vendor.api_level` is 202604 or
newer — every Android 17 image:

```
Fatal signal 11 (SIGSEGV), code 1 (SEGV_MAPERR), fault addr 0x0
pc 0x0   ra <libwebviewchromium.so>+0x04390b5c
Cause: null pointer dereference
```

This is an **upstream Chromium bug and not riscv64-specific** — the same window
breaks arm64. `third_party/ashmem/ashmem-dev.c` reads `s_use_memfd` before the
`pthread_once` initializer that sets it has run, so the first caller takes the
function-pointer path while the initializer sets the flag and returns *without*
populating the pointers. Introduced by
[crrev.com/c/6853886](https://chromium-review.googlesource.com/c/chromium/src/+/6853886),
fixed by
[crrev.com/c/6900640](https://chromium-review.googlesource.com/c/chromium/src/+/6900640)
then
[crrev.com/c/6897348](https://chromium-review.googlesource.com/c/chromium/src/+/6897348).

If your pinned revision falls inside that window, backport both, in that order.
M142 and newer already carry them, and the code has since moved to
`base/android/linker/ashmem.cc`.

## Known gaps

- The M151 rebase is unfinished; the pin in `config.sh` is the M141 revision that was
  actually verified.
- `-mstrict-align` is unconditional. A `riscv_strict_align` gn argument would let
  non-SpacemiT hardware opt out, but it does not exist yet.
- Two test-only pieces of the sandbox changelist are not carried:
  `syscall_parameters_restrictions_unittest.cc` no longer exists upstream, and the
  riscv branch of `syscall_unittest.cc` (an ECALL opcode assertion) is missing.
  Neither is built by the WebView target, so neither affects the shipped APK.
- Nothing here is upstreamed. Commit 5 could be as is; the rest need work.
