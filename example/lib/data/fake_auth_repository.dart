import '../domain/auth_repository.dart';

/// Stands in for a real backend: any email works with the password "secret".
class FakeAuthRepository implements AuthRepository {
  const FakeAuthRepository({this.delay = const Duration(milliseconds: 600)});

  final Duration delay;

  @override
  Future<User> signIn(String email, String password) async {
    await Future<void>.delayed(delay);
    if (password != 'secret') throw const AuthException('Invalid credentials');
    return User(email);
  }
}
