# PlezyTV screen links

Open a screen on a running app or launch it with the same command. Screen links
wait in memory until the active profile’s main screen is ready. Finish sign-in
and profile selection normally. Only the latest waiting link is retained; there
is no timeout or persistence across process exit.

```sh
adb shell am start -a android.intent.action.VIEW -d 'plezytv://screen/home'
adb shell am start -a android.intent.action.VIEW -d 'plezytv://screen/libraries'
adb shell am start -a android.intent.action.VIEW -d 'plezytv://screen/library?id=1'
adb shell am start -a android.intent.action.VIEW -d 'plezytv://screen/item?id=12345'
adb shell am start -a android.intent.action.VIEW -d 'plezytv://screen/search'
adb shell am start -a android.intent.action.VIEW -d 'plezytv://screen/search?q=the%20matrix'
adb shell am start -a android.intent.action.VIEW -d 'plezytv://screen/downloads'
adb shell am start -a android.intent.action.VIEW -d 'plezytv://screen/settings'
adb shell am start -a android.intent.action.VIEW -d 'plezytv://screen/update'
```

`home` selects the first visible tab, just like the app’s Home command. `library`
selects the section in the normal Libraries screen. `item` opens details for a
movie, show, season or episode, never starts playback. Replace example IDs with
IDs from your server. Add `&server=<machineId>` to disambiguate library/item
IDs; otherwise the first connected server resolving the ID wins. Keep the URI
quoted and percent-encode search query text when needed. Item and library IDs
must contain decimal digits only; server identifiers accept ASCII letters,
digits and hyphens. Links wait during profile selection/binding and library
initialization, including when the requested known server is still connecting.

`update` runs a manual PlezyTV update check in tagged builds. Later screen links
can proceed while it checks; a superseded check does not open a result dialog. Untagged builds
(no `PLEZYTV_VERSION`) have no updater UI or network checks. Invalid links,
missing IDs, unknown servers/IDs and invisible tabs leave the current screen
unchanged and produce one `appLogger` warning with the URI and reason. Existing
`plezytv://play`, `plezytv://live` and shelf IDs retain their original handling.
The separate log-tag task adds `adb logcat -s PlezyTV`; until it lands, warnings
use the existing Flutter logging output.

After the requested screen finishes loading, capture the TV display:

```sh
adb exec-out screencap -p > plezytv-settings.png
```

For a cold-start check, close PlezyTV first, issue the same screen command,
complete any profile/sign-in step, then capture. Back and D-pad navigation use
the existing main screen and profile navigator.

## PlezyTV updates

Tagged Android builds check the anonymous `underlow/PlezyTV` latest release once
per six hours after the main screen is ready. Automatic failures only log;
manual checks (Settings or the link above) report the result and ignore the
cooldown and skipped version. Only exact `vX.Y.Z` tags and the installed app’s
ARM ABI asset qualify. An automatic offer waits while any video route is active.

Install downloads into app cache with progress and Cancel. If Android asks for
permission to install apps, allow it for PlezyTV, return, and press Install again;
the completed download is reused. Old update downloads are removed at the next
startup and before downloading another APK. This is separate from the disabled
upstream updater. Fork-owned dialog strings support English and Russian.

Local checks cover mocked releases, failure/cancel cleanup, permission retry,
remote dialog focus, startup timer shutdown and active/covered video routes.
A real signed release and device are still needed to verify the complete
GitHub download → Android permission setting → package installer → replacement
flow. No TV installation was attempted for T4 (device storage is full).

S16 filtered library route:
`plezytv://screen/library-filter?id=42&field=genre&value=1&server=machine-id`.
`id`, `field`, `value` are required; `server` is optional. Encode field/value as URL query
components. IDs retain the Plex digits-only rule. `field` and `value` are accepted only by
`library-filter`; `q` is not accepted there. The router checks the library, its TV video
eligibility, then the server's filter field and listed value before pushing a route.
Unknown libraries, non-video libraries and unknown fields/values leave the current screen in
place and log a PlezyTV warning. The route starts on Browse, retains saved grouping/sort,
replaces saved filters with this one clause, and stores all subsequent changes only in memory.
Back returns to the previous screen; shell selection stays unchanged.

## Settings transfer over adb

The fixed-file Backup section is available on Android with the TV UI enabled.
Desktop force-TV keeps Plezy’s file picker; tvOS keeps Backup hidden. Importing
also updates an existing Search keyboard immediately, including while Search is
retained behind another section.

Choose/sign in to a profile first, or send the link while the profile picker is
open: it waits until selection finishes. Only the newest pending screen/settings
link is kept. Import applies immediately without a confirmation dialog or restart.

```sh
adb shell am start -a android.intent.action.VIEW -d 'plezytv://settings/export' -p com.underlow.plezytv
adb logcat -s PlezyTV
# Wait for "Settings export: <count> keys" before reading the file:
adb shell content read --uri content://com.underlow.plezytv.settings/settings.json > ./plezytv-settings.json

# On the destination TV (use adb -s <serial> with multiple connected devices):
adb shell 'content write --uri content://com.underlow.plezytv.settings/settings.json' < ./plezytv-settings.json
adb shell am start -a android.intent.action.VIEW -d 'plezytv://settings/import' -p com.underlow.plezytv
adb logcat -s PlezyTV
```

