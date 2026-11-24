import 'package:flutter/cupertino.dart';

import 'controllers.dart';
import 'login_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  Future<void> _confirmSignOut(BuildContext context) async {
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('Sign out?'),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    AppScope.of(context).auth.signOut();
    await Navigator.of(context).pushAndRemoveUntil(
      CupertinoPageRoute<void>(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final darkMode = AppScope.of(context).darkMode;
    return CupertinoPageScaffold(
      navigationBar: const CupertinoNavigationBar(middle: Text('Settings')),
      child: SafeArea(
        // A Cupertino page inside a MaterialApp has no text style of its
        // own: without this, plain Text is drawn in the red fallback style.
        child: DefaultTextStyle(
          style: CupertinoTheme.of(context).textTheme.textStyle,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Dark mode'),
                    ValueListenableBuilder<bool>(
                      valueListenable: darkMode,
                      builder: (context, dark, _) => CupertinoSwitch(
                        key: const Key('dark_mode'),
                        value: dark,
                        onChanged: (value) => darkMode.value = value,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const CupertinoTextField(
                  key: Key('display_name'),
                  placeholder: 'Display name',
                ),
                const SizedBox(height: 16),
                CupertinoButton(
                  onPressed: () => _confirmSignOut(context),
                  child: const Text('Sign out'),
                ),
                // Lets the plugin's own tests check that app errors get reported.
                CupertinoButton(
                  onPressed: () => throw StateError('Deliberate test error'),
                  child: const Text('Throw test error'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
