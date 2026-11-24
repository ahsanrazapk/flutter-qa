import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qa_demo/domain/auth_repository.dart';
import 'package:qa_demo/presentation/controllers.dart';
import 'package:qa_demo/presentation/settings_screen.dart';

import 'support/stub_auth.dart';

void main() {
  late AuthController auth;
  late ValueNotifier<bool> darkMode;

  /// One screen on its own, given the controllers it reads from the tree.
  Future<void> pumpSettings(WidgetTester tester) async {
    auth = AuthController(StubAuth((email, _) async => User(email)));
    darkMode = ValueNotifier(false);
    await auth.signIn('ada@example.com', 'secret');
    await tester.pumpWidget(
      AppScope(
        auth: auth,
        cart: CartController(),
        darkMode: darkMode,
        child: const MaterialApp(home: SettingsScreen()),
      ),
    );
  }

  // A Text with no text style above it is drawn in red with a yellow
  // underline. Nothing but a look at the screen, or this check, catches it.
  testWidgets('labels get the theme\'s text style', (tester) async {
    await pumpSettings(tester);

    final style = DefaultTextStyle.of(tester.element(find.text('Dark mode')));
    expect(style.style.debugLabel, isNot(contains('fallback style')));
  });

  testWidgets('the switch turns dark mode on', (tester) async {
    await pumpSettings(tester);
    expect(
      tester.widget<CupertinoSwitch>(find.byType(CupertinoSwitch)).value,
      isFalse,
    );

    await tester.tap(find.byKey(const Key('dark_mode')));
    await tester.pumpAndSettle();

    expect(darkMode.value, isTrue);
    expect(
      tester.widget<CupertinoSwitch>(find.byType(CupertinoSwitch)).value,
      isTrue,
    );
  });

  testWidgets('cancelling the dialog keeps the user signed in', (tester) async {
    await pumpSettings(tester);

    await tester.tap(find.text('Sign out'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(CupertinoDialogAction, 'Cancel'));
    await tester.pumpAndSettle();

    expect(auth.status, AuthStatus.signedIn);
    expect(find.byType(SettingsScreen), findsOneWidget);
  });

  testWidgets('confirming signs out and returns to the sign-in screen', (
    tester,
  ) async {
    await pumpSettings(tester);

    await tester.tap(find.text('Sign out'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(CupertinoDialogAction, 'Sign out'));
    await tester.pumpAndSettle();

    expect(auth.status, AuthStatus.signedOut);
    expect(find.byKey(const Key('sign_in')), findsOneWidget);
    expect(find.byType(SettingsScreen), findsNothing);
  });
}
