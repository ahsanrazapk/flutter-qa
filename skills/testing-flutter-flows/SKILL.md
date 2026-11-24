---
name: testing-flutter-flows
description: Use when writing, running or fixing Flutter end-to-end tests with integration_test on a device, emulator, simulator or desktop - a user journey such as sign-in, checkout or onboarding - or when an integration test is flaky, times out, hangs, or cannot find a widget that is on screen.
---

# Testing Flutter Flows

## Overview

An integration test runs the real app on a real device and walks one user
journey through it. It is the slowest and most expensive layer, so it carries
only what the cheaper layers cannot: that the pieces work together, on a
device, from launch.

**Core rule: one journey per test, proven by what the user ends up seeing.**
Rules, edge cases and screen states belong in unit and widget tests
(**testing-flutter-logic**, **testing-flutter-ui**).

## Which journeys

Write one for each path that would make the release unusable if it broke:
launch and sign in, the main purchase or create flow, sign out, and whatever
this app exists to do. Five solid journeys beat fifty brittle ones.

## Walk it before writing it

Do the journey first on the running app with **driving-flutter-apps**. The
snapshot gives the keys, tooltips and source lines to target, shows which
steps need scrolling, and reports exceptions the journey triggers. Then
translate each step:

| Pilot step | Test code |
|---|---|
| `type "x" --key email` | `await tester.enterText(find.byKey(const Key('email')), 'x');` |
| `tap --key sign_in` | `await tester.tap(find.byKey(const Key('sign_in')));` |
| `tap --tooltip "Add"` | `await tester.tap(find.byTooltip('Add'));` |
| `wait --text "Welcome"` | `await pumpUntilFound(tester, find.text('Welcome'));` |
| `scroll-to --text "Row 30"` | `scrollUntilVisible`, then `Scrollable.ensureVisible` (below) |
| `back` | `await tester.pageBack();` |

Add a `Key` in the app's code for anything the test acts on that has none.

## Pattern

```dart
// integration_test/checkout_flow_test.dart
const password = String.fromEnvironment('QA_PASSWORD');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a signed-in user can place an order', (tester) async {
    app.main();
    await pumpUntilFound(tester, find.byKey(const Key('sign_in')));

    await tester.enterText(find.byKey(const Key('email')), 'ada@example.com');
    await tester.enterText(find.byKey(const Key('password')), password);
    await tester.tap(find.byKey(const Key('sign_in')));
    await pumpUntilFound(tester, find.text('Welcome, ada@example.com'));

    // Far down a lazy list: scroll until the row exists, then bring it clear
    // of anything that floats over the list.
    final addButton = find.byTooltip('Add Product 30');
    await tester.scrollUntilVisible(
      addButton,
      300,
      scrollable: find.descendant(
        of: find.byType(ListView),
        matching: find.byType(Scrollable),
      ),
    );
    await Scrollable.ensureVisible(tester.element(addButton), alignment: 0.5);
    await tester.pump();
    await tester.tap(addButton);
    await pumpUntilFound(tester, find.text(r'Cart: 1 items · $348.75'));
  });
}

/// Pumps frames until [finder] matches. Unlike pumpAndSettle it works on
/// screens where something animates for ever, and never waits longer than
/// it has to.
Future<void> pumpUntilFound(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 15),
}) async {
  final deadline = tester.binding.clock.now().add(timeout);
  while (finder.evaluate().isEmpty) {
    if (tester.binding.clock.now().isAfter(deadline)) {
      fail('Timed out after ${timeout.inSeconds}s waiting for $finder');
    }
    await tester.pump(const Duration(milliseconds: 100));
  }
}
```

Setup, once per project:
`flutter pub add "dev:integration_test:{\"sdk\":\"flutter\"}"`.

## Rules that keep flows from flaking

1. **Wait for a condition, never for a time.** After every step that loads or
   navigates, `pumpUntilFound` the thing the user would see next. No
   `Future.delayed`, no bare `pump(Duration(seconds: 3))`.
2. **`pumpAndSettle` only on screens you know come to rest.** A spinner or a
   looping animation makes it time out; a real backend makes it return too
   early. `pumpUntilFound` is right in both cases.
3. **Scroll, then centre, then tap.** `scrollUntilVisible` stops when the row
   first shows at the edge, often under a floating button or the navigation
   bar.
4. **Start from a known state.** Each test launches the app itself. If the app
   keeps a session or data, clear it first (see the device controls in
   **driving-flutter-apps**) or use a fresh test account.
5. **Secrets come from `--dart-define`**, read with `String.fromEnvironment`.
   Never commit a real password, token or production URL.
6. **Use a test backend or test account** whose data the test may change.
   Ask which one before running a flow that writes anything.
7. **Assert the outcome**, not only that no step threw: the order confirmation,
   the new row, the updated total.

## Run

```
flutter devices
flutter test integration_test -d <device> --dart-define=QA_PASSWORD=...
flutter test integration_test/checkout_flow_test.dart -d <device>     # one file
```

- Stop any `pilot` session first: both install the same app on the device.
- Each file is a separate build and install. Keep related journeys in one file.
- Prefer an emulator or simulator for unattended runs. On macOS desktop the
  test hangs if the app's window is covered, because a hidden window is not
  drawn.
- The first run on a device builds the app; allow several minutes.

## When a flow fails

| Symptom | Cause and fix |
|---|---|
| Hangs with no output on desktop | The window is hidden. Bring it to the front or use an emulator. |
| `Timed out waiting for` a widget you can see | The finder is wrong, not the wait: take a pilot snapshot at that step and compare text, key and route. |
| Passes alone, fails in a suite | State left by an earlier test: stored login, cached data. Reset it. |
| Fails only on a slow device or CI | A fixed wait somewhere. Replace it with `pumpUntilFound` and raise its timeout. |
| `tap() ... would not hit test` | Covered or off screen: rule 3. |
| A system permission dialog blocks the flow | Grant it before launch with the device controls; the test cannot tap native UI. |
| Works in debug, the release build misbehaves | Out of reach of this test: list it as a manual check. |

To debug a failure, reproduce the journey step by step with pilot up to the
failing step: its snapshot shows what is really on screen, and it prints any
exception the app threw on the way.
