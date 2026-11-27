// Self-tests for the pure parts of the plugin's host CLI.
import 'package:flutter_test/flutter_test.dart';

import '../../../skills/driving-flutter-apps/scripts/pilot.dart';

Matcher failsWith(String text) =>
    throwsA(isA<Fail>().having((f) => f.message, 'message', contains(text)));

void main() {
  group('parseArgs', () {
    test('separates the command, a ref, options and switches', () {
      final args = parseArgs(['tap', '12', '--timeout', '3', '--long']);
      expect(args.positional, ['tap', '12']);
      expect(args.options, {'timeout': '3', 'long': 'true'});
    });

    test('keeps negative numbers and text that starts with a dash', () {
      final args = parseArgs(['scroll', '--dy', '-300']);
      expect(args.options['dy'], '-300');
      expect(parseArgs(['type', '-5']).positional, ['type', '-5']);
    });

    test('passes everything after -- on to flutter run', () {
      final args = parseArgs([
        'start',
        '-d',
        'emulator-5554',
        '--',
        '--flavor',
        'dev',
      ]);
      expect(args.options['device'], 'emulator-5554');
      expect(args.passthrough, ['--flavor', 'dev']);
    });

    test('rejects typos instead of swallowing them', () {
      expect(
        () => parseArgs(['tap', '--txet', 'x']),
        failsWith('Unknown option'),
      );
      expect(() => parseArgs(['tap', '--text']), failsWith('needs a value'));
    });
  });

  group('targetOf', () {
    test('reads a ref or a finder, with an index', () {
      expect(targetOf(parseArgs(['tap', '12'])), {'ref': '12'});
      expect(targetOf(parseArgs(['tap', '--text', 'Save', '--index', '1'])), {
        'text': 'Save',
        'index': '1',
      });
    });

    test('skips the text of a type command', () {
      expect(targetOf(parseArgs(['type', 'hello', '7']), skip: 2), {
        'ref': '7',
      });
      expect(targetOf(parseArgs(['type', 'hello']), skip: 2), isEmpty);
    });

    test('refuses two targets and words that are not refs', () {
      expect(
        () => targetOf(parseArgs(['tap', '3', '--text', 'Save'])),
        failsWith('one target'),
      );
      expect(
        () => targetOf(parseArgs(['tap', 'Save'])),
        failsWith('not a ref'),
      );
    });
  });

  group('flow lines', () {
    test('split like a shell, with quotes and comments', () {
      expect(splitLine('type "ada lovelace" --key name  # her name'), [
        'type',
        'ada lovelace',
        '--key',
        'name',
      ]);
      expect(splitLine("tap --text 'Say \"hi\"'"), [
        'tap',
        '--text',
        'Say "hi"',
      ]);
      expect(splitLine('type "" --key name'), ['type', '', '--key', 'name']);
      expect(splitLine('   # only a comment'), isEmpty);
      expect(splitLine('tap --text a#b'), ['tap', '--text', 'a#b']);
    });

    test('report an unclosed quote', () {
      expect(() => splitLine('type "oops'), failsWith('Unclosed'));
    });

    test('take secrets from the environment', () {
      expect(expandEnv(r'${USER_PW}!', {'USER_PW': 's3cret'}), 's3cret!');
      expect(() => expandEnv(r'${MISSING}', {}), failsWith('MISSING'));
    });
  });

  group('snapshot rendering', () {
    test('shows role, text, state and origin on one line', () {
      expect(
        renderNode({
          'ref': 7,
          'depth': 1,
          'label': 'Sign in',
          'flags': ['isButton', 'hasEnabledState'],
          'actions': ['tap'],
          'widget': 'FilledButton',
          'key': 'sign_in',
          'src': 'lib/login.dart:70',
        }),
        '  [7] button "Sign in" (disabled)  <- FilledButton key=sign_in lib/login.dart:70',
      );
    });

    test('shows values, switches, scrolling and custom controls', () {
      expect(
        renderNode({
          'ref': 5,
          'label': 'Email',
          'value': 'a@b.c',
          'flags': ['isTextField', 'isFocused'],
        }),
        '[5] textfield "Email" = "a@b.c" (focused)',
      );
      expect(
        renderNode({
          'ref': 3,
          'flags': ['hasToggledState'],
          'actions': ['tap'],
        }),
        '[3] switch (off)',
      );
      expect(
        renderNode({
          'ref': 4,
          'flags': ['hasToggledState', 'isToggled'],
        }),
        '[4] switch (on)',
      );
      expect(
        renderNode({
          'ref': 9,
          'actions': ['scrollUp'],
          'scroll': [120, 2400],
        }),
        '[9] scrollable (scrolled 120 of 2400)',
      );
      expect(
        renderNode({
          'ref': 2,
          'label': 'Rating',
          'value': '3 of 5',
          'actions': ['increase', 'decrease'],
        }),
        '[2] text "Rating" = "3 of 5" (increase, decrease)',
      );
      expect(
        renderNode({
          'ref': 8,
          'label': 'Add',
          'tooltip': 'Add to cart',
          'flags': ['isButton'],
          'offscreen': true,
        }),
        '[8] button "Add" tooltip "Add to cart" (off screen)',
      );
    });

    test('says so when the screen is blank', () {
      expect(
        renderSnapshot({
          'size': [800, 600],
          'route': null,
          'nodes': <Object>[],
        }),
        'screen 800x600\n(nothing is on screen: the app is showing a blank page)',
      );
    });

    test('heads the list with the screen size and route', () {
      expect(
        renderSnapshot({
          'size': [411, 890],
          'route': '/cart (MaterialPageRoute<void>)',
          'nodes': [
            {
              'ref': 1,
              'depth': 0,
              'label': 'Cart',
              'flags': ['isHeader'],
            },
          ],
        }),
        'screen 411x890  route /cart (MaterialPageRoute<void>)\n[1] header "Cart"',
      );
    });
  });

  group('changed code', () {
    test('reads the new side of a diff, hunk by hunk', () {
      const diff = '''
diff --git a/lib/cart.dart b/lib/cart.dart
--- a/lib/cart.dart
+++ b/lib/cart.dart
@@ -5 +5 @@ class Cart {
-  old
+  new
@@ -12,2 +11,0 @@
-  gone
-  gone too
@@ -70,2 +68,3 @@
-  a
-  b
+  a
+  b
+  c
diff --git a/lib/old.dart b/lib/old.dart
--- a/lib/old.dart
+++ /dev/null
@@ -1,2 +0,0 @@
-gone
-gone
diff --git a/lib/new.dart b/lib/new.dart
--- /dev/null
+++ b/lib/new.dart
@@ -0,0 +1,4 @@
+one
''';
      expect(changedLines(diff), {
        'lib/cart.dart': [(5, 5), (11, 11), (68, 70)],
        'lib/new.dart': [(1, 4)],
      });
    });

    // Line numbers:  1 class, 2 submit, 5 build, 6 Scaffold, 7 AppBar,
    // 8 Padding, 10 Column, 12 FilledButton, 16 Text('Total').
    const source = '''
class CartPage extends StatelessWidget {
  void _submit() {
    order();
  }
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Cart')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            FilledButton(
              onPressed: _submit,
              child: const Text('Place order'),
            ),
            const Text('Total'),
          ],
        ),
      ),
    );
  }
}''';

    /// The snapshot of that page, and which labels a change to [lines] marks.
    (List<String>, Map<String, String>) marked(List<(int, int)> lines) {
      String at(int line) => 'lib/cart_page.dart:$line';
      final snapshot = {
        'nodes': [
          {
            'label': 'Cart',
            'src': at(7),
            'chain': [at(7), at(6)],
          },
          {
            'label': 'Place order',
            'src': at(12),
            'chain': [at(12), at(10), at(8), at(6)],
          },
          {
            'label': 'Total',
            'src': at(16),
            'chain': [at(16), at(10), at(8), at(6)],
          },
        ],
      };
      final elsewhere = markChanged(snapshot, {
        'lib/cart_page.dart': lines,
      }, (file) => source.split('\n'));
      return (
        [
          for (final node in snapshot['nodes']!)
            if (node['changed'] == true) node['label']! as String,
        ],
        elsewhere,
      );
    }

    test('a changed line marks the widget whose call it lies in', () {
      expect(marked([(16, 16)]).$1, ['Total']);
      // The button's callback and its child are part of the button.
      expect(marked([(13, 14)]).$1, ['Place order']);
    });

    test('a changed wrapper marks everything it wraps, and nothing else', () {
      expect(marked([(9, 9)]).$1, ['Place order', 'Total']);
    });

    test('changed lines outside every widget on screen are handed back', () {
      final (labels, elsewhere) = marked([(3, 3), (16, 16), (21, 22)]);
      expect(labels, ['Total']);
      expect(elsewhere, {'lib/cart_page.dart': '3, 21-22'});
    });

    test('a snapshot says what changed here and what did not show', () {
      expect(
        renderSnapshot({
          'size': [800, 600],
          'route': null,
          'nodes': [
            {'ref': 1, 'depth': 0, 'label': 'Total', 'changed': true},
            {'ref': 2, 'depth': 0, 'label': 'Cart'},
          ],
          'changed': {
            'base': 'main',
            'files': 2,
            'elsewhere': {'lib/cart.dart': '12-18'},
          },
        }),
        'screen 800x600\n'
        '[1] text "Total"  *changed*\n'
        '[2] text "Cart"\n'
        'changed since main: 1 of these elements. '
        'Changed, but no widget on this screen:\n'
        '  lib/cart.dart:12-18',
      );
    });
  });

  group('session setup', () {
    test('reads the package name from a pubspec', () {
      expect(
        packageName('description: x\nname: shop_app\nversion: 1.0.0\n'),
        'shop_app',
      );
      expect(() => packageName('version: 1.0.0\n'), failsWith('no name'));
    });

    test('generates an entrypoint that installs the bridge first', () {
      final code = entrypoint(
        package: 'shop_app',
        target: 'lib/main_dev.dart',
        targetSource: 'Future<void> main() async {}',
      );
      expect(code, contains("import 'package:shop_app/main_dev.dart' as app;"));
      expect(
        code.indexOf('installPilot();'),
        lessThan(code.indexOf('app.main();')),
      );
    });

    test('handles a main that takes arguments or lives outside lib', () {
      final code = entrypoint(
        package: 'shop_app',
        target: 'tool/main.dart',
        targetSource: 'void main(List<String> args) {}',
      );
      expect(code, contains("import '../../tool/main.dart' as app;"));
      expect(code, contains('app.main(const <String>[]);'));
    });

    test('turns the VM service address into its WebSocket address', () {
      expect(
        '${webSocketUri('http://127.0.0.1:60272/iDI7AcG-usQ=/\n')}',
        'ws://127.0.0.1:60272/iDI7AcG-usQ=/ws',
      );
      expect(
        '${webSocketUri('http://127.0.0.1:8181')}',
        'ws://127.0.0.1:8181/ws',
      );
    });
  });
}
