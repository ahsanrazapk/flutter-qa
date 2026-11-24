// Checks the shape of a Flutter project's lib/ folder: imports that cross a
// layer boundary, import cycles between modules, oversized files, and test
// coverage per module. Dart SDK only: run with `dart arch_check.dart`.
import 'dart:convert';
import 'dart:io';

const usage = '''
Usage: dart arch_check.dart [options]

  --project DIR       Flutter project root (default: current directory)
  --forbid FROM=TO    add a rule: files in folder FROM must not import folder
                      TO, or a URI starting with TO (e.g. domain=package:dio/).
                      Repeatable. Replaces the default rules.
  --max-lines N       report files longer than N lines (default 400)
  --min-coverage N    fail when total line coverage is below N percent

Default rules, applied to the folders a project actually has:
  domain must not import data, presentation, ui or Flutter's widget libraries
  data must not import presentation or ui

Coverage is read from coverage/lcov.info (flutter test --coverage).
Exits 1 on a boundary violation, a cycle, or coverage below --min-coverage.''';

const defaultRules = [
  (from: 'domain', to: 'data'),
  (from: 'domain', to: 'presentation'),
  (from: 'domain', to: 'ui'),
  (from: 'domain', to: 'package:flutter/material.dart'),
  (from: 'domain', to: 'package:flutter/cupertino.dart'),
  (from: 'domain', to: 'package:flutter/widgets.dart'),
  (from: 'data', to: 'presentation'),
  (from: 'data', to: 'ui'),
];

typedef Rule = ({String from, String to});
typedef Import = ({int line, String uri});

/// The import and export directives of a Dart file.
List<Import> parseImports(String source) {
  final directive = RegExp('''^\\s*(?:import|export)\\s+['"]([^'"]+)['"]''');
  return [
    for (final (index, line) in const LineSplitter().convert(source).indexed)
      if (directive.firstMatch(line) case final match?)
        (line: index + 1, uri: match.group(1)!),
  ];
}

/// Where an import leads: a path under lib/ for the project's own files,
/// otherwise the URI unchanged.
String resolveImport(
  String uri, {
  required String from,
  required String package,
}) {
  if (uri.startsWith('package:$package/')) {
    return 'lib/${uri.substring('package:$package/'.length)}';
  }
  if (uri.contains(':')) return uri;
  final parts = from.split('/')..removeLast();
  for (final part in uri.split('/')) {
    if (part == '..') {
      if (parts.isNotEmpty) parts.removeLast();
    } else if (part != '.') {
      parts.add(part);
    }
  }
  return parts.join('/');
}

/// The unit cycles are reported between: the first folder under lib/, or the
/// first two when that folder only groups others (lib/features/cart).
String moduleOf(String path) {
  final parts = path.split('/').skip(1).toList(); // drop "lib"
  if (parts.length == 1) return '(lib root)';
  const groups = {'features', 'modules', 'src', 'packages'};
  final depth = groups.contains(parts.first) && parts.length > 2 ? 2 : 1;
  return parts.take(depth).join('/');
}

bool _inFolder(String path, String folder) => path.split('/').contains(folder);

/// The rule an import breaks, if any.
Rule? brokenRule(String file, String target, List<Rule> rules) {
  for (final rule in rules) {
    if (!_inFolder(file, rule.from)) continue;
    final hit = rule.to.contains(':')
        ? target.startsWith(rule.to)
        : target.startsWith('lib/') && _inFolder(target, rule.to);
    if (hit) return rule;
  }
  return null;
}

