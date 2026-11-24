// Turns a QA report written as JSON into one self-contained HTML page, with
// its screenshots embedded so the file can be sent to anyone, and prints that
// page to a PDF when a Chromium-family browser is installed.
// Dart SDK only: dart qa_report.dart qa-report/report.json
import 'dart:async';
import 'dart:convert';
import 'dart:io';

const usage = '''
Usage: dart qa_report.dart REPORT.json

Writes REPORT.html and REPORT.pdf next to the JSON file. Screenshot names in
the report are looked up next to the JSON file too. See
qa-report-example.json for the fields; a report with a required field missing
is refused.

The PDF is printed from the HTML by Chrome, Chromium, Edge or Brave, found in
the usual places or through CHROME_EXECUTABLE (the variable Flutter's web
tooling reads). Without one, open the HTML and print it to PDF yourself.''';

const severities = ['High', 'Medium', 'Low'];
const statuses = ['pass', 'fail', 'not run'];

String _text(Object? value) => const HtmlEscape().convert('${value ?? ''}');

bool _filled(Object? value) => value is String && value.trim().isNotEmpty;

/// What is wrong with [report], one message per problem; empty when it can
/// be rendered.
List<String> problemsIn(Map<String, dynamic> report) {
  final problems = <String>[];
  for (final field in ['title', 'verdict']) {
    if (!_filled(report[field])) problems.add('"$field" is missing.');
  }

  final results = report['results'];
  if (results is! List || results.isEmpty) {
    problems.add('"results" needs one entry for each layer that was run.');
  } else {
    for (final (index, result) in results.indexed) {
      final where = 'results[$index]';
      if (result is! Map) {
        problems.add('$where is not an object.');
        continue;
      }
      for (final field in ['layer', 'command', 'result']) {
        if (!_filled(result[field]))
          problems.add('$where: "$field" is missing.');
      }
      if (!statuses.contains(result['status'])) {
        problems.add('$where: "status" must be one of ${statuses.join(', ')}.');
      }
    }
  }

  final defects = report['defects'];
  if (defects is! List) {
    problems.add('"defects" must be a list; use [] when there are none.');
  } else {
    for (final (index, defect) in defects.indexed) {
      final where = 'defects[$index]';
      if (defect is! Map) {
        problems.add('$where is not an object.');
        continue;
      }
      if (!severities.contains(defect['severity'])) {
        problems.add(
          '$where: "severity" must be one of ${severities.join(', ')}.',
        );
      }
      for (final field in ['title', 'expected', 'actual']) {
        if (!_filled(defect[field]))
          problems.add('$where: "$field" is missing.');
      }
      final steps = defect['steps'];
      if (steps is! List || steps.isEmpty) {
        problems.add('$where: "steps" must list how to reproduce it.');
      }
    }
  }

  final notCovered = report['notCovered'];
  if (notCovered is! List || notCovered.isEmpty) {
    problems.add(
      '"notCovered" is empty. Something is always left unchecked: say what.',
    );
  }
  return problems;
}

String _verdictClass(String verdict) {
  final lower = verdict.toLowerCase();
  if (lower.startsWith('not ready')) return 'bad';
  if (lower.startsWith('ready with')) return 'warn';
  if (lower.startsWith('ready')) return 'good';
  return 'warn';
}

String _list(Object? items, {String tag = 'ul'}) =>
    items is List && items.isNotEmpty
    ? '<$tag>${[for (final item in items) '<li>${_text(item)}</li>'].join()}</$tag>'
    : '';

String _defect(
  Map<String, dynamic> defect,
  List<int>? Function(String name) image,
) {
  final severity = '${defect['severity']}';
  final place = [
    if (_filled(defect['where'])) '<code>${_text(defect['where'])}</code>',
    if (_filled(defect['device'])) _text(defect['device']),
  ].join(' · ');

  var figure = '';
  if (defect['screenshot'] case final String name when name.isNotEmpty) {
    final bytes = image(name);
    final type = name.toLowerCase().endsWith('.png') ? 'png' : 'jpeg';
    figure = bytes == null
        ? '<p class="missing">Screenshot not found: ${_text(name)}</p>'
        : '<figure><img alt="Screenshot: ${_text(defect['title'])}" '
              'src="data:image/$type;base64,${base64Encode(bytes)}">'
              '<figcaption>${_text(name)}</figcaption></figure>';
  }

  String part(String heading, Object? body) =>
      _filled(body) ? '<h4>$heading</h4><p>${_text(body)}</p>' : '';

  return '''
<article class="defect ${severity.toLowerCase()}">
  <h3><span class="badge">${_text(severity)}</span> ${_text(defect['title'])}</h3>
  ${place.isEmpty ? '' : '<p class="where">$place</p>'}
  <div class="columns">
    <div>
      <h4>Steps</h4>${_list(defect['steps'], tag: 'ol')}
      ${part('Expected', defect['expected'])}
      ${part('Actual', defect['actual'])}
      ${part('Evidence', defect['evidence'])}
    </div>
    $figure
  </div>
</article>''';
}

