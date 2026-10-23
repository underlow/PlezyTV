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
quoted and percent-encode query text and IDs when needed.

`update` is reserved and currently logs "update unavailable". Invalid links,
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
