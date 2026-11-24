// Self-tests for the plugin's in-app bridge, run against the example app.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qa_demo/data/fake_auth_repository.dart';
import 'package:qa_demo/main.dart';

import '../../../skills/driving-flutter-apps/scripts/pilot_bridge.dart';

typedef Reply = Map<String, Object?>;

void main() {
  final root = Directory.current.uri.toString();

  /// A widget test that releases what the bridge holds before the framework
  /// checks for leftovers.
  void pilotTest(String name, Future<void> Function(WidgetTester) body) {
    testWidgets(name, (tester) async {
      try {
        await body(tester);
      } finally {
        debugResetPilot();
      }
    });
  }

  Future<Reply> send(
    WidgetTester tester,
    String cmd, [
    Map<String, String> args = const {},
  ]) => pilotCommand({'cmd': cmd, 'root': root, ...args}, controller: tester);

  Future<Reply> ok(
    WidgetTester tester,
    String cmd, [
    Map<String, String> args = const {},
  ]) async {
    final reply = await send(tester, cmd, args);
    expect(reply['ok'], isTrue, reason: '${reply['error']}');
    return reply;
  }

  Future<String> error(
    WidgetTester tester,
    String cmd, [
    Map<String, String> args = const {},
  ]) async {
    final reply = await send(tester, cmd, args);
    expect(reply['ok'], isFalse, reason: '$cmd $args should have failed');
    return reply['error']! as String;
  }

  List<Reply> nodes(Reply snapshot) =>
      (snapshot['nodes']! as List).cast<Reply>();

  Reply nodeLabelled(Reply snapshot, String label, {String? flag}) =>
      nodes(snapshot).firstWhere(
        (node) =>
            node['label'] == label &&
            (flag == null ||
                (node['flags'] as List? ?? const []).contains(flag)),
      );

  Future<void> signIn(WidgetTester tester) async {
    await tester.pumpWidget(
      const DemoApp(auth: FakeAuthRepository(delay: Duration.zero)),
    );
    await ok(tester, 'type', {'key': 'email', 'value': 'ada@example.com'});
    await ok(tester, 'type', {'key': 'password', 'value': 'secret'});
    final tap = await ok(tester, 'tap', {'key': 'sign_in'});
    // The reply names what was tapped, so a wrong target shows at once.
    expect(tap['hit'], containsPair('widget', 'FilledButton'));
    expect(tap['hit'], containsPair('key', 'sign_in'));
    expect(find.text('Welcome, ada@example.com'), findsOneWidget);
  }

  pilotTest('snapshot describes what is on screen and where it comes from', (
    tester,
  ) async {
    await tester.pumpWidget(const DemoApp(auth: FakeAuthRepository()));
    final snapshot = await ok(tester, 'snapshot');

    expect(snapshot['size'], [800, 600]);
    expect(snapshot['route'], contains('MaterialPageRoute'));

    final email = nodeLabelled(snapshot, 'Email');
    expect(email['flags'], contains('isTextField'));
    expect(email['widget'], 'TextFormField');
    expect(email['key'], 'email');
    expect(email['src'], startsWith('lib/presentation/login_screen.dart:'));

    final button = nodeLabelled(snapshot, 'Sign in', flag: 'isButton');
    expect(button['actions'], contains('tap'));
    expect(button['key'], 'sign_in');
  });

  pilotTest('types into fields and taps through to the next screen', (
    tester,
  ) async {
    await signIn(tester);
    final found = await ok(tester, 'find', {'contains': 'Welcome'});
    expect(found['count'], 1);
  });

  pilotTest('a ref from a snapshot taps the right place', (tester) async {
    await tester.pumpWidget(
      const DemoApp(auth: FakeAuthRepository(delay: Duration.zero)),
    );
    final snapshot = await ok(tester, 'snapshot');
    final button = nodeLabelled(snapshot, 'Sign in', flag: 'isButton');
    await ok(tester, 'tap', {'ref': '${button['ref']}'});
    // The form validated, which only a tap on the button does.
    expect(find.text('Enter a valid email'), findsOneWidget);
  });

  pilotTest('an ambiguous finder lists its matches instead of guessing', (
    tester,
  ) async {
    await tester.pumpWidget(const DemoApp(auth: FakeAuthRepository()));
    final message = await error(tester, 'tap', {'text': 'Sign in'});
    expect(message, contains('2 widgets match'));
    expect(message, contains('--index 1'));

    await ok(tester, 'tap', {'text': 'Sign in', 'index': '1'});
    expect(find.text('Enter a valid email'), findsOneWidget);
  });

  pilotTest('submit sends the keyboard action', (tester) async {
    await tester.pumpWidget(const DemoApp(auth: FakeAuthRepository()));
    await ok(tester, 'type', {
      'key': 'password',
      'value': 'secret',
      'submit': 'true',
    });
    expect(find.text('Enter a valid email'), findsOneWidget);
  });

  pilotTest('reports a wrong password without hanging on the spinner', (
    tester,
  ) async {
    await tester.pumpWidget(
      const DemoApp(auth: FakeAuthRepository(delay: Duration.zero)),
    );
    await ok(tester, 'type', {'key': 'email', 'value': 'ada@example.com'});
    await ok(tester, 'type', {'key': 'password', 'value': 'wrong'});
    await ok(tester, 'tap', {'key': 'sign_in'});
    expect(
      (await ok(tester, 'find', {'text': 'Invalid credentials'}))['count'],
      1,
    );
  });

  pilotTest('scroll-to reaches rows a lazy list has not built yet', (
    tester,
  ) async {
    await signIn(tester);
    expect(find.text('Product 39'), findsNothing);

    await ok(tester, 'scrollTo', {'text': 'Product 39'});
    expect(find.text('Product 39').hitTestable(), findsOneWidget);

    await ok(tester, 'scrollTo', {'text': 'Product 0', 'up': 'true'});
    expect(find.text('Product 0').hitTestable(), findsOneWidget);

    final message = await error(tester, 'scrollTo', {'text': 'Product 99'});
    expect(message, contains('without finding'));
  });

  pilotTest('refuses to tap something a dialog covers', (tester) async {
    await signIn(tester);
    await ok(tester, 'tap', {'tooltip': 'Add Product 0'});
    await ok(tester, 'tap', {'key': 'checkout'});
    expect(find.text('Place order?'), findsOneWidget);

    final message = await error(tester, 'tap', {
      'text': 'Product 0',
      'index': '0',
    });
    expect(message, contains('cannot be tapped'));

    await ok(tester, 'tap', {'text': 'Place order'});
    expect((await ok(tester, 'find', {'text': 'Order placed'}))['count'], 1);
  });

  pilotTest('back pops a route and says so when there is none', (tester) async {
    await signIn(tester);
    await ok(tester, 'tap', {'text': 'Product 1'});
    expect(find.text('Your rating: 0'), findsOneWidget);

    await ok(tester, 'back');
    expect(find.text('Your rating: 0'), findsNothing);

    expect(await error(tester, 'back'), contains('nothing to go back to'));
  });

  pilotTest('drives canvas-drawn widgets by coordinates', (tester) async {
    await signIn(tester);
    await ok(tester, 'tap', {'text': 'Product 1'});

    final rating = nodeLabelled(await ok(tester, 'snapshot'), 'Rating');
    expect(rating['value'], '0 of 5');
    expect(rating['actions'], contains('increase'));

    // The fourth of five stars: 70% of the way across the widget.
    final [left, top, right, bottom] = (rating['rect']! as List).cast<int>();
    final x = left + (right - left) * 0.7;
    await ok(tester, 'tap', {'at': '$x,${(top + bottom) / 2}'});
    expect(find.text('Your rating: 4'), findsOneWidget);
  });

  pilotTest('drives Cupertino widgets', (tester) async {
    await signIn(tester);
    await ok(tester, 'tap', {'tooltip': 'Settings'});
    expect((await ok(tester, 'snapshot'))['route'], contains('Cupertino'));

    await ok(tester, 'tap', {'key': 'dark_mode'});
    expect(
      Theme.of(tester.element(find.text('Dark mode'))).brightness,
      Brightness.dark,
    );

    await ok(tester, 'type', {'key': 'display_name', 'value': 'Ada'});
    expect(find.text('Ada'), findsOneWidget);

    await ok(tester, 'tap', {'text': 'Sign out'});
    expect(find.text('Sign out?'), findsOneWidget);
    await ok(tester, 'tap', {'text': 'Cancel'});
    expect(find.text('Sign out?'), findsNothing);
  });

  pilotTest('long press and double tap', (tester) async {
    final seen = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: GestureDetector(
            onLongPress: () => seen.add('long'),
            onDoubleTap: () => seen.add('double'),
            child: const Text('Target'),
          ),
        ),
      ),
    );
    await ok(tester, 'tap', {'text': 'Target', 'mode': 'long'});
    await ok(tester, 'tap', {'text': 'Target', 'mode': 'double'});
    expect(seen, ['long', 'double']);
  });

  pilotTest('a double tap reaches a handler that has no guard twice', (
    tester,
  ) async {
    var orders = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: FilledButton(
            // No loading state and no guard: the bug --double exists to find.
            onPressed: () async {
              await Future<void>.delayed(const Duration(milliseconds: 300));
              orders++;
            },
            child: const Text('Place order'),
          ),
        ),
      ),
    );
    await ok(tester, 'tap', {'text': 'Place order', 'mode': 'double'});
    expect(orders, 2);
  });

  pilotTest('swipe and scroll move a list', (tester) async {
    await signIn(tester);
    await ok(tester, 'scroll', {'type': 'ListView', 'dy': '-300'});
    expect(find.text('Product 0').hitTestable(), findsNothing);
    await ok(tester, 'swipe', {'type': 'ListView', 'dy': '300'});
    expect(find.text('Product 0').hitTestable(), findsOneWidget);
  });

  pilotTest('maps a list row to its own widget, not to the list', (
    tester,
  ) async {
    await signIn(tester);
    final row = nodeLabelled(
      await ok(tester, 'snapshot'),
      'Product 0\n\$12.50',
    );
    expect(row['widget'], 'ListTile');
    expect(row['src'], startsWith('lib/presentation/home_screen.dart:'));
  });

  test('locates an app error by the blamed widget or the first app frame', () {
    expect(
      errorLocation(
        'A RenderFlex overflowed by 42 pixels on the bottom.\n'
            'The relevant error-causing widget was:\n'
            '  Column Column:file:///app/lib/cart.dart:57:16\n'
            'stack: (file:///app/.dart_tool/flutter_pilot/pilot_bridge.dart:9:1)',
        '',
      ),
      'file:///app/lib/cart.dart:57',
    );
    expect(
      errorLocation(
        'Bad state: boom',
        '#0 Cart.pay (package:shop/domain/cart.dart:12:5)\n'
            '#1 _InkResponseState.handleTap (package:flutter/src/material/ink_well.dart:1:1)\n'
            '#2 _Pilot._tap (file:///app/.dart_tool/flutter_pilot/pilot_bridge.dart:561:7)',
      ),
      'package:shop/domain/cart.dart:12',
    );
    expect(errorLocation('boom', '#0 main (dart:core/x.dart:1:1)'), isNull);
  });

  test('survives an app handler that calls the previous handler', () {
    final original = FlutterError.onError;
    addTearDown(() => FlutterError.onError = original);
    final presented = <String>[];
    FlutterError.onError = (details) => presented.add('first');

    debugHookPilotErrors(); // what installPilot does before main()
    // What crash reporters do in main(): wrap whatever was there.
    final previous = FlutterError.onError;
    FlutterError.onError = (details) {
      presented.add('app');
      previous?.call(details);
    };
    debugHookPilotErrors(); // what every command does

    FlutterError.reportError(
      FlutterErrorDetails(exception: StateError('boom')),
    );

    // Recorded once, each handler ran once, and nothing looped.
    expect(debugDrainPilotErrors(), [contains('boom')]);
    expect(presented, ['app', 'first']);
  });

  pilotTest('explains what went wrong', (tester) async {
    await tester.pumpWidget(const DemoApp(auth: FakeAuthRepository()));
    expect(
      await error(tester, 'tap', {'ref': '99999'}),
      contains('new snapshot'),
    );
    expect(
      await error(tester, 'tap', {'text': 'Nope'}),
      contains('Nothing on screen'),
    );
    expect(
      await error(tester, 'type', {'value': 'x'}),
      contains('No text field'),
    );
    expect(
      await error(tester, 'type', {'key': 'sign_in', 'value': 'x'}),
      contains('not a text field'),
    );
    expect(await error(tester, 'fly'), contains('Unknown pilot command'));
  });
}