/// The report as one HTML page. [image] returns a screenshot's bytes, or
/// null when it cannot be read.
String renderReport(
  Map<String, dynamic> report, {
  required List<int>? Function(String name) image,
}) {
  final defects = [
    for (final severity in severities)
      for (final defect in report['defects'] as List)
        if ((defect as Map)['severity'] == severity)
          defect.cast<String, dynamic>(),
  ];
  final counts = [
    for (final severity in severities)
      (
        severity: severity,
        count: defects.where((d) => d['severity'] == severity).length,
      ),
  ];
  final verdict = '${report['verdict']}';
  final scope = report['scope'];

  return '''
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>QA report: ${_text(report['title'])}</title>
<style>$_style</style>
</head>
<body>
<main>
<header>
  <p class="kicker">QA report</p>
  <h1>${_text(report['title'])}</h1>
  <p class="verdict ${_verdictClass(verdict)}">${_text(verdict)}</p>
  ${_filled(report['summary']) ? '<p class="summary">${_text(report['summary'])}</p>' : ''}
  <ul class="counts">
    ${[for (final entry in counts) '<li class="${entry.severity.toLowerCase()}"><b>${entry.count}</b> ${entry.severity}</li>'].join()}
  </ul>
</header>

${scope is Map && scope.isNotEmpty ? '''
<section>
  <h2>Scope</h2>
  <dl>${[for (final entry in scope.entries) '<dt>${_text(entry.key)}</dt><dd>${_text(entry.value)}</dd>'].join()}</dl>
</section>''' : ''}

<section>
  <h2>Results</h2>
  <table>
    <thead><tr><th>Layer</th><th>Command</th><th>Result</th></tr></thead>
    <tbody>
    ${[for (final result in report['results'] as List) '<tr class="${'${(result as Map)['status']}'.replaceAll(' ', '-')}"><td>${_text(result['layer'])}</td><td><code>${_text(result['command'])}</code></td><td><span class="status">${_text(result['status'])}</span> ${_text(result['result'])}</td></tr>'].join('\n    ')}
    </tbody>
  </table>
  ${report['testsAdded'] is List && (report['testsAdded'] as List).isNotEmpty ? '<h3 class="minor">Tests added in this pass</h3>${_list(report['testsAdded'])}' : ''}
</section>

<section>
  <h2>Defects</h2>
  ${defects.isEmpty ? '<p>None found in what was checked.</p>' : defects.map((d) => _defect(d, image)).join('\n')}
</section>

<section>
  <h2>Not covered</h2>
  <p class="note">What a person still has to check.</p>
  ${_list(report['notCovered'])}
</section>

${report['repeat'] is List && (report['repeat'] as List).isNotEmpty ? '''
<section>
  <h2>How to repeat this</h2>
  <pre>${[for (final line in report['repeat'] as List) _text(line)].join('\n')}</pre>
</section>''' : ''}
</main>
</body>
</html>
''';
}