Export overwrites this fixed file with portable Plezy and PlezyTV settings, without
tokens, server addresses or search history. Import reports the imported/skipped
key counts; failures report their cause. A short on-screen notification also shows
the result. Missing or invalid files leave preferences unchanged. No query
parameters are accepted. The `settings` intent filter has no `BROWSABLE` category;
these commands are intended for adb rather than browser links. Existing `screen`,
`play` and `live` links retain their handling.

The provider accepts only shell (adb) and root callers. It exposes only
`settings.json`, with read or truncating write access; it does not apply settings
until the import link is sent. The underlying file remains
`/sdcard/Android/data/com.underlow.plezytv/files/plezytv-settings.json`
(`getExternalFilesDir(null)`), for reference only: direct adb access is denied on
the tested Xiaomi Android 11 device. No root or debug build is needed.

Local tests/build checks do not establish provider commands or cold/warm intent
behavior on a real TV. Android 9 availability of `content write` remains unverified.

## S26: startup and image measurements

Host requirement: Node 22+ (global WebSocket), Android SDK adb at
`~/Library/Android/sdk/platform-tools/adb` (override with `ADB`). No device is
selected implicitly. Install the desired build and sign in first; these commands
never build, install, or connect to a TV themselves.

```sh
node scripts/plezytv/measure/measure.mjs cold --device SERIAL --package com.underlow.plezytv --runs 7 --delay 20
node scripts/plezytv/measure/measure.mjs images --device SERIAL --package com.underlow.plezytv --delay 20
node scripts/plezytv/measure/measure.mjs laps --device SERIAL --package com.underlow.plezytv --runs 5 --delay 20
```

`cold` force-stops and launches the installed app for each run, clears logcat,
then samples `dumpsys meminfo` N seconds after `am start -W` returns. Output is
JSON lines: PSS and Graphics in MiB, each startup phase in milliseconds relative
to the first `native_on_create` logcat timestamp, and `bindingToHomeMs` from
`binding_settled` to `TV home rows ready`. This uses logcat timestamps, not the
Dart stopwatch's `elapsedMs`. Missing marks are null/absent, never zero; summary
reports sample/missing counts and min/median/max for each metric. For an original
Plezy comparison, missing TV readiness is expected. Activity name is
`PACKAGE/com.edde746.plezy.PlezyActivity` (the fork retains the upstream
Android namespace; override the class with `--activity CLASS` for another build).
This also works when the launcher icon alias is disabled.

Home logs `TV home rows ready: visibleRows=N` once per load after both data
parts finish and every visible row's first poster contains a decoded `RawImage`
after a frame. Visibility is intersection with the rows viewport; partially
visible rows count. Hidden Home does not emit. Missing or failed first artwork
leaves the mark absent rather than claiming readiness from a placeholder.
This is a Flutter paint-frame proxy, not proof of physical display presentation.

`images` requires an installed **profile** build. It cold-launches with Dart
profiling enabled, discovers the service in logcat, creates an ephemeral adb
forward, waits `delay` seconds, and removes its forward on exit. To inspect the
current screen (search, movie, series, or Home after scrolling), supply
`--uri http://127.0.0.1:PORT/TOKEN/` from an existing host-forwarded VM service;
that mode neither launches nor navigates. Keep VM tokens private.
It requests GC, counts live `dart:ui _Image` instances, ImageCache `_cache` and
`_liveImages` entries, and mounted `TvHorizontalRowState` instances (all mounted
screens, including retained hidden sections; non-null `_element` denotes mounted).
Inspection uses `getInstances(objectId: classId)` and `getObject`, including paged
map associations; it works without `evaluate`, which profile AOT builds reject.
`currentSizeMiB`/`maximumSizeMiB` report Flutter cache bytes converted to MiB
(the reduced-mode budget is 64 MiB). `heldByWidgetsApprox` subtracts
cache keys absent from `_liveImages` from `_Image` count. This is approximate:
cache entries, keys, image wrappers and native images are not one-to-one;
listeners may belong to non-widget consumers, pending images and other screens
also contribute. It cannot prove a precise count of offscreen images or native
GPU bytes. Private Flutter fields may change; unsupported layouts fail loudly.
The map comparison uses key object ids. These sequential reads are not an atomic
snapshot: images, listeners and cache membership can change during inspection;
detected map size/key inconsistencies fail with a retry message. VM inspection/GC
also perturbs the app: measure release PSS separately.

`laps` is operator-guided so library identity, focus position and movie selection
remain explicit. Start on settled Home, confirm baseline, navigate Home → library
→ movie → back to library → back to Home for each prompt, then confirm. It waits
`delay` seconds each lap and prints per-lap memory, baseline/final memory and PSS
delta. Use the same movie and navigation every time. No playback is needed.

Measurement accuracy is limited: content, poster sizes, visible rows, server and
network state vary. Compare several runs on the same device/server on the same
day with original Plezy as reference. Record build mode, content and viewport;
20 seconds is a sampling delay, not a guarantee that Home has finished loading.
Device acceptance A1/A2/A4/A6/A13 remains a coordinator check.
