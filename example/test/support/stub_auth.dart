import 'package:qa_demo/domain/auth_repository.dart';

/// An [AuthRepository] whose answer each test decides, and which records how
/// it was called.
class StubAuth implements AuthRepository {
  StubAuth(this.answer);

  final Future<User> Function(String email, String password) answer;
  final calls = <({String email, String password})>[];

  @override
  Future<User> signIn(String email, String password) {
    calls.add((email: email, password: password));
    return answer(email, password);
  }
}
