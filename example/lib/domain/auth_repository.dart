class User {
  const User(this.email);

  final String email;
}

class AuthException implements Exception {
  const AuthException(this.message);

  final String message;
}

abstract interface class AuthRepository {
  /// Throws [AuthException] when the credentials are rejected.
  Future<User> signIn(String email, String password);
}
