# android-webview-riscv64

Tout ce qu'il faut pour reconstruire l'APK **WebView** Android pour **riscv64**, et
pour l'intégrer dans un arbre AOSP.

Chromium n'a pas de target Android riscv64 officielle. L'`external/chromium-webview`
d'AOSP ne fournit des prebuilts que pour arm, arm64, x86 et x86_64 : une image Android
riscv64 n'a donc **aucun** provider WebView, et toute application qui embarque une
`WebView` échoue au démarrage. Ce repo porte la recette ; les changements de source
eux-mêmes vivent sous forme de commits sur un fork de Chromium (voir
[Où vit quoi](#où-vit-quoi)).

*An English version of this document is available: [README.md](README.md).*

## État

| Élément | État |
|---|---|
| Chromium 151.0.7922.108 (M151 stable) — la révision épinglée | **Vérifié sur matériel** — SpacemiT K3, Android 17, `ro.vendor.api_level=202604`. Affiche des pages, le renderer tourne sandboxé. |
| Chromium 141.0.7366.3 | Vérifié précédemment sur une SpacemiT K1 (X60). Conservé à titre historique : la branche M141 exige un backport ashmem supplémentaire, voir [Le crash Android 17](#le-crash-android-17). |
| Autres boards que les SpacemiT K1 / K3 | **Non testé.** Le build est riscv64 générique, mais seules ces deux-là ont booté. |
| Cuttlefish (`aosp_cf_riscv64_phone`) | **Non testé.** |
| Support riscv64 upstream | **Non mergé.** Un des sept commits est une changelist Gerrit non mergée, le reste est local. Trois d'entre eux sont directement upstreamables, voir [La série](#la-série). |

« Vérifié » ne veut pas dire « supporté ». C'est une recette qui marche, pas un
produit.

## Où vit quoi

Les changements de source sont des **commits sur un fork**, pas des fichiers patch :

- **[BayLibre/chromium](https://github.com/BayLibre/chromium)**, branche
  `spacemit-riscv64-m151` — les sept commits riscv64 au-dessus de la révision
  upstream épinglée. Reviewables, bisectables, et rebasables avec
  `git rebase --onto`.
- **Ce repo** — la recette : scripts, configuration de build, glue AOSP,
  documentation, et les trois changements que le fork ne peut pas porter (voir plus
  bas).

`third_party/ffmpeg`, `third_party/swiftshader` et `third_party/cpuinfo/src` sont des
repos git séparés : un fork de `chromium/src` ne peut donc pas contenir leurs
changements. Ils vivent ici, et `02-apply-series.sh` route chacun vers le bon repo :

| Patch | Repo cible |
|---|---|
| `0001-ffmpeg-support-android-riscv64.patch` | `third_party/ffmpeg` |
| `0002-swiftshader-default-to-llvm16.patch` | `third_party/swiftshader` |
| `0003-cpuinfo-fix-hwprobe-cpu_set-type-on-bionic.patch` | `third_party/cpuinfo/src` |

Déplacer le gitlink dans `chromium/src` n'est **pas** une alternative : gclient
résout les sous-repos depuis `DEPS` et ignore les gitlinks, et un hash de commit créé
localement ne serait reproductible par personne d'autre.

```
scripts/config.sh      toutes les révisions épinglées, à un seul endroit
scripts/01-fetch.sh    workspace + checkout Chromium à la révision épinglée
scripts/02-apply-series.sh   la branche du fork, SwiftShader, et le patch ffmpeg
scripts/03-build.sh    gn gen + ninja
scripts/04-verify-apk.sh     vérifier l'APK sans board
args.gn                la configuration gn qui a produit l'APK vérifié
aosp/                  la glue device-tree (Android.bp, snippet de makefile)
patches/               les changements qui appartiennent à un autre repo que chromium/src
```

## Prérequis hôte

Mesurés sur la machine qui a produit l'APK vérifié, pas estimés :

- Hôte de build Linux x86_64. Le build cross-compile, aucun matériel riscv64 n'est
  nécessaire.
- **76 Go** pour le checkout, avant `out/`. Prévoir **~150 Go** au total.
- 64 Go de RAM recommandés.
- 2 à 6 h pour un build propre, selon le nombre de cœurs.

## Construire

```
./scripts/01-fetch.sh
./scripts/02-apply-series.sh
./scripts/03-build.sh
./scripts/04-verify-apk.sh
```

Le résultat est `workspace/src/out/riscv64/apks/SystemWebView64.apk`
(145 131 247 octets pour le build vérifié).

`WORKSPACE=/chemin/quelque/part` déplace le checkout. Tout le reste est épinglé dans
`scripts/config.sh` — c'est là, et nulle part ailleurs, qu'on change une révision.

Trois choses qui te mordront sinon :

- **`02-apply-series.sh` exige que la branche du fork existe sur le remote.** Il fetch
  `$SERIES_BRANCH` depuis `$SERIES_REMOTE` ; il n'y a pas de chemin hors-ligne.
- **Relancer `gclient sync` annule les trois patchs de sous-repo**, parce que gclient
  possède ces répertoires. Il faut relancer `02-apply-series.sh` après chaque sync.
- **`gclient sync` refuse carrément de tourner si un sous-repo est sale**, ce qui est
  le cas dès que les patchs sont appliqués :

  ```
  ____ src/third_party/ffmpeg at <rev>
      You have uncommitted changes.
  ```

  Faire `git -C src/third_party/ffmpeg stash push -u` avant le sync, puis réappliquer.

## La série

| # | Commit | Origine |
|---|---|---|
| 1 | `sandbox: Add support for riscv64-linux` | [crrev.com/c/4935120](https://chromium-review.googlesource.com/c/chromium/src/+/4935120) PS11, par Andreas Schwab. Non mergé. |
| 2 | `build/config: riscv64: build with -mstrict-align` | local |
| 3 | `android: do not apply the 32-bit version code offset on riscv64` | local |
| 4 | `cpuinfo: enable the riscv linux sources on android` | local, upstreamable tel quel |
| 5 | `ffmpeg: support the android-riscv64 build` | local (patch compagnon dans `patches/`) |
| 6 | `blink: fix SimdEqualIgnoringAsciiCase tag types for scalable vectors` | local, upstreamable tel quel |
| 7 | `skia: link the NDK ICU stub when building against API 31 or newer` | local, upstreamable tel quel |

Quatre d'entre eux méritent une explication.

**Le commit 1 n'est optionnel dans aucun des deux sens.** Sans lui, riscv64 ne
compile pas : `sandbox/linux/bpf_dsl/seccomp_macros.h` termine sa chaîne
d'architectures par `#error Unsupported target platform`, et `linux_syscalls.h` n'a
aucun include riscv64. Ce n'est pas non plus du poids mort au runtime — le renderer
WebView tourne réellement en `SECCOMP_MODE_FILTER`, donc la policy doit connaître la
numérotation des syscalls riscv64.

**Le commit 2 existe à cause d'un SIGBUS, pas d'une préférence.** Le SpacemiT X60
trappe sur les accès vectoriels non alignés : `hwprobe` rapporte vector-misaligned
comme UNSUPPORTED, et le handler misaligned du kernel n'émule que les `vle`/`vse`
unit-stride, jamais les `vlse` stridés. Sans `-mstrict-align`, l'autovectorizer émet
un `vlse64.v` stridé avec des éléments non alignés (dans `ui::GestureDetector`, entre
autres) et WebView meurt en `SIGBUS`/`BUS_ADRALN` au premier `loadUrl`. À noter, le
coût : le flag s'applique à **tous** les builds riscv64, donc du matériel dont le
support misaligned vectoriel fonctionne paie un alignement dont il n'a pas besoin. Il
n'y a pas encore d'argument gn pour s'en dispenser.

**Les commits 6 et 7 sont des bugs upstream que seul riscv64 atteint.** Ce ne sont
pas des hacks de portage : les deux sont des correctifs acceptables upstream tels
quels.

Commit 6 : `SimdEqualIgnoringAsciiCase()` fabrique un `FixedTag<uint8_t, 8>`
indépendant et le promeut en `FixedTag<uint16_t, 8>`. Sur une cible à vecteurs
scalables comme RVV, le `PromoteTo` de Highway attend `VFromD<Rebind<uint8_t, D>>`,
dont le LMUL est moitié — la résolution de surcharge échoue. Les deux descripteurs ne
coïncident que sur les cibles à largeur fixe, d'où le fait que personne ne l'avait
remarqué. `Rebind` est ce que l'API Highway prévoit ici.

Commit 7 est une chaîne qui commence et finit par riscv64 :

```
riscv64  ->  build/config/android/config.gni force android_ndk_api_level = 36
         ->  __ANDROID_API__ >= 31 dans Skia
         ->  SkFontMgr_android_ndk.cpp cesse de dlsym'er libicu.so et référence
             u_strFoldCase / u_strFromUTF8 / u_strToUTF8 directement
         ->  trois symboles non résolus au link, personne ne linke le stub ICU du NDK
```

Toutes les autres architectures compilent contre le min-sdk bien plus bas de
Chromium et ne quittent donc jamais le chemin dlsym. Le fix linke le stub ICU du NDK,
gardé par `android_ndk_api_level >= 31` pour rester juste partout.

## Configuration de build

Deux entrées d'`args.gn` ne sont pas devinables, et toutes deux échouent en
désignant un coupable qui n'est pas le bon :

- **`clang_use_default_sample_profile = false`** — il n'existe pas de profil AFDO
  riscv64. Sans ça, le build s'arrête sur `chrome/android/profiles/afdo.prof ...
  missing and no known rule to make it`.
- **`PYTHONNOUSERSITE=1`**, exporté par `03-build.sh` — un protobuf plus récent que
  3.20 dans `~/.local` masque celui qu'attendent les modules `_pb2.py` générés de
  Chromium, et `compile_resources.py` meurt sur *« Descriptors cannot not be created
  directly »*. Ça se manifeste **après** que la bibliothèque native a compilé, ce qui
  fait passer un problème de Python hôte pour un problème de WebView. L'alternative
  documentée par upstream, `PROTOCOL_BUFFERS_PYTHON_IMPLEMENTATION=python`, marche
  aussi mais parse en pure Python.

`chrome_pgo_phase = 0` (pas de profil PGO riscv64), `treat_warnings_as_errors = false`
(riscv64 n'est pas warning-clean upstream) et `use_remoteexec = use_siso = false`
(pas de RBE) complètent les non-défauts.

## Intégrer dans un arbre AOSP

Copier `aosp/webview/Android.bp` et l'APK dans le device tree, puis ajouter
`PRODUCT_PACKAGES += webview_riscv64` depuis `aosp/device-common.mk.snippet`.
`config_webview_packages.xml` liste déjà `com.android.webview` comme
`availableByDefault` sans épinglage de signature : il devient donc le provider par
défaut au boot, sans aucun changement dans le framework.

Cinq contraintes, chacune ayant coûté du debug réel :

- **Ne pas nommer le module `webview`** — collision avec le module upstream inerte
  d'`external/chromium-webview`.
- **`enforce_uses_libs: false` est obligatoire.** `android_app_import` applique par
  défaut la vérification des `<uses-library>`, ce qui transforme les uses-libs
  optionnelles de l'APK (`android.ext.adservices`, par exemple) en dépendances Soong
  qu'un module de device tree ne peut pas voir, et le build échoue sur la visibilité.
- **Mettre `PRODUCT_PACKAGES` dans le makefile device commun**, pas dans celui d'une
  board. L'APK est riscv64-générique, pas spécifique à une board.
- **Lancer `m installclean` entre deux rebuilds**, sinon un `/product/app/webview/`
  périmé survit et l'image embarque deux providers `com.android.webview`.
- **Si l'APK est versionné, il faut Git LFS** (136 Mo dépasse la limite de 100 Mo par
  blob de GitHub). `repo sync` ne lance **pas** `git lfs pull` : un sync frais laisse
  donc un pointeur de 4 Ko à la place de l'APK, et le build casse dans `aapt2 dump
  badging`. C'est le mode d'échec le plus probable pour un tiers.

Ne pas patcher `external/chromium-webview` — ça voudrait dire forker un repo AOSP.
L'import reste local au device.

## Tester sur une board

`com.android.webview` est une application système **updatable** : on peut donc tester
un rebuild sans reflasher et sans `adb remount` (qui, sur certaines images, désactive
verity et casse `apexd` au boot suivant) :

```
apksigner sign --key <aosp>/build/make/target/product/security/testkey.pk8 \
  --cert <aosp>/build/make/target/product/security/testkey.x509.pem \
  --out signed.apk workspace/src/out/riscv64/apks/SystemWebView64.apk
adb install -r signed.apk
adb shell pm path com.android.webview   # désormais sous /data/app/
adb shell am start -a android.intent.action.VIEW \
  -d data:text/html,HELLO -n org.chromium.webview_shell/.WebViewBrowserActivity
adb exec-out screencap -p > shot.png
```

L'APK doit être re-signé avec la clé qui a signé l'image. `default_dev_cert: true`
signifie qu'AOSP re-signe l'APK au moment du build avec `testkey` : un APK portant la
signature propre de Chromium est donc rejeté.

**L'update `/data` survit à un flash.** À versionCode inchangé, il masque le nouvel
APK système : après un flash, lancer
`adb shell pm uninstall-system-updates com.android.webview`, sinon on continue de
tester l'ancien build.

## Le crash Android 17

Une WebView construite depuis un Chromium daté entre le 2025-08-18 et le 2025-09-04
crashe de façon déterministe à la première utilisation sur tout device dont
`ro.vendor.api_level` vaut 202604 ou plus — donc toute image Android 17 :

```
Fatal signal 11 (SIGSEGV), code 1 (SEGV_MAPERR), fault addr 0x0
pc 0x0   ra <libwebviewchromium.so>+0x04390b5c
Cause: null pointer dereference
```

C'est un **bug upstream de Chromium, pas un problème riscv64** — la même fenêtre
casse arm64. `third_party/ashmem/ashmem-dev.c` lit `s_use_memfd` avant que
l'initialiseur `pthread_once` qui le renseigne ait tourné : le premier appelant part
donc sur le chemin par pointeur de fonction pendant que l'initialiseur lève le flag et
retourne *sans* remplir les pointeurs. Introduit par
[crrev.com/c/6853886](https://chromium-review.googlesource.com/c/chromium/src/+/6853886),
corrigé par
[crrev.com/c/6900640](https://chromium-review.googlesource.com/c/chromium/src/+/6900640)
puis
[crrev.com/c/6897348](https://chromium-review.googlesource.com/c/chromium/src/+/6897348).

Si la révision épinglée tombe dans cette fenêtre, backporter les deux, dans cet
ordre. M142 et suivants les portent déjà, et le code a depuis déménagé dans
`base/android/linker/ashmem.cc`.

## Limites connues

- `-mstrict-align` est inconditionnel. Un argument gn `riscv_strict_align`
  permettrait au matériel non-SpacemiT de s'en passer, mais il n'existe pas encore.
- L'APK a été éprouvé en chargeant des pages dans le webview shell et en vérifiant que
  le renderer sandboxé démarre. Ce n'est pas une suite de tests : rien ici ne fait
  tourner le CTS Chromium ou WebView.
- Deux morceaux test-only de la changelist sandbox ne sont pas portés :
  `syscall_parameters_restrictions_unittest.cc` n'existe plus upstream, et la branche
  riscv de `syscall_unittest.cc` (une assertion sur l'opcode ECALL) manque. Ni l'un
  ni l'autre n'est compilé par la target WebView, donc l'APK livré n'est pas affecté.
- Rien n'est encore upstreamé. Les commits 4, 6 et 7 et les patchs 0002 et 0003
  pourraient l'être tels quels ; la changelist sandbox et `-mstrict-align` demandent
  du travail d'abord.

## Licence

Le contenu original de ce repo — la documentation, les scripts, la configuration gn
et la glue AOSP — est sous Apache License 2.0. Voir [LICENSE](LICENSE).

Les fichiers de `patches/` sont l'exception. Chacun est une œuvre dérivée du projet
auquel il s'applique et reste sous les termes de ce projet, pas sous ceux de ce repo :

| Patch | Projet upstream | Termes upstream |
|---|---|---|
| `0001-ffmpeg-support-android-riscv64.patch` | FFmpeg, et le `ffmpeg_generated.gni` de Chromium | LGPL-2.1-or-later, BSD-3-Clause |
| `0002-swiftshader-default-to-llvm16.patch` | SwiftShader | Apache-2.0 |
| `0003-cpuinfo-fix-hwprobe-cpu_set-type-on-bionic.patch` | cpuinfo | BSD-2-Clause |

`aosp/webview/Android.bp` dérive d'AOSP et porte son propre en-tête Apache-2.0.

L'APK que produit cette recette est un build de Chromium, couvert par le licensing
propre à Chromium, qu'il n'appartient pas à ce repo d'accorder.
