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
armeabi-v7a and arm64-v8a APKs with update checking and Sentry disabled (their
compile-time defaults are false). Manual runs upload APK artifacts; `v*` tags
also publish a GitHub Release. Artifact versions use the tag on tagged builds,
and pubspec version on manual builds. Update pubspec version/build number when
preparing an app update.

Run **PlezyTV release** manually to validate signing before publishing. To release
an already reviewed commit, create and push a tag yourself:

```sh
git tag v0.1.0
git push origin v0.1.0
```

Download the matching ABI APK and install alongside original Plezy:

```sh
adb install -r plezytv-v0.1.0-armeabi-v7a.apk
adb shell am start -a android.intent.action.VIEW -d 'plezytv://live?channel=4.1'
```

Check both apps appear and launch independently. Original `plezy://` links should
continue to resolve to Plezy. Verify no updater dialog appears in PlezyTV.

## Repository setup (manual)

In Actions, open each inherited workflow (`build.yml`, `ci.yml`,
`update-packages.yml`) and choose **… → Disable workflow**. Their source files
remain unchanged so upstream stays mergeable. Leave `plezytv-build.yml` and
`plezytv-upstream.yml` enabled. Repository Actions settings must permit GitHub
Actions to create pull requests, and the workflow token needs contents, PR and
issue write access. No workflow pushes to main.

**PlezyTV upstream sync** runs weekly and manually. It recreates `upstream-sync`
from main, merges upstream/main, runs analyze/tests/debug build, and opens or
updates a PR. That branch is automation-owned: do not put manual work there.
Conflicts produce an `upstream-sync` issue with paths; failed checks still produce
a PR plus an issue with logs. Successful later runs close the status issue.
Review and merge the PR manually. Workflow-token pushes do not trigger other
Actions workflows; the sync workflow itself performs the validation. Conflicts,
release signing, device acceptance and real GitHub automation must be verified
in the configured repository; local source checks do not establish these.
