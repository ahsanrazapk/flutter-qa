import 'package:flutter/material.dart';

import 'controllers.dart';
import 'home_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    final auth = AppScope.of(context).auth;
    await auth.signIn(_email.text, _password.text);
    if (!mounted || auth.status != AuthStatus.signedIn) return;
    await Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(builder: (_) => const HomeScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = AppScope.of(context).auth;
    return Scaffold(
      appBar: AppBar(title: const Text('Sign in')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _form,
          child: ListenableBuilder(
            listenable: auth,
            builder: (context, _) => Column(
              children: [
                TextFormField(
                  key: const Key('email'),
                  controller: _email,
                  decoration: const InputDecoration(labelText: 'Email'),
                  validator: (value) => value != null && value.contains('@')
                      ? null
                      : 'Enter a valid email',
                ),
                TextFormField(
                  key: const Key('password'),
                  controller: _password,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'Password'),
                  validator: (value) => value == null || value.isEmpty
                      ? 'Enter your password'
                      : null,
                  onFieldSubmitted: (_) => _submit(),
                ),
                const SizedBox(height: 16),
                if (auth.status == AuthStatus.signingIn)
                  const CircularProgressIndicator()
                else
                  FilledButton(
                    key: const Key('sign_in'),
                    onPressed: _submit,
                    child: const Text('Sign in'),
                  ),
                if (auth.error case final error?)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      error,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
