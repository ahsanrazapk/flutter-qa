import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qa_demo/domain/auth_repository.dart';
import 'package:qa_demo/main.dart';

import 'support/stub_auth.dart';

void main() {
  Future<void> fillIn(
    WidgetTester tester,
    String email,
    String password,
  ) async {
    await tester.enterText(find.byKey(const Key('email')), email);
    await tester.enterText(find.byKey(const Key('password')), password);
    await tester.tap(find.byKey(const Key('sign_in')));
    await tester.pump();
  }

  testWidgets('an invalid form never reaches the backend', (tester) async {
    final auth = StubAuth((email, _) async => User(email));
    await tester.pumpWidget(DemoApp(auth: auth));

    await fillIn(tester, 'not-an-email', '');

    expect(find.text('Enter a valid email'), findsOneWidget);
    expect(find.text('Enter your password'), findsOneWidget);
    expect(auth.calls, isEmpty);
  });

  testWidgets('shows a spinner while signing in, then the home screen', (
    tester,
  ) async {
    // A Completer holds the answer back so the loading state can be seen.
    final answer = Completer<User>();
    await tester.pumpWidget(DemoApp(auth: StubAuth((_, _) => answer.future)));

    await fillIn(tester, 'ada@example.com', 'secret');
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byKey(const Key('sign_in')), findsNothing);

    answer.complete(const User('ada@example.com'));
    await tester.pump(); // the controller reports the result
    // Home has an indicator that never stops, so pumpAndSettle would time
    // out. Pump past the route transition instead.
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Welcome, ada@example.com'), findsOneWidget);
  });

  testWidgets('a double tap on Sign in signs in once', (tester) async {
    final answer = Completer<User>();
    final auth = StubAuth((_, _) => answer.future);
    await tester.pumpWidget(DemoApp(auth: auth));
    await tester.enterText(find.byKey(const Key('email')), 'ada@example.com');
    await tester.enterText(find.byKey(const Key('password')), 'secret');

    // No pump between the taps: the second lands before the UI can react,
    // which is the strictest version of a fast double tap.
    await tester.tap(find.byKey(const Key('sign_in')));
    await tester.tap(find.byKey(const Key('sign_in')));
    await tester.pump();

    expect(auth.calls, hasLength(1));
    answer.complete(const User('ada@example.com'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Welcome, ada@example.com'), findsOneWidget);
  });

  testWidgets('shows why a sign-in was rejected and lets the user retry', (
    tester,
  ) async {
    await tester.pumpWidget(
      DemoApp(
        auth: StubAuth(
          (_, _) async => throw const AuthException('Invalid credentials'),
        ),
      ),
    );

    await fillIn(tester, 'ada@example.com', 'wrong');
    await tester.pump();

    expect(find.text('Invalid credentials'), findsOneWidget);
    expect(find.byKey(const Key('sign_in')), findsOneWidget);
  });

  testWidgets('meets the tap target, label and contrast guidelines', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      DemoApp(auth: StubAuth((email, _) async => User(email))),
    );

    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    await expectLater(tester, meetsGuideline(textContrastGuideline));
    semantics.dispose();
  });

  testWidgets('fits a small phone at the largest text size', (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await tester.pumpWidget(
      DemoApp(auth: StubAuth((email, _) async => User(email))),
    );
    await fillIn(tester, 'not-an-email', '');

    // An overflow is reported as an exception, which fails the test by itself.
    expect(find.text('Enter a valid email'), findsOneWidget);
  });
}
