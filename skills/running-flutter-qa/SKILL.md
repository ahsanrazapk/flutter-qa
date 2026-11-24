---
name: running-flutter-qa
description: Use when asked to QA, test thoroughly, verify, sign off or check the release readiness of a Flutter app, feature, branch or pull request - or to find what is untested, or to say what still needs manual testing.
---

# Running Flutter QA

## Overview

QA produces a statement about risk: what was checked, how, what broke, and
what nobody has checked yet. This skill runs every automated layer in order,
cheapest first, and ends with a report a person can act on.

**Core rule: a check passed only if you ran it in this session and read its
output.** Not "the tests should pass", not last week's run. Each line of the
report names its command and its result.

**Second rule: report what you find; do not quietly fix it.** A QA pass that
edits the app as it goes cannot say what state the app was in. Fix only when
asked, and then re-run the layer that found the problem.

## 1. Fix the scope

- The whole app, or a change? For a change: `git diff --stat <base>...HEAD`
  and list the screens, rules and journeys it touches, plus what depends on
  them.
- Which devices matter (Android, iOS, tablet, desktop)? Run `flutter devices`
  and use only those it lists as connected; ignore any marked offline or
  unauthorised. A physical phone is somebody's phone: use it only if the user
  named it.
- Which backend and account may be used? Never run flows that write data
  against production. Ask if it is not obvious.

Write the scope down as the first lines of the report.

## 2. Run the layers in order

| # | Layer | What to do | Skill |
|---|---|---|---|
| 1 | Static | `flutter analyze`; `dart format --output=none --set-exit-if-changed .` (rewrites nothing: exit code 1 and its `Changed` lines name the unformatted files); the architecture checker | **reviewing-flutter-architecture** |
| 2 | Logic | Every rule in scope has unit tests for its cases, including failure paths; `flutter test --coverage`, then the architecture checker again for coverage by module | **testing-flutter-logic** |
| 3 | UI | Every screen in scope has widget tests for its states, one accessibility test, one small-screen large-text test | **testing-flutter-ui** |
| 4 | Journeys | Critical paths as integration tests, run on a device | **testing-flutter-flows** |
| 5 | Exploration | Drive the running app through everything in scope, trying to break it | **driving-flutter-apps** |
| 6 | Report | Fill in [qa-report-template.md](qa-report-template.md) | |

Do them in this order: a compile error makes every later layer meaningless,
and a logic bug found in 2 saves an hour of chasing it in 5.

A layer that fails does not stop the pass. Record the failure, carry on with
whatever can still run, and say in the report which later results the failure
makes unreliable. A layer you could not run, or were told not to, goes in the
results as `not run`, with the reason, and again under "Not covered".

Read exit codes from the command itself: piping it through `tail` or `head`
replaces its exit code with theirs.

Missing tests are a result, not a blocker: for a QA request, write the tests
that are missing for what is in scope (layers 2 to 4), and list them in the
report as added. If the code cannot be tested as it stands, that is a finding
for layer 1.

## 3. Exploration: how to try to break a screen

Automated tests check what someone thought of. Exploration looks for the rest.
On every screen in scope, with pilot:

| Try | Looking for |
|---|---|
| Every tappable element once | dead buttons, wrong destinations, exceptions |
| Back from every screen and every dialog, including the system back | lost input, a dialog that will not close, exiting to the wrong place |
| Each field: empty, only spaces, 500 characters, emoji, right-to-left text, spaces around a valid value | crashes, overflow, missing validation, unhelpful messages |
| Double tap every button that submits, pays, saves, deletes or navigates: `pilot tap <target> --double` | two orders, duplicate rows, a page opened twice, a screen that closes twice, an exception |
| Leave while it is loading (`back` straight after a submit) | exceptions after the screen is gone |
| Scroll every list to its end | overflow, a last row hidden under a floating button, an empty state |
| Do it, undo it, do it again; sign out and back in | stale state from the first time |
| `restart`, then look again | state that should have been saved, or should not have been |
| Dark mode, largest text, a small screen (device controls) | unreadable or clipped UI |
| `pilot shot` on every screen, and look at it | unstyled text (red, yellow underline), overlap, clipping: none of it shows in a snapshot |
| Offline in the middle of a load (device controls) | a spinner for ever, no retry |

After every action read the `! app error` lines. Each one is a defect even if
nothing looked wrong.

Save a pilot flow for every defect you can reproduce: the flow is the bug
report's steps, and later the proof that it is fixed.

## 4. Writing a defect

```
[High] Placing an order twice charges twice
Steps:    pilot/double_order.flow  (sign in, add Product 3, checkout, tap "Place order" twice)
Expected: one order
Actual:   two "Order placed" messages; cart total charged twice
Evidence: snapshot after step 9 shows 2 orders; lib/checkout/checkout_page.dart:88 has no guard
Device:   emulator-5554, Android 16
```

Severity: **High** blocks a journey, loses data or money, or crashes.
**Medium** gives a wrong result with a workaround. **Low** is cosmetic.

## 5. Say what is left

Automation here does not reach everything. Always list, under "Not covered",
whichever of these apply, so that a person knows where to look:

- Release builds: obfuscation, performance, start-up time, app size
- Native UI and services: permission prompts and their denied paths, push
  notifications, in-app purchases and payments, sign-in with a third party,
  camera, biometrics, maps, web views, share sheets
- Real devices: old or small phones, notches and foldables, slow networks,
  low memory, interruptions such as calls and backgrounding
- A real screen reader (TalkBack, VoiceOver), beyond the guideline checks
- Whether it looks and feels right: spacing, motion, wording, translations
- Store and platform requirements; upgrade from the previous version with
  existing user data
- Any device or platform that was in scope but not run in this session

Never write "fully tested" or "no issues". Write what ran, what it showed, and
what did not run.

## Common mistakes

| Mistake | Instead |
|---|---|
| Reporting a layer as passed from memory or from CI | Run it now, quote the last line of its output |
| Stopping at the first failure | Record it and continue; one pass, one complete report |
| Fixing bugs mid-pass without saying so | Report first. If asked to fix, re-run the layer afterwards. |
| Only walking the happy path in exploration | Use the table in section 3 on every screen |
| An empty "Not covered" section | It is never empty. If it looks empty, the scope was not written down. |
| Counting a test nobody saw fail | Break the code once to see it go red |