/// Groups of nodes that can all reach each other (Tarjan's algorithm).
List<List<String>> findCycles(Map<String, Set<String>> graph) {
  final index = <String, int>{};
  final low = <String, int>{};
  final stack = <String>[];
  final cycles = <List<String>>[];
  void visit(String node) {
    index[node] = low[node] = index.length;
    stack.add(node);
    for (final next in graph[node] ?? const <String>{}) {
      if (!index.containsKey(next)) {
        visit(next);
        low[node] = low[node]! < low[next]! ? low[node]! : low[next]!;
      } else if (stack.contains(next)) {
        low[node] = low[node]! < index[next]! ? low[node]! : index[next]!;
      }
    }
    if (low[node] != index[node]) return;
    final group = <String>[];
    while (true) {
      final member = stack.removeLast();
      group.add(member);
      if (member == node) break;
    }
    if (group.length > 1) cycles.add(group..sort());
  }

  for (final node in graph.keys.toList()..sort()) {
    if (!index.containsKey(node)) visit(node);
  }
  return cycles;
}

/// Lines found and lines hit, per source file, from an lcov report.
Map<String, ({int found, int hit})> parseLcov(String lcov) {
  final coverage = <String, ({int found, int hit})>{};
  String? file;
  var found = 0;
  var hit = 0;
  for (final line in const LineSplitter().convert(lcov)) {
    if (line.startsWith('SF:')) {
      file = line.substring(3).replaceAll(r'\', '/');
      found = hit = 0;
    } else if (line.startsWith('DA:')) {
      found++;
      if (!line.endsWith(',0')) hit++;
    } else if (line == 'end_of_record' && file != null) {
      coverage[file] = (found: found, hit: hit);
    }
  }
  return coverage;
}

bool _generated(String path) =>
    RegExp(r'\.(g|freezed|gr|mocks|config)\.dart$').hasMatch(path) ||
    path.contains('/generated/') ||
    path.contains('/l10n/');

class Report {
  final violations = <String>[];
  final cycles = <String>[];
  final largeFiles = <String>[];
  final coverage = <String>[];
  double? totalCoverage;
}

Report check(
  String project, {
  List<Rule> rules = defaultRules,
  int maxLines = 400,
}) {
  final pubspec = File('$project/pubspec.yaml');
  if (!pubspec.existsSync()) {
    throw FormatException('$project has no pubspec.yaml.');
  }
  final package = RegExp(
    r'^name:\s*(\S+)',
    multiLine: true,
  ).firstMatch(pubspec.readAsStringSync())!.group(1)!;
  final lib = Directory('$project/lib');
  final sources = <String, String>{
    for (final entity in lib.listSync(recursive: true))
      if (entity is File && entity.path.endsWith('.dart'))
        entity.path.substring(project.length + 1).replaceAll(r'\', '/'): entity
            .readAsStringSync(),
  }..removeWhere((path, _) => _generated(path));

  final report = Report();
  final moduleGraph = <String, Set<String>>{};
  final crossings = <String, String>{}; // "a -> b" to one import that does it
  for (final file in sources.keys.toList()..sort()) {
    final module = moduleOf(file);
    moduleGraph.putIfAbsent(module, () => {});
    for (final import in parseImports(sources[file]!)) {
      final target = resolveImport(import.uri, from: file, package: package);
      final rule = brokenRule(file, target, rules);
      if (rule != null) {
        report.violations.add(
          '$file:${import.line} imports ${import.uri} '
          '(${rule.from} must not depend on ${rule.to})',
        );
      }
      if (!target.startsWith('lib/')) continue;
      final other = moduleOf(target);
      if (other == module) continue;
      moduleGraph[module]!.add(other);
      crossings.putIfAbsent('$module -> $other', () => '$file:${import.line}');
    }
    final lines = const LineSplitter().convert(sources[file]!).length;
    if (lines > maxLines) report.largeFiles.add('$file ($lines lines)');
  }

  for (final cycle in findCycles(moduleGraph)) {
    final proof = [
      for (final a in cycle)
        for (final b in cycle)
          if (crossings['$a -> $b'] case final where?) '  $a -> $b at $where',
    ];
    report.cycles.add('${cycle.join(' <-> ')}\n${proof.join('\n')}');
  }

  final lcov = File('$project/coverage/lcov.info');
  if (lcov.existsSync()) {
    final measured = parseLcov(lcov.readAsStringSync());
    final perModule = <String, ({int found, int hit})>{};
    final untouched = <String>[];
    for (final file in sources.keys) {
      // A file no test loads is missing from lcov altogether: count its
      // lines as uncovered, or it would hide.
      final lines = measured[file];
      final found = lines?.found ?? _codeLines(sources[file]!);
      if (lines == null && found > 0) untouched.add(file);
      final sum = perModule[moduleOf(file)] ?? (found: 0, hit: 0);
      perModule[moduleOf(file)] = (
        found: sum.found + found,
        hit: sum.hit + (lines?.hit ?? 0),
      );
    }
    var found = 0;
    var hit = 0;
    for (final module in perModule.keys.toList()..sort()) {
      final sum = perModule[module]!;
      found += sum.found;
      hit += sum.hit;
      report.coverage.add('${_percent(sum.hit, sum.found)}  $module');
    }
    for (final file in untouched..sort()) {
      report.coverage.add('  0%  $file (no test loads this file)');
    }
    report.totalCoverage = found == 0 ? 100 : 100 * hit / found;
  }
  return report;
}

/// A rough count of executable lines, for files lcov knows nothing about.
int _codeLines(String source) => const LineSplitter()
    .convert(source)
    .map((line) => line.trim())
    .where(
      (line) =>
          line.endsWith(';') &&
          !line.startsWith('import ') &&
          !line.startsWith('export ') &&
          !line.startsWith('part ') &&
          !line.startsWith('//'),
    )
    .length;

String _percent(int hit, int found) =>
    '${found == 0 ? 100 : (100 * hit / found).round()}%'.padLeft(4);

void main(List<String> argv) {
  var project = '.';
  var maxLines = 400;
  double? minCoverage;
  final rules = <Rule>[];
  for (var i = 0; i < argv.length; i += 2) {
    final value = i + 1 < argv.length ? argv[i + 1] : null;
    switch (argv[i]) {
      case '--project' when value != null:
        project = value;
      case '--max-lines' when int.tryParse(value ?? '') != null:
        maxLines = int.parse(value!);
      case '--min-coverage' when double.tryParse(value ?? '') != null:
        minCoverage = double.parse(value!);
      case '--forbid' when value != null && value.contains('='):
        final split = value.indexOf('=');
        rules.add((
          from: value.substring(0, split),
          to: value.substring(split + 1),
        ));
      default:
        stderr.writeln(usage);
        exitCode = 64;
        return;
    }
  }

  final Report report;
  try {
    report = check(
      project,
      rules: rules.isEmpty ? defaultRules : rules,
      maxLines: maxLines,
    );
  } on FormatException catch (problem) {
    stderr.writeln(problem.message);
    exitCode = 64;
    return;
  }

  void section(String title, List<String> lines, {String empty = 'none'}) {
    stdout.writeln('$title: ${lines.isEmpty ? empty : ''}');
    for (final line in lines) {
      stdout.writeln('  ${line.replaceAll('\n', '\n  ')}');
    }
  }

  section('Boundary violations', report.violations);
  section('Import cycles between modules', report.cycles);
  section('Files over $maxLines lines', report.largeFiles);
  final total = report.totalCoverage;
  section(
    total == null
        ? 'Line coverage'
        : 'Line coverage ${total.toStringAsFixed(1)}% by module',
    report.coverage,
    empty: 'no coverage/lcov.info; run `flutter test --coverage` first',
  );

  final tooLow = minCoverage != null && (total ?? 0) < minCoverage;
  if (tooLow) stdout.writeln('Coverage is below the required $minCoverage%.');
  if (report.violations.isNotEmpty || report.cycles.isNotEmpty || tooLow) {
    exitCode = 1;
  }
}
