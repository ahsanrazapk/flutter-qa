/// One product line in the cart. Money is kept in cents so sums stay exact.
class CartLine {
  const CartLine(this.name, this.unitPriceCents, this.quantity);

  final String name;
  final int unitPriceCents;
  final int quantity;

  int get totalCents => unitPriceCents * quantity;
}

class Cart {
  final _lines = <String, CartLine>{};

  List<CartLine> get lines => List.unmodifiable(_lines.values);

  int get itemCount =>
      _lines.values.fold(0, (sum, line) => sum + line.quantity);

  int get subtotalCents =>
      _lines.values.fold(0, (sum, line) => sum + line.totalCents);

  /// Orders of 100.00 or more get 10% off.
  int get discountCents => subtotalCents >= 10000 ? subtotalCents ~/ 10 : 0;

  int get totalCents => subtotalCents - discountCents;

  void add(String name, int unitPriceCents) {
    final quantity = (_lines[name]?.quantity ?? 0) + 1;
    _lines[name] = CartLine(name, unitPriceCents, quantity);
  }

  void remove(String name) => _lines.remove(name);
}

String formatCents(int cents) =>
    '\$${cents ~/ 100}.${(cents % 100).toString().padLeft(2, '0')}';
