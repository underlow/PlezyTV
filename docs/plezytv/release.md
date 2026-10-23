# Building and releasing PlezyTV

The Android application ID is `com.underlow.plezytv`; Kotlin classes retain the
upstream namespace. Keep the signing key safe and backed up: all subsequent
updates must use the same key. Never commit signing material.

Create your own release key (keytool prompts for passwords):

```sh
keytool -genkeypair -v -keystore plezytv-release.jks -alias plezytv \
  -keyalg RSA -keysize 4096 -validity 10000
base64 < plezytv-release.jks | tr -d '\n'
```

In repository Settings → Secrets and variables → Actions add:

- `ANDROID_KEYSTORE_BASE64`: the base64 output above.
- `ANDROID_STORE_PASSWORD`: keystore password.
- `ANDROID_KEY_PASSWORD`: key password.
- `ANDROID_KEY_ALIAS`: `plezytv` (or your chosen alias).

The PlezyTV release workflow fails if any secret is missing, decodes the keystore
only for the job, and removes it even after failure. It builds signed
armeabi-v7a and arm64-v8a APKs with upstream update checking and Sentry disabled
(their compile-time defaults are false). Manual runs upload APK artifacts; `v*`
tags also publish a GitHub Release. Tags must have the exact format `vX.Y.Z`
(nonnegative decimal components, no leading zeros, suffixes or prereleases);
other tag formats fail the build. Artifact names use the tag on tagged builds
and the pubspec version on manual builds.

Tagged builds bake `PLEZYTV_VERSION=X.Y.Z` into Dart and use Android
`versionCode = major*10000 + minor*100 + patch`: `v0.2.0` → `200`,
`v1.2.3` → `10203`. Both ABI APKs have the same versionCode; Flutter’s ABI
offsets are disabled outside AMAZON builds. Keep minor and patch below 100
and ensure each release code increases. Manual CI and ordinary local builds
have no `PLEZYTV_VERSION`, so the fork updater stays disabled; their build
number still comes from pubspec unless explicitly overridden.

**One-time migration from v0.1.0:** its APK codes were 1156/2156. Android
refuses an in-place update to v0.2.0 (code 200). Uninstall PlezyTV once, then
install the matching new APK; uninstalling removes local app data and requires
signing in again. Original Plezy is a separate app and is unaffected. Subsequent
releases use increasing tag-derived codes and the same signing key.

Run **PlezyTV release** manually to validate signing before publishing. To release
an already reviewed commit, create and push a tag yourself:

```sh
git tag v0.2.0
git push origin v0.2.0
```

Download the matching ABI APK and install alongside original Plezy:

```sh
adb install -r plezytv-v0.2.0-armeabi-v7a.apk
adb shell am start -a android.intent.action.VIEW -d 'plezytv://live?channel=4.1'
```

Check both apps appear and launch independently. Original `plezy://` links should
continue to resolve to Plezy. On manual builds, verify no updater dialog appears
in PlezyTV.

## Repository setup (manual)

In Actions, open each inherited workflow (`build.yml`, `ci.yml`,
`update-packages.yml`) and choose **… → Disable workflow**. Their source files
remain unchanged so upstream stays mergeable. Leave `plezytv-build.yml` and
`plezytv-upstream.yml` enabled. Repository Actions settings must permit GitHub
Actions to create pull requests, and the workflow token needs contents, PR and
issue write access. No workflow pushes to main.

Optional secret `UPSTREAM_SYNC_TOKEN`: a fine-grained personal access token scoped
only to this repository, with **Contents**, **Pull requests**, **Issues**, and
**Workflows** read/write permissions. When present, upstream sync uses it for
checkout, push and GitHub CLI operations. Without it, the workflow uses
`GITHUB_TOKEN`. If incoming commits touch `.github/workflows/`, the default token
cannot push them: sync skips the push and validation, opens/updates its status
issue with the affected paths and token instructions, and fails the run. Add the
secret and rerun to proceed. Detection covers every incoming commit, including
workflow edits subsequently reverted in that history.

**PlezyTV upstream sync** runs weekly and manually. It recreates `upstream-sync`
from main, merges upstream/main, installs root and wakelock_plus dependencies,
runs the upstream analyzer wrapper, native formatting, Flutter tests and a debug
Android build, and opens or
updates a PR. That branch is automation-owned: do not put manual work there.
Conflicts produce an `upstream-sync` issue with paths; failed checks still produce
a PR plus an issue with logs. When repository issues are disabled, the report
is written to the Actions job summary instead; a failed sync still fails the run.
Successful later runs close the status issue when issues are enabled. All GitHub
CLI operations explicitly target this fork via `GH_REPO`.
Review and merge the PR manually. `GITHUB_TOKEN` pushes do not trigger other
Actions workflows; PAT pushes can trigger enabled workflows. The sync workflow
itself performs validation when push authorization permits it. Conflicts,
release signing, device acceptance and real GitHub automation must be verified
in the configured repository; local source checks do not establish these.

## Local build verification

Use the checkout-local Flutter/CMake tools and JDK 21 (matching CI):

```sh
export JAVA_HOME="$PWD/.tools/jdk21/Contents/Home"
export PATH="$JAVA_HOME/bin:$PWD/.tools/flutter/bin:$PWD/.tools/cmake-4.1.2/CMake.app/Contents/bin:$PATH"
export XDG_CONFIG_HOME=/private/tmp/plezytv-flutter-config
flutter build apk --release --split-per-abi --target-platform android-arm,android-arm64 --build-number=200
for abi in armeabi-v7a arm64-v8a; do
  "$HOME/Library/Android/sdk/build-tools/36.1.0/aapt2" dump badging \
    "build/app/outputs/flutter-apk/app-$abi-release.apk" | head -1
done
```

Both package lines must report `versionCode='200'`. This local build omits
`PLEZYTV_VERSION`; the tagged workflow supplies it separately. Without local
`android/key.properties`, these APKs are unsigned and only verify packaging.
