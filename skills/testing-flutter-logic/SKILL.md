---
name: testing-flutter-logic
description: Use when writing or fixing unit tests for Flutter or Dart logic - a Bloc, Cubit, Riverpod notifier, Provider or ChangeNotifier, GetX controller, MobX store, Redux reducer, repository, use case, model, validator or calculation - or when asked whether a piece of logic is correct, handles its edge cases, or is covered by tests.
---

# Testing Flutter Logic

## Overview

Logic tests are the exact, cheap layer: milliseconds each, no device, no
widgets. Whatever the state management library, the thing under test is a
plain Dart object. Build it with fakes, call it, assert what it reports.

**Core rule: a test must be able to fail.** Before trusting a new test, break
the code it covers (flip a comparison, return early) and watch the test go
red. A test that stays green proves nothing; fix the test.

**When a test you believe is right fails, the code may be wrong.** Read the
code again before touching the test. A real defect is a finding to report, with
file and line. Never bend an assertion to match what the code happens to do.

## The cases to write

For every unit, write down which of these exist, then write one test for each:

| Case | Example |
|---|---|
| The normal path, with realistic values | sign in with a valid account |
| Each boundary of each rule: just under, exactly on | discount at 99.99 and at 100.00 |
| Empty, one, many | cart with 0, 1, 2 of the same product |
| Each way a dependency can fail | rejected credentials; an unexpected exception; a timeout |
| Every state the unit passes through, in order | `signingIn` then `signedIn` |
| The same call again while the first is running | a double tap on Sign in |
| Recovery after a failure | the old error is gone after a successful retry |
| Input the UI lets through | spaces around an email, an empty string |

The "unexpected exception" row finds the most bugs: code that catches only the
error it expects leaves the app stuck in its loading state for ever.

## Pattern

Replace what the unit depends on with a small hand-written stub that the test
controls and that records how it was called. Collect every state the unit
announces, then assert the whole sequence.

```dart
class StubAuth implements AuthRepository {
  StubAuth(this.answer);
  final Future<User> Function(String email, String password) answer;
  final calls = <({String email, String password})>[];

  @override
  Future<User> signIn(String email, String password) {
    calls.add((email: email, password: password));
    return answer(email, password);
  }
}

test('a rejected sign-in ends signed out, with the reason', () async {
  final controller = AuthController(
    StubAuth((_, _) async => throw const AuthException('Invalid credentials')),
  );
  final seen = <AuthStatus>[];
  controller.addListener(() => seen.add(controller.status));

  await controller.signIn('ada@example.com', 'wrong');

  expect(seen, [AuthStatus.signingIn, AuthStatus.signedOut]);
  expect(controller.error, 'Invalid credentials');
});

test('a second tap while signing in does not call the backend again', () async {
  final answer = Completer<User>();          // holds the first call open
  final auth = StubAuth((_, _) => answer.future);
  final controller = AuthController(auth);

  final first = controller.signIn('ada@example.com', 'secret');
  await controller.signIn('ada@example.com', 'secret');
  expect(auth.calls, hasLength(1));

  answer.complete(const User('ada@example.com'));
  await first;
});
```

A `Completer` is how to test the state *during* an async call. Never use a
delay for that.

## The same pattern in each library

The shape never changes: construct with fakes, act, assert the states. Only
the way to observe states differs.

| Library | Observe states by | Give the unit its fakes by |
|---|---|---|
| ChangeNotifier, ValueNotifier | `addListener`, then read the fields | constructor arguments |
| Bloc, Cubit | `expectLater(bloc.stream, emitsInOrder([...]))` set up **before** `add` or the method call; `await bloc.close()` | constructor arguments |
| Riverpod | a `ProviderContainer` with `overrides`, `container.listen` to collect, `container.read` to act; dispose it in `addTearDown` | provider overrides |
| GetX | read the `.obs` values of a controller you construct directly | constructor arguments, or `Get.put` and `Get.reset()` in `tearDown` |
| MobX, signals | read the observables after each action | constructor arguments |
| Redux | call the reducer: `reducer(state, action)` is a pure function | none needed |

Check the version in `pubspec.lock` and that version's API before writing:
these packages rename things between major versions. Use the mocking package
the project already has; do not add one for a stub this small.

If the unit cannot be constructed without a real network client, database or
`BuildContext`, that is the finding: report it, then ask before refactoring.
See **reviewing-flutter-architecture**.

## The data layer

Repositories and API clients are logic too. Run the real parsing and mapping
code against canned responses: a full payload, an optional field missing, a
`null` where a value was expected, a number sent as a string, an empty list,
an error status, a timeout. Replace the HTTP client or database at the lowest
seam the project's package offers, so that everything above it is real. Assert
what the repository returns or throws, because that is what the rest of the
app has to handle.

## Things that make logic tests lie

| Problem | Fix |
|---|---|
| `DateTime.now()`, `Random()`, or a timer inside the unit | Pass a clock or generator in; the test passes a fixed one |
| Money in `double` | Integers in the smallest unit; assert exact values |
| State shared between tests through a singleton or `static` | Create everything inside the test or `setUp` |
| A mock that returns whatever makes the test pass | A stub with real behaviour; assert on results, not on call counts alone |
| Asserting only the final state | Assert the whole sequence: a missing `loading` state is a UI bug |
| `await Future.delayed` to "let it finish" | Await the call itself, or complete a `Completer` |

## Run and measure

```
flutter test test/cart_test.dart          # one file while writing
flutter test --coverage                   # everything, writes coverage/lcov.info
```

Coverage by module, including files no test ever loads, comes from the
architecture skill's checker, which sits next to this skill:
`dart <this skill's base directory>/../reviewing-flutter-architecture/scripts/arch_check.dart`.
Coverage shows what never ran. It cannot show that what ran was checked, so a
covered line still needs an assertion that would fail if the line were wrong.
