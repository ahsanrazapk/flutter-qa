import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:qa_demo/main.dart' as app;

// Run on a device with:
//   flutter test integration_test -d <device> --dart-define=QA_DEMO_PASSWORD=secret
const password = String.fromEnvironment('QA_DEMO_PASSWORD');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a signed-in user can place an order', (tester) async {
    app.main();
    await pumpUntilFound(tester, find.byKey(const Key('sign_in')));

    await tester.enterText(find.byKey(const Key('email')), 'ada@example.com');
    await tester.enterText(find.byKey(const Key('password')), password);
    await tester.tap(find.byKey(const Key('sign_in')));
    await pumpUntilFound(tester, find.text('Welcome, ada@example.com'));

    // The row is far down a lazy list: scroll until it exists, then bring it
    // clear of the checkout button that floats over the list's corner.
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

    await tester.tap(find.byKey(const Key('checkout')));
    await pumpUntilFound(tester, find.text(r'Total $348.75'));
    await tester.tap(find.text('Place order'));
    await pumpUntilFound(tester, find.text('Order placed'));
  });
}

/// Pumps frames until [finder] matches. Unlike pumpAndSettle it works on
/// screens where something animates for ever, and it never waits longer than
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