const _style = '''
:root {
  --page: #f6f7f9; --card: #ffffff; --ink: #1c2330; --soft: #5b6676;
  --line: #dde1e7; --code: #eef1f5;
  --high: #c62828; --medium: #b26a00; --low: #5b6676; --good: #1b7a3d;
}
@media (prefers-color-scheme: dark) {
  :root {
    --page: #14181f; --card: #1c222c; --ink: #e8ebf0; --soft: #9aa5b5;
    --line: #2e3643; --code: #262e3a;
    --high: #ff6b6b; --medium: #f0b24a; --low: #9aa5b5; --good: #5fd08a;
  }
}
* { box-sizing: border-box; }
body { margin: 0; background: var(--page); color: var(--ink);
  font: 16px/1.55 system-ui, -apple-system, "Segoe UI", Roboto, sans-serif; }
main { max-width: 1040px; margin: 0 auto; padding: 32px 16px 64px; }
h1 { font-size: 30px; line-height: 1.2; margin: 4px 0 12px; }
h2 { font-size: 20px; margin: 40px 0 12px; }
h3 { font-size: 18px; margin: 0 0 4px; line-height: 1.35; }
h3.minor { font-size: 15px; margin-top: 20px; color: var(--soft); }
h4 { font-size: 12px; text-transform: uppercase; letter-spacing: .06em;
  color: var(--soft); margin: 16px 0 2px; }
p { margin: 0 0 8px; }
code, pre { font: 13px/1.5 ui-monospace, SFMono-Regular, Menlo, Consolas, monospace;
  background: var(--code); border-radius: 4px; }
code { padding: 1px 5px; overflow-wrap: anywhere; }
pre { padding: 14px 16px; overflow-x: auto; }
.kicker { text-transform: uppercase; letter-spacing: .08em; font-size: 12px;
  color: var(--soft); margin: 0; }
.verdict { display: inline-block; font-weight: 600; padding: 6px 12px;
  border-radius: 6px; border: 1px solid currentColor; }
.verdict.bad { color: var(--high); } .verdict.warn { color: var(--medium); }
.verdict.good { color: var(--good); }
.summary { font-size: 18px; max-width: 70ch; }
.counts { list-style: none; display: flex; gap: 20px; padding: 0; margin: 16px 0 0; }
.counts b { font-size: 22px; }
.counts .high { color: var(--high); } .counts .medium { color: var(--medium); }
.counts .low { color: var(--low); }
dl { display: grid; grid-template-columns: max-content 1fr; gap: 6px 20px; margin: 0; }
dt { color: var(--soft); } dd { margin: 0; }
table { width: 100%; border-collapse: collapse; background: var(--card);
  border: 1px solid var(--line); border-radius: 8px; overflow: hidden; }
th, td { text-align: left; padding: 10px 12px; border-bottom: 1px solid var(--line);
  vertical-align: top; }
th { font-size: 12px; text-transform: uppercase; letter-spacing: .06em; color: var(--soft); }
tr:last-child td { border-bottom: 0; }
.status { font-weight: 600; margin-right: 6px; }
tr.pass .status { color: var(--good); } tr.fail .status { color: var(--high); }
tr.not-run .status { color: var(--medium); }
.defect { background: var(--card); border: 1px solid var(--line);
  border-left: 5px solid var(--low); border-radius: 8px; padding: 18px 20px;
  margin: 0 0 16px; break-inside: avoid; }
.defect.high { border-left-color: var(--high); }
.defect.medium { border-left-color: var(--medium); }
.badge { font-size: 12px; font-weight: 700; padding: 2px 8px; border-radius: 999px;
  border: 1px solid currentColor; vertical-align: 2px; margin-right: 6px; }
.high .badge { color: var(--high); } .medium .badge { color: var(--medium); }
.low .badge { color: var(--low); }
.where { color: var(--soft); font-size: 14px; }
.columns { display: grid; grid-template-columns: minmax(0, 1fr) minmax(0, 1fr); gap: 24px; }
.columns > div:only-child { grid-column: 1 / -1; }
ol, ul { margin: 0 0 8px; padding-left: 22px; }
figure { margin: 0; }
figure img { max-width: 100%; height: auto; display: block;
  border: 1px solid var(--line); border-radius: 6px; }
figcaption, .note, .missing { color: var(--soft); font-size: 13px; margin-top: 6px; }
@media (max-width: 760px) { .columns { grid-template-columns: minmax(0, 1fr); } }
@page { size: A4; margin: 14mm 12mm; }
@media print {
  /* Paper is light whatever the reader's screen is set to. */
  :root {
    --page: #ffffff; --card: #ffffff; --ink: #1c2330; --soft: #5b6676;
    --line: #dde1e7; --code: #eef1f5;
    --high: #c62828; --medium: #b26a00; --low: #5b6676; --good: #1b7a3d;
  }
  * { -webkit-print-color-adjust: exact; print-color-adjust: exact; }
  body { font-size: 13px; }
  main { max-width: none; padding: 0; }
  h1 { font-size: 24px; } h2 { margin-top: 26px; break-after: avoid; }
  figure img { max-height: 90mm; width: auto; }
}
''';

