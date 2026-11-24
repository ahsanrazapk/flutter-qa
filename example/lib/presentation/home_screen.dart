import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../domain/cart.dart';
import 'controllers.dart';
import 'rating_stars.dart';
import 'settings_screen.dart';

/// Product [index] costs 12.50 more than the one before it.
int priceCentsOf(int index) => 1250 * (index + 1);

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  Future<void> _checkout(BuildContext context) async {
    final cart = AppScope.of(context).cart.cart;
    if (cart.itemCount == 0) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Your cart is empty')));
      return;
    }
    final placed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Place order?'),
        content: Text('Total ${formatCents(cart.totalCents)}'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Place order'),
          ),
        ],
      ),
    );
    if (placed != true || !context.mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Order placed')));
  }

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Home'),
        actions: [
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.settings),
            onPressed: () => Navigator.of(context).push(
              CupertinoPageRoute<void>(builder: (_) => const SettingsScreen()),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('checkout'),
        onPressed: () => _checkout(context),
        label: const Text('Checkout'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text('Welcome, ${scope.auth.user?.email ?? 'guest'}'),
          ),
          ListenableBuilder(
            listenable: scope.cart,
            builder: (context, _) => Text(
              'Cart: ${scope.cart.cart.itemCount} items · '
              '${formatCents(scope.cart.cart.totalCents)}',
              key: const Key('cart_summary'),
            ),
          ),
          // Animates for ever, like a sync indicator in a real app.
          const LinearProgressIndicator(),
          Expanded(
            child: ListView.builder(
              // Room to scroll the last rows clear of the checkout button.
              padding: const EdgeInsets.only(bottom: 88),
              itemCount: 40,
              itemBuilder: (context, index) => ListTile(
                title: Text('Product $index'),
                subtitle: Text(formatCents(priceCentsOf(index))),
                trailing: IconButton(
                  tooltip: 'Add Product $index',
                  icon: const Icon(Icons.add_shopping_cart),
                  onPressed: () =>
                      scope.cart.add('Product $index', priceCentsOf(index)),
                ),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => ProductScreen(index: index),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class ProductScreen extends StatefulWidget {
  const ProductScreen({super.key, required this.index});

  final int index;

  @override
  State<ProductScreen> createState() => _ProductScreenState();
}

class _ProductScreenState extends State<ProductScreen> {
  int _rating = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Product ${widget.index}')),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(formatCents(priceCentsOf(widget.index))),
            const SizedBox(height: 16),
            RatingStars(
              rating: _rating,
              onChanged: (rating) => setState(() => _rating = rating),
            ),
            Text('Your rating: $_rating'),
          ],
        ),
      ),
    );
  }
}
