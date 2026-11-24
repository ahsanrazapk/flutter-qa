# QA report: <app or change>

**Verdict:** <Ready | Ready with the listed risks | Not ready>: <one sentence saying why>

## Scope

- Checked: <screens, rules, journeys>
- Build: <branch and commit, or "not under git">, debug
- Devices: <device ids and OS versions actually used>
- Backend and account: <which>
- Out of scope: <what was deliberately left out>

## Results

| Layer | Command | Result |
|---|---|---|
| Static analysis | `flutter analyze` | <0 errors, 3 warnings> |
| Formatting | `dart format --output=none --set-exit-if-changed .` | <clean / N files> |
| Architecture | `arch_check.dart` | <0 violations, 0 cycles> |
| Unit and widget tests | `flutter test --coverage` | <212 passed, 0 failed; 81% of lines> |
| Integration tests | `flutter test integration_test -d <device>` | <4 passed on emulator-5554; not run on iOS: no simulator booted> |
| Pilot flows | `pilot.dart run pilot/<name>.flow` | <6 passed, 1 failed> |
| Exploration | pilot, <N> screens | <2 defects, 1 app error> |

Tests added in this pass: <files, or "none">

## Defects

<Most severe first. One block each, in the format from the skill:
title with severity, steps (a pilot flow where possible), expected, actual,
evidence with file and line, device.>

## Coverage by module

<Paste the "Line coverage" section of arch_check, then name the rules and
screens in scope that still have no test.>

## Not covered

<What a person still has to check, and why automation did not reach it.
Include every device or platform in scope that was not run.>

## How to repeat this

```
<the exact commands, in order, including --dart-define names (not values)>
```
