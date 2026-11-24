import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qa_demo/domain/auth_repository.dart';
import 'package:qa_demo/presentation/controllers.dart';
import 'package:qa_demo/presentation/home_screen.dart';

import 'support/stub_auth.dart';

void main() {
  late CartController cart;

  Future<void> pumpHome(WidgetTester tester) async {
    cart = CartController();
    await tester.pumpWidget(
      AppScope(
        auth: AuthController(StubAuth((email, _) async => User(email))),
        cart: cart,
        darkMode: ValueNotifier(false),
        child: const MaterialApp(home: HomeScreen()),
      ),
    );
  }

  // Home shows an indicator that never stops, so these tests pump a duration
  // where another screen's tests would use pumpAndSettle.
  const transition = Duration(milliseconds: 500);

  testWidgets('adding products updates the cart summary', (tester) async {
    await pumpHome(tester);
    expect(find.text(r'Cart: 0 items · $0.00'), findsOneWidget);

    await tester.tap(find.byTooltip('Add Product 0'));
    await tester.tap(find.byTooltip('Add Product 0'));
    await tester.tap(find.byTooltip('Add Product 1'));
    await tester.pump();

    expect(find.text(r'Cart: 3 items · $50.00'), findsOneWidget);
  });

  testWidgets('checking out an empty cart explains instead of ordering', (
    tester,
  ) async {
    await pumpHome(tester);

    await tester.tap(find.byKey(const Key('checkout')));
    await tester.pump(transition);

    expect(find.text('Your cart is empty'), findsOneWidget);
    expect(find.text('Place order?'), findsNothing);
  });

  testWidgets('the dialog shows the discounted total and places the order', (
    tester,
  ) async {
    await pumpHome(tester);
    cart.add('Product 9', 12500);

    await tester.tap(find.byKey(const Key('checkout')));
    await tester.pump(transition);
    expect(find.text(r'Total $112.50'), findsOneWidget);

    await tester.tap(find.text('Place order'));
    await tester.pump(transition);
    expect(find.text('Order placed'), findsOneWidget);
  });

  testWidgets('cancelling the dialog places nothing', (tester) async {
    await pumpHome(tester);
    cart.add('Product 0', 1250);

    await tester.tap(find.byKey(const Key('checkout')));
    await tester.pump(transition);
    await tester.tap(find.text('Cancel'));
    await tester.pump(transition);

    expect(find.text('Order placed'), findsNothing);
    expect(cart.cart.itemCount, 1);
  });

  testWidgets('a product opens its own page', (tester) async {
    await pumpHome(tester);

    await tester.tap(find.text('Product 2'));
    await tester.pump();
    await tester.pump(transition);

    expect(find.text('Your rating: 0'), findsOneWidget);
    expect(find.text(r'$37.50'), findsOneWidget);
  });
}
