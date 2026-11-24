import 'package:flutter/material.dart';

import 'data/fake_auth_repository.dart';
import 'domain/auth_repository.dart';
import 'presentation/controllers.dart';
import 'presentation/login_screen.dart';

void main() => runApp(const DemoApp(auth: FakeAuthRepository()));

class DemoApp extends StatefulWidget {
  const DemoApp({super.key, required this.auth});

  final AuthRepository auth;

  @override
  State<DemoApp> createState() => _DemoAppState();
}

class _DemoAppState extends State<DemoApp> {
  late final _auth = AuthController(widget.auth);
  final _cart = CartController();
  final _darkMode = ValueNotifier(false);

  @override
  void dispose() {
    _auth.dispose();
    _cart.dispose();
    _darkMode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppScope(
      auth: _auth,
      cart: _cart,
      darkMode: _darkMode,
      child: ValueListenableBuilder<bool>(
        valueListenable: _darkMode,
        builder: (context, dark, _) => MaterialApp(
          title: 'QA Demo',
          theme: ThemeData(colorSchemeSeed: Colors.indigo),
          darkTheme: ThemeData(
            colorSchemeSeed: Colors.indigo,
            brightness: Brightness.dark,
          ),
          themeMode: dark ? ThemeMode.dark : ThemeMode.light,
          home: const LoginScreen(),
        ),
      ),
    );
  }
}
