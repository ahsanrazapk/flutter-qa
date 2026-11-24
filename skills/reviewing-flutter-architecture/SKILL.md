---
name: reviewing-flutter-architecture
description: Use when asked to review, audit or improve a Flutter app's architecture, system design, layering, state management, dependency injection, error handling or testability - or before a large refactor, when adding a feature to an unfamiliar Flutter codebase, or when bugs keep coming from tangled state or duplicated logic.
---

# Reviewing Flutter Architecture

## Overview

An architecture review answers one question: **can this code be changed and
tested without breaking something far away?** Judge the code against the
structure the project itself chose, then against what its bugs and tests show.
No pattern is correct by name: a small app with `setState` can be sound and a
"clean architecture" app can be tangled.

**Core rule: every finding carries evidence** (file and line, or a command and
its output) and a consequence someone would care about. "Could be cleaner" is
not a finding.

## 1. Measure before reading

Run these from the project root and keep the output:

```
flutter analyze
dart <this skill's base directory>/scripts/arch_check.dart
flutter test --coverage --reporter failures-only   # then run arch_check again for coverage by module
```

`arch_check` reports:

| Section | Meaning |
|---|---|
| Boundary violations | an import crossing a layer the wrong way, with file and line |
| Import cycles between modules | features or layers that depend on each other, with the imports that close the loop |
| Files over 400 lines | where responsibilities have piled up |
| Line coverage by module | including files no test ever loads, which a plain coverage report hides |

Its default rules (`domain` imports neither `data`, `presentation`, `ui` nor
Flutter's widget libraries; `data` does not import `presentation`) fit a
layered or feature-first layout. For any other layout, state the project's own
rules: `--forbid FROM=TO`, repeatable, where `TO` is a folder name or a URI
prefix such as `package:dio/`. If the project has no layers at all, say so and
skip that section instead of inventing one.

It exits 1 on a violation or cycle, so it can gate CI, optionally with
`--min-coverage N`.

## 2. Find the intended design

Read, in this order: any architecture notes in the repo (README, `docs/`,
CLAUDE.md), the folder layout under `lib/`, `pubspec.yaml` (which state
management, routing, DI and networking packages), and `main.dart` (how the app
is wired). Write down in two or three sentences what the design is meant to
be. Review against that.

## 3. Read for these, with evidence

**State**

| Look for | Why it matters |
|---|---|
| Business rules inside `build` methods or widget callbacks | cannot be unit tested; duplicated across screens |
| The same fact stored in two places (a controller and a widget's field) | they drift apart: stale UI |
| State mutated in place, then notified | listeners comparing old and new see no change |
| A state holder that takes `BuildContext`, or navigates, or shows dialogs | logic tied to the widget tree; untestable without it |
| No loading or error state for an async call | a spinner for ever, or a silent failure |
| Async work with no guard against running twice | double submissions |
| Controllers, streams, timers, focus nodes never disposed or cancelled | leaks; callbacks firing on dead widgets |
| `setState` or `context` used after an `await` without checking `mounted` | crashes after navigating away |
| One app-wide state object that everything listens to | every change rebuilds everything |

**Boundaries**

| Look for | Why it matters |
|---|---|
| Widgets calling HTTP, a database or a plugin directly | cannot be tested without the real thing |
| JSON or database rows used as the app's model everywhere | a backend change breaks every screen |
| Concrete classes created where they are used (`ApiClient()` inside a widget) | nothing can be replaced in a test |
| A dependency reached through a global or a service locator from deep inside logic | hidden inputs; tests interfere with each other |
| A feature importing another feature's internals | the cycle `arch_check` reports |

**Failure**

| Look for | Why it matters |
|---|---|
| `catch (e) {}` or a catch that only prints | failures vanish; the user sees nothing |
| Catching only the expected exception type around an async call | any other error leaves the UI stuck |
| No timeout on network calls | the app waits for ever on a bad connection |
| Errors shown as raw exception text | leaks internals; useless to the user |
| Secrets, tokens or environment URLs in source | they ship in the app |

Use the analyzer for what it can prove. These lints from Dart's own lint set
catch several rows above mechanically; note which are off in
`analysis_options.yaml` and recommend turning them on:
`use_build_context_synchronously`, `cancel_subscriptions`, `close_sinks`,
`unawaited_futures`, `discarded_futures`, `avoid_dynamic_calls`.

## 4. Check the claim with a test

The sharpest evidence that a design is hard to test is trying to test it. For
each serious finding, name the unit test that cannot currently be written and
why (for example: "`CartPage` builds its own `ApiClient`, so the empty-cart
state cannot be shown without a server"). If it *can* be written, write it
with **testing-flutter-logic**: a failing test is the strongest finding of all.

## 5. Report

Order by consequence, not by file. For each finding:

```
[High] Sign-in can hang for ever
Where:   lib/presentation/controllers.dart:21-30
What:    signIn catches AuthException only.
Effect:  any other failure (no network) leaves status at signingIn; the
         spinner never ends and the button never returns.
Proof:   test "a failure that is not about credentials still ends the spinner"
         fails: expected signedOut, got signingIn.
Fix:     catch everything else, set an error, return to signedOut.
```

Severity is about the user and the next developer: **High** loses data, money
or the ability to proceed; **Medium** makes a class of bug likely or a class
of test impossible; **Low** costs time.

End with what is sound and should be kept, and with what was not examined.

## Common mistakes

| Mistake | Instead |
|---|---|
| Recommending a rewrite to a favourite pattern | Name the specific harm and the smallest change that removes it |
| Reporting `arch_check` output as the review | It only sees imports and sizes. Section 3 needs reading. |
| Findings with no file and line | Drop them or find the evidence |
| Refactoring while reviewing | Report first; change only what was asked for |
| Calling low coverage a design flaw | Ask why it is low: untestable code is the flaw, missing tests are a task |
