import 'package:flutter_test/flutter_test.dart';
import 'package:qa_demo/domain/cart.dart';

void main() {
  group('Cart', () {
    test('starts empty', () {
      final cart = Cart();
      expect(cart.itemCount, 0);
      expect(cart.totalCents, 0);
    });

    test('adding a product again raises its quantity, not the line count', () {
      final cart = Cart()
        ..add('Tea', 450)
        ..add('Tea', 450);
      expect(cart.lines, hasLength(1));
      expect(cart.itemCount, 2);
      expect(cart.subtotalCents, 900);
    });

    // The discount rule has one boundary, so test just below it and on it.
    test('gives no discount just under 100.00', () {
      final cart = Cart()..add('Lamp', 9999);
      expect(cart.discountCents, 0);
      expect(cart.totalCents, 9999);
    });

    test('gives 10% off from exactly 100.00', () {
      final cart = Cart()..add('Lamp', 10000);
      expect(cart.discountCents, 1000);
      expect(cart.totalCents, 9000);
    });

    test('rounds the discount down to whole cents', () {
      final cart = Cart()..add('Lamp', 10005);
      expect(cart.discountCents, 1000);
      expect(cart.totalCents, 9005);
    });

    test('removing a product drops its whole line', () {
      final cart = Cart()
        ..add('Tea', 450)
        ..add('Tea', 450)
        ..add('Cup', 1200)
        ..remove('Tea');
      expect(cart.itemCount, 1);
      expect(cart.subtotalCents, 1200);
    });
  });

  test('formatCents always shows two decimals', () {
    expect(formatCents(0), r'$0.00');
    expect(formatCents(5), r'$0.05');
    expect(formatCents(123450), r'$1234.50');
  });
}
