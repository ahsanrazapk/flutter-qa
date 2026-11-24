// Self-tests for the plugin's architecture checker.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../../skills/reviewing-flutter-architecture/scripts/arch_check.dart';

void main() {
  test('parseImports reads imports and exports with their line numbers', () {
    const source = '''
// import 'commented.dart';
import 'dart:io';
import "package:shop/domain/cart.dart" show Cart;
export 'src/api.dart';
part 'cart.g.dart';
''';
    expect(parseImports(source), [
      (line: 2, uri: 'dart:io'),
      (line: 3, uri: 'package:shop/domain/cart.dart'),
      (line: 4, uri: 'src/api.dart'),
    ]);
  });

  test('resolveImport maps own-package and relative imports to lib paths', () {
    String resolve(String uri) => resolveImport(
      uri,
      from: 'lib/features/cart/ui/page.dart',
      package: 'shop',
    );
    expect(resolve('package:shop/domain/cart.dart'), 'lib/domain/cart.dart');
    expect(resolve('../data/repo.dart'), 'lib/features/cart/data/repo.dart');
    expect(
      resolve('widgets/row.dart'),
      'lib/features/cart/ui/widgets/row.dart',
    );
    expect(resolve('package:dio/dio.dart'), 'package:dio/dio.dart');
    expect(resolve('dart:io'), 'dart:io');
  });

  test('moduleOf groups by feature under a grouping folder', () {
    expect(moduleOf('lib/main.dart'), '(lib root)');
    expect(moduleOf('lib/domain/cart.dart'), 'domain');
    expect(moduleOf('lib/features/cart/ui/page.dart'), 'features/cart');
    expect(moduleOf('lib/features/shared.dart'), 'features');
  });

  test('brokenRule spots folder and package boundaries', () {
    const rules = defaultRules;
    expect(brokenRule('lib/domain/cart.dart', 'lib/data/repo.dart', rules), (
      from: 'domain',
      to: 'data',
    ));
    expect(
      brokenRule(
        'lib/features/cart/domain/cart.dart',
        'package:flutter/material.dart',
        rules,
      )?.to,
      'package:flutter/material.dart',
    );
    expect(brokenRule('lib/domain/a.dart', 'lib/domain/b.dart', rules), isNull);
    expect(
      brokenRule('lib/presentation/a.dart', 'lib/data/b.dart', rules),
      isNull,
    );
    // foundation is not a widget library.
    expect(
      brokenRule('lib/domain/a.dart', 'package:flutter/foundation.dart', rules),
      isNull,
    );
  });

  test('findCycles returns only groups that depend on each other', () {
    expect(
      findCycles({
        'a': {'b'},
        'b': {'c'},
        'c': {'a'},
        'd': {'a'},
        'e': {},
      }),
      [
        ['a', 'b', 'c'],
      ],
    );
    expect(
      findCycles({
        'a': {'b'},
        'b': {},
      }),
      isEmpty,
    );
  });

  test('parseLcov counts found and hit lines per file', () {
    const lcov = '''
SF:lib/domain/cart.dart
DA:3,2
DA:4,0
DA:9,10
LF:3
LH:2
end_of_record
SF:lib\\data\\repo.dart
DA:1,0
end_of_record
''';
    expect(parseLcov(lcov), {
      'lib/domain/cart.dart': (found: 3, hit: 2),
      'lib/data/repo.dart': (found: 1, hit: 0),
    });
  });

  group('check', () {
    late Directory project;

    void write(String path, String content) => File('${project.path}/$path')
      ..createSync(recursive: true)
      ..writeAsStringSync(content);

    setUp(() {
      project = Directory.systemTemp.createTempSync('arch_check_test');
      write('pubspec.yaml', 'name: shop\n');
    });
    tearDown(() => project.deleteSync(recursive: true));

    test('passes a cleanly layered project', () {
      write('lib/domain/cart.dart', 'class Cart {}\n');
      write('lib/data/repo.dart', "import '../domain/cart.dart';\n");
      write(
        'lib/presentation/page.dart',
        "import 'package:flutter/material.dart';\n"
            "import 'package:shop/domain/cart.dart';\n",
      );
      final report = check(project.path);
      expect(report.violations, isEmpty);
      expect(report.cycles, isEmpty);
      expect(report.totalCoverage, isNull);
    });

    test('reports a boundary violation with file and line', () {
      write('lib/domain/cart.dart', "// header\nimport '../data/repo.dart';\n");
      write('lib/data/repo.dart', '');
      expect(check(project.path).violations, [
        "lib/domain/cart.dart:2 imports ../data/repo.dart "
            '(domain must not depend on data)',
      ]);
    });

    test('reports a cycle between features with the imports that form it', () {
      write('lib/features/cart/a.dart', "import '../pay/b.dart';\n");
      write(
        'lib/features/pay/b.dart',
        "import 'package:shop/features/cart/a.dart';\n",
      );
      final cycles = check(project.path).cycles;
      expect(cycles.single, contains('features/cart <-> features/pay'));
      expect(cycles.single, contains('lib/features/cart/a.dart:1'));
      expect(cycles.single, contains('lib/features/pay/b.dart:1'));
    });

    test('custom rules replace the defaults', () {
      write('lib/domain/cart.dart', "import 'package:dio/dio.dart';\n");
      final report = check(
        project.path,
        rules: [(from: 'domain', to: 'package:dio/')],
      );
      expect(report.violations.single, contains('package:dio/dio.dart'));
    });

    test('flags long files and skips generated ones', () {
      write('lib/big.dart', 'var x = 1;\n' * 12);
      write('lib/model.g.dart', 'var x = 1;\n' * 12);
      expect(check(project.path, maxLines: 10).largeFiles, [
        'lib/big.dart (12 lines)',
      ]);
    });

    test('coverage counts files that no test ever loaded', () {
      write('lib/domain/cart.dart', 'int total() {\n  return 1;\n}\n');
      write('lib/data/repo.dart', 'int load() {\n  return 2;\n}\n');
      write(
        'coverage/lcov.info',
        'SF:lib/domain/cart.dart\nDA:1,1\nDA:2,1\nend_of_record\n',
      );
      final report = check(project.path);
      expect(report.coverage, [
        '  0%  data',
        '100%  domain',
        '  0%  lib/data/repo.dart (no test loads this file)',
      ]);
      // 2 of 3 lines: the unloaded file's one statement counts against it.
      expect(report.totalCoverage, closeTo(66.7, 0.1));
    });
  });
}
