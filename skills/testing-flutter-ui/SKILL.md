---
name: testing-flutter-ui
description: Use when writing or fixing Flutter widget tests or golden tests - a screen, form, dialog, list, navigation step, Material or Cupertino component, custom-painted or third-party widget - or when a widget test fails with pumpAndSettle timed out, finds no widgets or too many, a RenderFlex overflow, or a pending timer. Also use when checking accessibility, text scaling, dark mode or small screens.
---

# Testing Flutter UI

## Overview

A widget test builds one screen or component in memory, with fake
dependencies, and drives it in fake time. It is where every visible state of
the UI gets checked: fast enough to cover them all, exact enough to trust.

**Core rule: test what the user sees and does**, not how the widget is built.
Find by key, label or text; assert on visible results.

## The states to cover

For each screen, list which of these it has, then write a test for each:

| State | How to produce it |
|---|---|
| Loading | a stub whose answer is a `Completer` you have not completed |
| Data | complete it with a realistic value |
| Empty | complete it with an empty list |
| Error, and retry | make the stub throw; then make it succeed |
| Invalid input | submit the form empty and with a bad value |
| Disabled or in progress | the action button is gone or inactive while busy |
| Double tap | `tester.tap` the button twice with no `pump` between, then assert the dependency was called once |
| Small screen, large text | see "Sizes and themes" below |
| Accessible | see "Accessibility" below |

## Pumping: the part that goes wrong

Fake time only moves when the test moves it.

| Call | Does |
|---|---|
| `await tester.pump()` | builds one frame: use after anything that changes state |
| `await tester.pump(duration)` | moves the clock, then builds one frame: finishes a timer or a transition |
| `await tester.pumpAndSettle()` | pumps until nothing is animating |

`pumpAndSettle` **times out on any screen that animates for ever**: a progress
indicator, a shimmer, a looping animation. Loading states always have one. On
those screens pump a duration instead:

```dart
testWidgets('shows a spinner while signing in, then the home screen', (tester) async {
  final answer = Completer<User>();
  await tester.pumpWidget(DemoApp(auth: StubAuth((_, _) => answer.future)));

  await tester.enterText(find.byKey(const Key('email')), 'ada@example.com');
  await tester.enterText(find.byKey(const Key('password')), 'secret');
  await tester.tap(find.byKey(const Key('sign_in')));
  await tester.pump();
  expect(find.byType(CircularProgressIndicator), findsOneWidget);

  answer.complete(const User('ada@example.com'));
  await tester.pump();                            // the result arrives
  await tester.pump(const Duration(seconds: 1));  // the route transition ends
  expect(find.text('Welcome, ada@example.com'), findsOneWidget);
});
```

Give the widget its dependencies the way the app does (constructor, provider
override, inherited widget), with the stubs from **testing-flutter-logic**.
To test one screen alone, wrap it in what it reads from the tree plus a
`MaterialApp` or `CupertinoApp`.

## Finders

| Prefer | For |
|---|---|
| `find.byKey(const Key('sign_in'))` | anything a test acts on; add the key to the widget |
| `find.byTooltip`, `find.bySemanticsLabel` | icon buttons and images |
| `find.text`, `find.textContaining` | asserting what is shown |
| `find.widgetWithText(CupertinoDialogAction, 'Cancel')` | one of several widgets with the same text |
| `find.descendant(of:, matching:)` | a widget inside a particular row or dialog |
| `find.byType` | the only widget of its kind |

Material and Cupertino widgets are tested the same way; only the types differ
(`CupertinoSwitch`, `CupertinoDialogAction`, `CupertinoTextField`).

To get keys, types and source lines from the running app instead of reading
code, use **driving-flutter-apps**: its snapshot prints them per element.

## Custom-painted and third-party widgets

Nothing inside a `CustomPaint`, a chart or a game canvas can be found. Test it
three ways:

```dart
// 1. Behaviour: tap where the thing is drawn.
final left = tester.getTopLeft(find.byType(RatingStars));
await tester.tapAt(left + const Offset(RatingStars.starSize * 3.5, 20));
expect(changes, [4]);

// 2. Meaning: what a screen reader is told.
final semantics = tester.ensureSemantics();
expect(
  tester.getSemantics(find.byType(RatingStars)),
  isSemantics(label: 'Rating', value: '3 of 5', hasIncreaseAction: true),
);
semantics.dispose();

// 3. Appearance: compare pixels with a recorded image.
await expectLater(
  find.byType(RatingStars),
  matchesGoldenFile('goldens/rating_3_of_5.png'),
);
```

Golden rules: record with `flutter test --update-goldens`, **look at the image
before committing it**, and tag golden tests (`tags: 'golden'`, declared in
`dart_test.yaml`) because pixels only match on the platform that recorded
them. Run them on one platform: `flutter test --tags golden`.

For a widget from a package, test your use of it (what you pass in, what you
do with its callbacks), not the package itself.

## Accessibility

```dart
testWidgets('meets the tap target, label and contrast guidelines', (tester) async {
  final semantics = tester.ensureSemantics();
  await tester.pumpWidget(const MyScreen());

  await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
  await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
  await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
  await expectLater(tester, meetsGuideline(textContrastGuideline));
  semantics.dispose();
});
```

One such test per screen. A failure names the widget: fix the widget.

## Sizes and themes

```dart
tester.view.physicalSize = const Size(320, 568);       // a small phone
tester.view.devicePixelRatio = 1;
addTearDown(tester.view.reset);
tester.platformDispatcher.textScaleFactorTestValue = 2; // largest text
addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
```

An overflow is thrown as an exception, so a test at this size fails by itself
if the layout breaks. Repeat the screen's main test in dark mode by pumping it
with `themeMode: ThemeMode.dark`.

## What a passing test cannot see

A screen can pass every test and still look wrong. The commonest case: a
`Text` with no Material or Cupertino text style above it (a Cupertino page
inside a `MaterialApp`, a bare overlay) is drawn in red with a yellow
underline. Check for it directly, and look at each screen once with a golden
or a screenshot from **driving-flutter-apps**:

```dart
final style = DefaultTextStyle.of(tester.element(find.text('Dark mode')));
expect(style.style.debugLabel, isNot(contains('fallback style')));
```

## When a widget test fails

| Message | Cause and fix |
|---|---|
| `pumpAndSettle timed out` | Something animates for ever. Pump a duration instead. |
| `Found 0 widgets` | Not built yet: pump. Or off screen in a lazy list: `tester.scrollUntilVisible`. Or in a route that is not on top. |
| `Found 2 widgets` / too many elements | Same text twice (title and button). Use a key or `find.descendant`. |
| `Bad state: Too many elements` from `scrollUntilVisible` | Several scrollables are on screen (a text field is one). Pass `scrollable:` with the list's own `Scrollable`. |
| `A SemanticsNode with action ... needs to be annotated` | The widget's `Semantics` is incomplete: a real accessibility bug. Fix the widget. |
| The next screen never appears with a fake that waits | The fake uses a timer: `pump` its delay before pumping the transition. |
| `A RenderFlex overflowed` | A real layout bug at this size. Fix the layout, not the test size. |
| `A Timer is still pending` | The code started a timer the test never ran out: `pump` past it, or the widget does not cancel it in `dispose` (a bug). |
| `setState() called after dispose()` | The widget does not check `mounted` after an `await` (a bug). |
| `MissingPluginException` | A plugin has no native side in tests. Put the plugin behind an interface and stub it. |
| `tap() ... would not hit test` | The widget is covered or off screen. `tester.ensureVisible` first, or close what covers it. |
| A network image fails to load | Tests have no network. Inject the image provider or stub the client. |
| Golden differs by a few pixels on another machine | Goldens are per platform. Run them where they were recorded. |

Run one file while writing: `flutter test test/login_screen_test.dart`. Add
`--name "spinner"` for one test.