/// The first Chromium-family browser that [exists], or null. The environment
/// and the file check are passed in so that this can be tested.
String? findBrowser({
  required String operatingSystem,
  required Map<String, String> environment,
  required bool Function(String path) exists,
}) {
  final candidates = [
    ?environment['CHROME_EXECUTABLE'],
    if (operatingSystem == 'macos')
      for (final app in [
        'Google Chrome',
        'Chromium',
        'Microsoft Edge',
        'Brave Browser',
      ])
        '/Applications/$app.app/Contents/MacOS/$app',
    if (operatingSystem == 'windows')
      for (final root in ['PROGRAMFILES', 'PROGRAMFILES(X86)', 'LOCALAPPDATA'])
        if (environment[root] case final folder?) ...[
          '$folder\\Google\\Chrome\\Application\\chrome.exe',
          '$folder\\Microsoft\\Edge\\Application\\msedge.exe',
        ],
    if (operatingSystem == 'linux')
      for (final folder in (environment['PATH'] ?? '').split(':'))
        for (final name in [
          'google-chrome',
          'google-chrome-stable',
          'chromium',
          'chromium-browser',
          'microsoft-edge',
        ])
          '$folder/$name',
  ];
  return candidates.where(exists).firstOrNull;
}

/// Prints [htmlPath] to [pdfPath] with a headless [browser]. Returns null on
/// success, otherwise what went wrong.
Future<String?> printToPdf(
  String browser,
  String htmlPath,
  String pdfPath,
) async {
  // A profile of its own: a browser the user has open is left alone.
  final profile = Directory.systemTemp.createTempSync('qa_report_browser');
  try {
    final process = await Process.start(browser, [
      '--headless',
      '--disable-gpu',
      '--no-first-run',
      '--user-data-dir=${profile.path}',
      '--no-pdf-header-footer',
      '--print-to-pdf=${File(pdfPath).absolute.path}',
      '${File(htmlPath).absolute.uri}',
    ]);
    unawaited(process.stdout.drain<void>());
    unawaited(process.stderr.drain<void>());
    final code = await process.exitCode.timeout(
      const Duration(seconds: 90),
      onTimeout: () {
        process.kill();
        return -1;
      },
    );
    final pdf = File(pdfPath);
    if (code == 0 && pdf.existsSync() && pdf.lengthSync() > 0) return null;
    return code == -1
        ? 'the browser did not finish in 90 seconds'
        : 'the browser exited with code $code';
  } on ProcessException catch (problem) {
    return problem.message;
  } finally {
    try {
      profile.deleteSync(recursive: true);
    } on FileSystemException {
      // The browser may still be letting go of it; a temp folder can stay.
    }
  }
}

Future<void> main(List<String> argv) async {
  if (argv.length != 1 || argv.single.startsWith('-')) {
    stderr.writeln(usage);
    exitCode = 64;
    return;
  }
  final source = File(argv.single);
  if (!source.existsSync()) {
    stderr.writeln('${source.path} does not exist.');
    exitCode = 64;
    return;
  }

  final Object? report;
  try {
    report = jsonDecode(source.readAsStringSync());
  } on FormatException catch (problem) {
    stderr.writeln('${source.path} is not valid JSON: ${problem.message}');
    exitCode = 1;
    return;
  }
  if (report is! Map<String, dynamic>) {
    stderr.writeln('${source.path} must hold one JSON object.');
    exitCode = 1;
    return;
  }
  final problems = problemsIn(report);
  if (problems.isNotEmpty) {
    stderr.writeln('The report is incomplete:\n  ${problems.join('\n  ')}');
    exitCode = 1;
    return;
  }

  final missing = <String>[];
  final html = renderReport(
    report,
    image: (name) {
      final file = File('${source.parent.path}/$name');
      if (file.existsSync()) return file.readAsBytesSync();
      missing.add(name);
      return null;
    },
  );
  final base = source.path.replaceFirst(RegExp(r'\.json$'), '');
  File('$base.html').writeAsStringSync(html);
  stdout.writeln(
    'wrote $base.html (${(report['defects'] as List).length} defects)',
  );
  for (final name in missing) {
    stdout.writeln('screenshot not found: $name');
  }

  final browser = findBrowser(
    operatingSystem: Platform.operatingSystem,
    environment: Platform.environment,
    exists: (path) => File(path).existsSync(),
  );
  final failure = browser == null
      ? 'no Chrome, Chromium, Edge or Brave was found'
      : await printToPdf(browser, '$base.html', '$base.pdf');
  stdout.writeln(
    failure == null
        ? 'wrote $base.pdf'
        : 'no PDF: $failure. Open $base.html in a browser and print it to PDF.',
  );
}
