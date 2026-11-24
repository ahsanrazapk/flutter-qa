// Self-tests for the plugin's HTML report generator.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../../skills/running-flutter-qa/scripts/qa_report.dart';

Map<String, dynamic> report() => {
  'title': 'Checkout',
  'verdict': 'Not ready: an order can be placed twice',
  'results': [
    {
      'layer': 'Static analysis',
      'command': 'flutter analyze',
      'result': '0 errors',
      'status': 'pass',
    },
  ],
  'defects': [
    {
      'severity': 'Low',
      'title': 'Typo in the empty state',
      'steps': ['Open the cart'],
      'expected': '"Your cart is empty"',
      'actual': '"Your cart is emtpy"',
    },
    {
      'severity': 'High',
      'title': 'A double tap places two orders',
      'where': 'lib/checkout.dart:88',
      'steps': ['Add a product', 'Double tap "Place order"'],
      'expected': 'One order',
      'actual': 'Two orders',
      'screenshot': '01-double-order.png',
    },
  ],
  'notCovered': ['Release builds'],
};

void main() {
  group('problemsIn', () {
    test('accepts a complete report', () {
      expect(problemsIn(report()), isEmpty);
    });

    test('accepts the example the skill points to', () {
      final example = File(
        '../skills/running-flutter-qa/qa-report-example.json',
      ).readAsStringSync();
      expect(problemsIn(jsonDecode(example) as Map<String, dynamic>), isEmpty);
    });

    test('insists on saying what was not covered', () {
      final problems = problemsIn(report()..['notCovered'] = <String>[]);
      expect(problems.single, contains('notCovered'));
    });

    test('names each missing or invalid field', () {
      final broken = report()
        ..remove('verdict')
        ..['results'] = [
          {'layer': 'Unit tests', 'command': 'flutter test', 'status': 'ok'},
        ]
        ..['defects'] = [
          {'severity': 'Critical', 'title': 'Crash', 'steps': <String>[]},
        ];
      expect(
        problemsIn(broken),
        containsAll([
          '"verdict" is missing.',
          'results[0]: "result" is missing.',
          'results[0]: "status" must be one of pass, fail, not run.',
          'defects[0]: "severity" must be one of High, Medium, Low.',
          'defects[0]: "expected" is missing.',
          'defects[0]: "steps" must list how to reproduce it.',
        ]),
      );
    });
  });

  group('findBrowser', () {
    String? find(
      String system, {
      Map<String, String> environment = const {},
      Set<String> installed = const {},
    }) => findBrowser(
      operatingSystem: system,
      environment: environment,
      exists: installed.contains,
    );

    test('prefers the browser Flutter was told to use', () {
      expect(
        find(
          'macos',
          environment: {'CHROME_EXECUTABLE': '/opt/chrome'},
          installed: {
            '/opt/chrome',
            '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
          },
        ),
        '/opt/chrome',
      );
    });

    test('finds Edge on a Mac that has no Chrome', () {
      const edge =
          '/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge';
      expect(find('macos', installed: {edge}), edge);
    });

    test('searches the PATH on Linux', () {
      expect(
        find(
          'linux',
          environment: {'PATH': '/usr/local/bin:/usr/bin'},
          installed: {'/usr/bin/chromium'},
        ),
        '/usr/bin/chromium',
      );
    });

    test('looks under Program Files on Windows', () {
      const chrome = r'C:\Program Files\Google\Chrome\Application\chrome.exe';
      expect(
        find(
          'windows',
          environment: {'PROGRAMFILES': r'C:\Program Files'},
          installed: {chrome},
        ),
        chrome,
      );
    });

    test('returns null when there is none', () {
      expect(find('linux', environment: {'PATH': '/usr/bin'}), isNull);
    });
  });

  group('renderReport', () {
    String render(Map<String, dynamic> report) => renderReport(
      report,
      image: (name) => name == '01-double-order.png' ? [1, 2, 3] : null,
    );

    test('puts the most severe defect first and counts each severity', () {
      final html = render(report());
      expect(
        html.indexOf('A double tap places two orders'),
        lessThan(html.indexOf('Typo in the empty state')),
      );
      expect(html, contains('<li class="high"><b>1</b> High</li>'));
      expect(html, contains('<li class="medium"><b>0</b> Medium</li>'));
      expect(html, contains('<li class="low"><b>1</b> Low</li>'));
    });

    test('embeds a screenshot so the page stands alone', () {
      final html = render(report());
      expect(html, contains('src="data:image/png;base64,AQID"'));
      expect(html, isNot(contains('src="01-double-order.png"')));
    });

    test('says so when a screenshot is missing instead of failing', () {
      final missing = report();
      (missing['defects'] as List)[1]['screenshot'] = 'lost.png';
      expect(render(missing), contains('Screenshot not found: lost.png'));
    });

    test('escapes everything that came from the app or the tester', () {
      final hostile = report()
        ..['title'] = '<script>alert(1)</script>'
        ..['verdict'] = 'Ready "now" & <b>';
      final html = render(hostile);
      expect(html, isNot(contains('<script>alert(1)</script>')));
      expect(html, contains('&lt;script&gt;alert(1)&lt;&#47;script&gt;'));
      expect(html, contains('Ready &quot;now&quot; &amp; &lt;b&gt;'));
    });

    test('colours the verdict by what it says', () {
      expect(render(report()), contains('class="verdict bad"'));
      expect(
        render(report()..['verdict'] = 'Ready with the listed risks'),
        contains('class="verdict warn"'),
      );
      expect(
        render(report()..['verdict'] = 'Ready'),
        contains('class="verdict good"'),
      );
    });

    test('marks a layer that was not run', () {
      final skipped = report()
        ..['results'] = [
          {
            'layer': 'Integration tests',
            'command': 'flutter test integration_test',
            'result': 'no device was available',
            'status': 'not run',
          },
        ];
      expect(render(skipped), contains('<tr class="not-run">'));
    });

    test('renders a report with no defects', () {
      final clean = report()..['defects'] = <Object>[];
      expect(render(clean), contains('None found in what was checked.'));
    });
  });
}
