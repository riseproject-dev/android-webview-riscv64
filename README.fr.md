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
| Chromium 141.0.7366.3 (`refs/branch-heads/7366`) | **Vérifié sur matériel** — SpacemiT K1 (X60), Android 17, `ro.vendor.api_level=202604`. Affiche des pages ; le renderer tourne sandboxé (`Seccomp: 2`). |
| Chromium 151.0.7922.108 (M151 stable) | **En cours.** La série est en cours de rebase ; pas encore compilée, jamais exécutée. |
| Autres boards que la SpacemiT K1 | **Non testé.** Le build est riscv64 générique, mais seule la K1 a booté. |
| Cuttlefish (`aosp_cf_riscv64_phone`) | **Non testé.** |
| Support riscv64 upstream | **Non mergé.** Deux des six commits sont des changelists Gerrit non mergées, le reste est local. |

« Vérifié » ne veut pas dire « supporté ». C'est une recette qui marche, pas un
produit.

## Où vit quoi

Les changements de source sont des **commits sur un fork**, pas des fichiers patch :

- **[BayLibre/chromium](https://github.com/BayLibre/chromium)**, branche
  `spacemit-riscv64-m141` — les six commits riscv64 au-dessus de la révision upstream
  épinglée. Reviewables, bisectables, et rebasables avec `git rebase --onto`.
- **Ce repo** — la recette : scripts, configuration de build, glue AOSP,
  documentation, et le seul changement que le fork ne peut pas porter (voir plus bas).

`third_party/ffmpeg` est un repo git séparé : un fork de `chromium/src` ne peut donc
pas contenir ses changements. Ils vivent ici, dans
`patches/0001-ffmpeg-support-android-riscv64.patch`.

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
(136 465 503 octets pour le build vérifié).

`WORKSPACE=/chemin/quelque/part` déplace le checkout. Tout le reste est épinglé dans
`scripts/config.sh` — c'est là, et nulle part ailleurs, qu'on change une révision.

Une contrainte d'ordre : **relancer `gclient sync` annule les étapes SwiftShader et
ffmpeg**, parce que toutes deux vivent dans des sous-repos que gclient possède. Il
faut relancer `02-apply-series.sh` après chaque sync.

## La série

| # | Commit | Origine |
|---|---|---|
| 1 | `sandbox: Add support for riscv64-linux` | [crrev.com/c/4935120](https://chromium-review.googlesource.com/c/chromium/src/+/4935120) PS11, par Andreas Schwab. Non mergé. |
| 2 | `swiftshader: roll to a revision that defaults to LLVM 16` | [SwiftShader CL 75929](https://swiftshader-review.googlesource.com/c/SwiftShader/+/75929) PS2, par Levi Zim. Non mergé. |
| 3 | `build/config: riscv64: build with -mstrict-align` | local |
| 4 | `android: do not apply the 32-bit version code offset on riscv64` | local |
| 5 | `cpuinfo: enable the riscv linux sources on android` | local, upstreamable tel quel |
| 6 | `ffmpeg: support the android-riscv64 build` | local (patch compagnon dans `patches/`) |

Deux d'entre eux méritent une explication.

**Le commit 1 n'est optionnel dans aucun des deux sens.** Sans lui, riscv64 ne
compile pas : `sandbox/linux/bpf_dsl/seccomp_macros.h` termine sa chaîne
d'architectures par `#error Unsupported target platform`, et `linux_syscalls.h` n'a
aucun include riscv64. Ce n'est pas non plus du poids mort au runtime — le renderer
WebView tourne réellement en `SECCOMP_MODE_FILTER`, donc la policy doit connaître la
numérotation des syscalls riscv64.

**Le commit 3 existe à cause d'un SIGBUS, pas d'une préférence.** Le SpacemiT X60
trappe sur les accès vectoriels non alignés : `hwprobe` rapporte vector-misaligned
comme UNSUPPORTED, et le handler misaligned du kernel n'émule que les `vle`/`vse`
unit-stride, jamais les `vlse` stridés. Sans `-mstrict-align`, l'autovectorizer émet
un `vlse64.v` stridé avec des éléments non alignés (dans `ui::GestureDetector`, entre
autres) et WebView meurt en `SIGBUS`/`BUS_ADRALN` au premier `loadUrl`. À noter, le
coût : le flag s'applique à **tous** les builds riscv64, donc du matériel dont le
support misaligned vectoriel fonctionne paie un alignement dont il n'a pas besoin. Il
n'y a pas encore d'argument gn pour s'en dispenser.

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

- Le rebase M151 n'est pas terminé ; la révision épinglée dans `config.sh` est celle
  de M141, qui a réellement été vérifiée.
- `-mstrict-align` est inconditionnel. Un argument gn `riscv_strict_align`
  permettrait au matériel non-SpacemiT de s'en passer, mais il n'existe pas encore.
- Deux morceaux test-only de la changelist sandbox ne sont pas portés :
  `syscall_parameters_restrictions_unittest.cc` n'existe plus upstream, et la branche
  riscv de `syscall_unittest.cc` (une assertion sur l'opcode ECALL) manque. Ni l'un
  ni l'autre n'est compilé par la target WebView, donc l'APK livré n'est pas affecté.
- Rien n'est upstreamé ici. Le commit 5 pourrait l'être tel quel ; les autres
  demandent du travail.
