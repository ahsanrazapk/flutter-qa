---
name: driving-flutter-apps
description: Use when asked to open, run, explore, click through or verify a running Flutter app on an emulator, simulator, device or desktop - checking that a screen or flow works, reproducing a bug, smoke-testing after a change, taking screenshots, or doing what Maestro or Appium would do. Also use when a Flutter test needs facts from the live screen, such as keys, widget types or source lines.
---

# Driving Flutter Apps

## Overview

`pilot` runs a Flutter app in debug mode with a small bridge inside it, then
reads the screen and acts on it like a user: real pointer events, real text
input. It needs only the Flutter SDK. Nothing is added to `pubspec.yaml`; its
files live in `.dart_tool/flutter_pilot/`, which every Flutter project ignores.

**Core rule: look, act, verify.** Never act on a screen you have not read, and
never report a step as working until `wait` or a snapshot shows its result.

`pilot` below is short for `dart <this skill's base directory>/scripts/pilot.dart`.
Write that out in every command: a shell variable holding the two words does
not run in zsh. Run it from the Flutter project root, or pass `--project DIR`.

## Quick reference

| Goal | Command |
|---|---|
| Launch the app | `pilot start -d <device>` (`flutter devices` lists them) |
| Launch a flavor or another main | `pilot start -d <device> --target lib/main_dev.dart -- --flavor dev` |
| Still building | `pilot ready` (repeat until it prints `ready`) |
| Read the screen | `pilot snapshot` |
| Read the screen and mark what a change built | `pilot snapshot --changed main` (any git branch or commit) |
| See the pixels | `pilot shot` then Read `.dart_tool/flutter_pilot/shot.png` |
| Screenshot with one element framed in red | `pilot shot bug.png --key pay`, `pilot shot bug.png 12`, `pilot shot bug.png --src lib/cart.dart:57` |
| Tap | `pilot tap 12`, `pilot tap --key sign_in`, `pilot tap --text "Save"` |
| Long press, double tap | `pilot tap 12 --long`, `pilot tap 12 --double` |
| Check a button survives a fast double tap | `pilot tap --key pay --double`, then verify it happened **once** |
| Type (replaces the content) | `pilot type "ada@example.com" --key email` |
| Type and press the keyboard's action key | `pilot type "shoes" --key search --submit` |
| Reach a row far down a list | `pilot scroll-to --text "Product 30"` (`--up` to go back) |
| Drag or flick | `pilot scroll --dy -300`, `pilot swipe --type PageView --dx -300` |
| Assert something appears / disappears | `pilot wait --text "Order placed"`, `pilot wait --text "Loading" --gone` |
| System back | `pilot back` |
| Apply a code change | `pilot reload` (state kept) or `pilot restart` (fresh start) |
| Replay a saved flow | `pilot run pilot/checkout.flow` |
| End the session | `pilot stop` |

Running `pilot` with no arguments prints every option.

A first build can take many minutes, on Android especially: `start` then says
`Not ready`, and `ready` keeps waiting. If either says `flutter run exited`,
the lines printed under it are the build or install error to fix.

## Reading a snapshot

```
screen 411x890  route /cart (MaterialPageRoute<void>)
[46] header "Cart"  <- Text lib/cart/cart_page.dart:21
[17] textfield "Coupon" = "SAVE10" (focused)  <- TextField key=coupon lib/cart/cart_page.dart:40
[20] button "Tea\n$4.50"  <- ListTile lib/cart/cart_page.dart:58
  [21] button tooltip "Remove Tea"  <- IconButton lib/cart/cart_page.dart:63
[30] button "Pay" (disabled)  <- FilledButton key=pay lib/cart/cart_page.dart:80
```

- `[n]` is a ref: `pilot tap 20`. Refs die when the screen changes; take a
  new snapshot instead of reusing old ones.
- After `<-` comes the widget your app's code created, its `Key`, and the
  source line. Open that line to learn what the element does before guessing.
- With `--changed <base>`, `*changed*` ends the line of every element built by
  code in `lib/` that differs from `<base>`, a changed wrapper's children
  included. Under the list come the changed lines that built no widget on
  this screen: another screen, a branch not taken, or logic. Reload first if
  the code was edited after the app started, or the lines will not match.
- The route line names the top route. A `DialogRoute` or `ModalBottomSheetRoute`
  there means an overlay is open and everything under it is unreachable.
- `(off screen)` rows exist but need scrolling. `scrolled 0 of 2084` on a
  scrollable means there is more below.
- Every action prints the snapshot that follows it, so one command is both the
  act and the look. For steps in a row whose result you already know, such as
  filling a form, add `--quiet` to all but the last: a snapshot of a list
  screen is several hundred tokens, the quiet `ok` line about fifteen.
