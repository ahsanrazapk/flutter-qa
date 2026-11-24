# Device controls

Pilot only sees what Flutter draws. Everything around the app (permissions,
stored data, deep links, location, the system's look) is set with the tools
that ship with the Flutter, Android and Xcode toolchains. Set these up
**before** `pilot start`, or `pilot restart` afterwards, so the app meets them
from a clean launch.

Find the ids first: `flutter devices` for the device id, and the application id
in `android/app/build.gradle*` (`applicationId`) or the bundle id in
`ios/Runner.xcodeproj/project.pbxproj` (`PRODUCT_BUNDLE_IDENTIFIER`).

## Any device

| Goal | Command |
|---|---|
| List devices and emulators | `flutter devices`, `flutter emulators` |
| Boot an emulator or simulator | `flutter emulators --launch <emulator id>` |
| Know an Android emulator has finished booting | `adb shell getprop sys.boot_completed` prints `1`. Installing before that fails with `Broken pipe`. |
| Screenshot of the whole device, native UI included | `flutter screenshot -d <device> -o shot.png` |

## Android (`adb -s <device>` when more than one is connected)

| Goal | Command |
|---|---|
| Clear the app's stored data | `adb shell pm clear <application id>` |
| Grant a runtime permission before the prompt appears | `adb shell pm grant <application id> android.permission.CAMERA` |
| Take a permission away | `adb shell pm revoke <application id> android.permission.CAMERA` |
| Open a deep link | `adb shell am start -a android.intent.action.VIEW -d "myapp://cart/42" <application id>` |
| Press system back, home | `adb shell input keyevent KEYCODE_BACK`, `KEYCODE_HOME` |
| Tap a native dialog pilot cannot see | `adb shell input tap X Y` (physical pixels, from `flutter screenshot`) |
| Dark mode on, off | `adb shell cmd uimode night yes`, `no` |
| Larger system text | `adb shell settings put system font_scale 1.3` (back to `1.0` afterwards) |
| Set the location (emulator) | `adb emu geo fix <longitude> <latitude>` (longitude first) |
| Go offline, online | `adb shell cmd connectivity airplane-mode enable`, `disable` |
| Record video | `adb shell screenrecord /sdcard/run.mp4`, then `adb pull /sdcard/run.mp4` |

## iOS simulator (`booted` means the running simulator)

| Goal | Command |
|---|---|
| Clear the app's stored data | `xcrun simctl uninstall booted <bundle id>`, then `pilot start` reinstalls it |
| Grant a permission before the prompt appears | `xcrun simctl privacy booted grant photos <bundle id>` (also `location`, `location-always`, `microphone`, `contacts`) |
| Reset all permissions | `xcrun simctl privacy booted reset all <bundle id>` |
| Open a deep link | `xcrun simctl openurl booted "myapp://cart/42"` |
| Dark mode on, off | `xcrun simctl ui booted appearance dark`, `light` |
| Set the location | `xcrun simctl location booted set <latitude>,<longitude>` |
| Send a push notification | `xcrun simctl push booted <bundle id> payload.json` |
| Add photos to the library | `xcrun simctl addmedia booted photo.jpg` |
| Record video | `xcrun simctl io booted recordVideo run.mp4` (Ctrl-C to stop) |

## Desktop

- Pilot keeps working when the app's window is hidden or covered: it draws
  frames itself when the display stops asking for them. `flutter test
  integration_test` does not, and hangs until the window is visible again.
- Stored data lives in the user's application support folder; delete the app's
  folder there to start clean.

## Rules

- Put every device back the way it was: text scale, dark mode, airplane mode
  and location outlive the session.
- Granting a permission in advance tests the granted path only. The denied
  path and the prompt itself still need a person: list them as manual checks.
- These commands change a device, so name the device explicitly when several
  are connected.
