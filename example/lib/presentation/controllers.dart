import 'package:flutter/widgets.dart';

import '../domain/auth_repository.dart';
import '../domain/cart.dart';

enum AuthStatus { signedOut, signingIn, signedIn }

class AuthController extends ChangeNotifier {
  AuthController(this._repository);

  final AuthRepository _repository;

  AuthStatus status = AuthStatus.signedOut;
  User? user;
  String? error;

  Future<void> signIn(String email, String password) async {
    if (status == AuthStatus.signingIn) return;
    status = AuthStatus.signingIn;
    error = null;
    notifyListeners();
    try {
      user = await _repository.signIn(email.trim(), password);
      status = AuthStatus.signedIn;
    } on AuthException catch (exception) {
      error = exception.message;
      status = AuthStatus.signedOut;
    } catch (_) {
      // A dropped connection must not leave the spinner up for ever.
      error = 'Could not sign in. Try again.';
      status = AuthStatus.signedOut;
    }
    notifyListeners();
  }

  void signOut() {
    user = null;
    status = AuthStatus.signedOut;
    notifyListeners();
  }
}

class CartController extends ChangeNotifier {
  final cart = Cart();

  void add(String name, int unitPriceCents) {
    cart.add(name, unitPriceCents);
    notifyListeners();
  }
}

/// Hands the app's controllers down the tree.
class AppScope extends InheritedWidget {
  const AppScope({
    super.key,
    required this.auth,
    required this.cart,
    required this.darkMode,
    required super.child,
  });

  final AuthController auth;
  final CartController cart;
  final ValueNotifier<bool> darkMode;

  static AppScope of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppScope>()!;

  @override
  bool updateShouldNotify(AppScope oldWidget) => false;
}
