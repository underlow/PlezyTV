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
# Wait for "Settings export: <count> keys" before pulling the file:
adb pull /sdcard/Android/data/com.underlow.plezytv/files/plezytv-settings.json ./plezytv-settings.json

# On the destination TV (use adb -s <serial> with multiple connected devices):
adb push ./plezytv-settings.json /sdcard/Android/data/com.underlow.plezytv/files/plezytv-settings.json
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

Local tests/build checks do not establish `adb push` access on Android 9/11 or
cold/warm intent behavior on a real TV; those remain device acceptance checks.