- An action's first line names what it landed on:
  `ok: FilledButton key=pay lib/cart/cart_page.dart:80 at 205,640`. If that is
  not the widget you meant, the step did something else.
- `(nothing is on screen: the app is showing a blank page)` is a defect, most
  often a route popped once too often. Report it; `restart` to carry on.

**A snapshot cannot show how a screen looks.** Take `pilot shot` once on every
new screen and look at it: text drawn in red with a yellow underline (a `Text`
with no text style above it), clipped or overlapping text, wrong colours in
dark mode. None of these appear in a snapshot or throw an error.

## Choosing a target

1. **A ref**, while exploring: exact, no ambiguity.
2. **`--key`**, in anything you will replay: survives text and layout changes.
3. **`--text`** (the whole text), **`--contains`** (part of it), **`--tooltip`**,
   **`--label`** (a semantics label), when there is no key.
4. **`--type`**, for the only widget of its kind.
5. **`--at X,Y`**, for canvas-drawn UI (charts, games, custom painters). Take
   `pilot shot` first: image pixels are the same logical coordinates.
6. **`--src FILE:LINE`**, the widget created at that source line. An app error
   names the line; this turns it back into the widget on screen.

When several widgets match, pilot lists them top to bottom with their source
lines and stops. Pick with `--index N`; do not guess.

Finders wait up to `--timeout` seconds (default 10) for their widget, so do not
add sleeps. A widget that is covered or disabled is refused with the name of
what is on top of it: that is a finding about the app, not something to force.

## App errors are findings

Any exception the app throws while a command runs is printed after it:

```
! app error: A RenderFlex overflowed by 42 pixels on the bottom.  at lib/cart/cart_page.dart:57
```

Each is a defect to report with its file and line, even when the step itself
"worked". Pilot turns accessibility on, so assertion failures about semantics
also show up here: those are real bugs for screen reader users.

## Saved flows

A flow is a file of pilot commands, one per line, replayed in seconds against
the running session. It fails at the first step that fails **or** that makes
the app throw, and prints the screen and the path of a screenshot in which
the widget that step was aimed at is framed in red.

```
# pilot/checkout.flow
restart                                   # start from a known state
type "ada@example.com" --key email
type "${QA_PASSWORD}" --key password      # read from the environment
tap --key sign_in
wait --contains "Welcome"
scroll-to --text "Product 30"
tap --tooltip "Add Product 30"
wait --text "Total $348.75"
```

- Begin with `restart`. It resets Dart state only; stored data survives (see
  [device-controls.md](device-controls.md) to clear it). A flow that failed
  leaves the app where it stopped, and the next flow's `restart` brings it back.
- Never write a real password or token in a flow: use `${NAME}`.
- End each flow with a `wait` that proves the outcome.
- Keep flows in `pilot/` and commit them. They are for fast local checks; for
  CI, turn the journey into an `integration_test` with **testing-flutter-flows**.

## What pilot cannot do

| Limit | Do instead |
|---|---|
| Release or profile builds | Debug builds only. Test release builds by hand. |
| Native UI: permission prompts, system pickers, web views, maps, ads | Grant or avoid them with platform tools: [device-controls.md](device-controls.md). `flutter screenshot` shows them. |
| A widget with no semantics is missing from the snapshot | `pilot shot`, then `--at`. Report the missing label as an accessibility finding. |
| `int` or object keys | `--key` matches `Key('x')` / `ValueKey('x')` only. Use text, type or a ref. |
| Flutter web | Not supported. Use a mobile or desktop device. |
| `start` and `reload` on Windows | `start` prints the `flutter run` line to launch yourself; use stop and start instead of reload. |

## Common mistakes

| Mistake | Fix |
|---|---|
| Reporting "works" after a tap printed `ok` | `ok` means the tap was sent. Prove the result with `wait` or the snapshot. |
| Reusing a ref after the screen changed | Take a new snapshot. |
| Adding a sleep before a step | Finders already wait. For a slow backend raise `--timeout`. |
| Forcing a covered widget with `--at` | Close the dialog or scroll first; if a user could not reach it either, report it. |
| Editing code and testing the old build | `pilot reload` after every edit; `restart` when state looks stale. |
| Leaving the app running | `pilot stop` when finished. |
| Checking a snackbar or toast several commands later | It is gone after a few seconds. `wait` for it in the very next command. |
| Testing a double tap with two `tap` commands | They run seconds apart. `--double` sends both taps 40 ms apart, as a fast finger does. |
| Ignoring `(the screen is still animating)` | Only a note: something animates for ever. `wait` for what you expect. |
