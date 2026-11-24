import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:qa_demo/domain/auth_repository.dart';
import 'package:qa_demo/presentation/controllers.dart';

import 'support/stub_auth.dart';

void main() {
  /// Every status the controller announces to its listeners, in order.
  List<AuthStatus> statusesOf(AuthController controller) {
    final seen = <AuthStatus>[];
    controller.addListener(() => seen.add(controller.status));
    return seen;
  }

  test('signs in through signingIn, with the email trimmed', () async {
    final auth = StubAuth((email, _) async => User(email));
    final controller = AuthController(auth);
    final seen = statusesOf(controller);

    await controller.signIn('  ada@example.com ', 'secret');

    expect(seen, [AuthStatus.signingIn, AuthStatus.signedIn]);
    expect(controller.user?.email, 'ada@example.com');
    expect(auth.calls.single.email, 'ada@example.com');
    expect(controller.error, isNull);
  });

  test('a rejected sign-in ends signed out, with the reason', () async {
    final controller = AuthController(
      StubAuth(
        (_, _) async => throw const AuthException('Invalid credentials'),
      ),
    );
    final seen = statusesOf(controller);

    await controller.signIn('ada@example.com', 'wrong');

    expect(seen, [AuthStatus.signingIn, AuthStatus.signedOut]);
    expect(controller.error, 'Invalid credentials');
    expect(controller.user, isNull);
  });

  test(
    'a failure that is not about credentials still ends the spinner',
    () async {
      final controller = AuthController(
        StubAuth((_, _) async => throw const SocketException('offline')),
      );

      await controller.signIn('ada@example.com', 'secret');

      expect(controller.status, AuthStatus.signedOut);
      expect(controller.error, isNotNull);
    },
  );

  test(
    'a second tap while signing in does not call the backend again',
    () async {
      final answer = Completer<User>();
      final auth = StubAuth((_, _) => answer.future);
      final controller = AuthController(auth);

      final first = controller.signIn('ada@example.com', 'secret');
      await controller.signIn('ada@example.com', 'secret');
      expect(auth.calls, hasLength(1));

      answer.complete(const User('ada@example.com'));
      await first;
      expect(controller.status, AuthStatus.signedIn);
    },
  );

  test('a retry clears the previous error', () async {
    var attempts = 0;
    final controller = AuthController(
      StubAuth((email, _) async {
        if (attempts++ == 0) throw const AuthException('Invalid credentials');
        return User(email);
      }),
    );

    await controller.signIn('ada@example.com', 'wrong');
    await controller.signIn('ada@example.com', 'secret');

    expect(controller.error, isNull);
    expect(controller.status, AuthStatus.signedIn);
  });

  test('signing out forgets the user', () async {
    final controller = AuthController(
      StubAuth((email, _) async => User(email)),
    );
    await controller.signIn('ada@example.com', 'secret');

    controller.signOut();

    expect(controller.status, AuthStatus.signedOut);
    expect(controller.user, isNull);
  });
}
