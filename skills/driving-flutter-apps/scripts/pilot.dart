// The host half of the pilot: starts a Flutter debug session and drives it
// through the bridge (pilot_bridge.dart) over the Dart VM service.
// Dart SDK only: run it with `dart pilot.dart <command>`.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

const usage = r'''
Usage: dart pilot.dart <command> [target] [options]

Session
  start [-d DEVICE] [--target lib/main.dart] [-- flutter run args]
                         build and launch the app with the bridge, wait for it
  ready                  wait for a session that is still starting
  stop                   quit the app and end the session
  reload | restart       hot reload | hot restart after a code change

Look
  snapshot [--json] [--changed BASE]
                         what is on screen: one line per element, with [ref].
                         --changed marks the elements built by lines of lib/
                         that differ from a git commit or branch, e.g. main
  shot [FILE.png]        screenshot of the Flutter UI, 1 px per logical pixel
  wait TARGET [--gone]   wait until a widget is on screen (or gone)
  errors                 exceptions the app threw since the last command

Act (each prints the new snapshot; --quiet turns that off)
  tap TARGET [--long | --double]
  type TEXT [TARGET] [--submit]    replace a text field's content
  scroll [TARGET] --dx N --dy N    drag; --dy -300 moves the content up
  swipe [TARGET] --dx N --dy N     the same, ending in a flick
  scroll-to TARGET [--up]          scroll the main list until TARGET is built
  back                             what the system back button does

Flows
  run FILE               run commands from a file, one per line. Stops at the
                         first failure or app error. ${NAME} reads the environment.

TARGET is one of
  12             a [ref] from the last snapshot
  --text S       exact visible text        --contains S   part of the text
  --key S        Key('S')                  --tooltip S    tooltip message
  --label S      semantics label           --type S       widget class name
  --at X,Y       a point in logical pixels (tap, scroll, swipe)
  --index N      which match, top to bottom, when several match

Options
  --project DIR  Flutter project root (default: current directory)
  --timeout N    seconds to wait (default 10; start and ready: 100)''';

/// A failure whose message is everything the caller needs to see.
class Fail implements Exception {
  Fail(this.message);
  final String message;
}

const _finders = ['text', 'contains', 'key', 'tooltip', 'label', 'type'];
const _valueOptions = [
  ..._finders,
  'at',
  'index',
  'dx',
  'dy',
  'project',
  'timeout',
  'target',
  'device',
  'changed',
];
const _switches = ['gone', 'json', 'quiet', 'long', 'double', 'submit', 'up'];

class Args {
  final positional = <String>[];
  final options = <String, String>{};

  /// Everything after a bare `--`, handed to `flutter run` untouched.
  final passthrough = <String>[];

  bool has(String name) => options.containsKey(name);
}

Args parseArgs(List<String> argv) {
  final args = Args();
  for (var i = 0; i < argv.length; i++) {
    final arg = argv[i];
    if (arg == '--') {
      args.passthrough.addAll(argv.skip(i + 1));
      break;
    }
    final name = arg == '-d'
        ? 'device'
        : arg.substring(arg.startsWith('--') ? 2 : 0);
    if (arg != '-d' && !arg.startsWith('--')) {
      args.positional.add(arg);
    } else if (_switches.contains(name)) {
      args.options[name] = 'true';
    } else if (_valueOptions.contains(name)) {
      if (i + 1 >= argv.length) throw Fail('Option $arg needs a value.');
      args.options[name] = argv[++i];
    } else {
      throw Fail(
        'Unknown option $arg. Run pilot.dart with no arguments for help.',
      );
    }
  }
  return args;
}

/// Splits a flow line the way a shell would: spaces separate, quotes group,
/// `#` starts a comment.
List<String> splitLine(String line) {
  final tokens = <String>[];
  final current = StringBuffer();
  String? quote;
  var inToken = false;
  for (final char in line.split('')) {
    if (quote != null) {
      char == quote ? quote = null : current.write(char);
    } else if (char == '"' || char == "'") {
      quote = char;
      inToken = true;
    } else if (char == ' ' || char == '\t') {
      if (inToken) tokens.add(current.toString());
      current.clear();
      inToken = false;
    } else if (char == '#' && !inToken) {
      break;
    } else {
      current.write(char);
      inToken = true;
    }
  }
  if (quote != null) throw Fail('Unclosed $quote quote.');
  if (inToken) tokens.add(current.toString());
  return tokens;
}

/// Replaces `${NAME}` with the environment's value, so that flows can use
/// credentials without storing them.
String expandEnv(String text, Map<String, String> environment) =>
    text.replaceAllMapped(RegExp(r'\$\{(\w+)\}'), (match) {
      final name = match.group(1)!;
      return environment[name] ??
          (throw Fail('The environment variable $name is not set.'));
    });

/// The bridge parameters that name what a command acts on.
Map<String, String> targetOf(Args args, {int skip = 1}) {
  final target = <String, String>{};
  final ref = args.positional.skip(skip).firstOrNull;
  if (ref != null) {
    if (int.tryParse(ref) == null) {
      throw Fail('"$ref" is not a ref. Refs are the [numbers] in a snapshot.');
    }
    target['ref'] = ref;
  }
  for (final name in [..._finders, 'at', 'index']) {
    if (args.options[name] case final value?) target[name] = value;
  }
  final named = target.keys.where((key) => key != 'index').toList();
  if (named.length > 1) {
    throw Fail('Give one target, not ${named.length}: ${named.join(', ')}.');
  }
  return target;
}

const _states = {
  'isChecked': 'checked',
  'isCheckStateMixed': 'mixed',
  'isToggled': 'on',
  'isSelected': 'selected',
  'isFocused': 'focused',
  'isObscured': 'obscured',
  'isReadOnly': 'read-only',
  'isExpanded': 'expanded',
  'isRequired': 'required',
};

/// Actions worth showing; tapping, scrolling and text editing are implied by
/// the role.
const _shownActions = {
  'longPress': 'long-press',
  'increase': 'increase',
  'decrease': 'decrease',
  'dismiss': 'dismiss',
};

String _role(List<String> flags, List<String> actions) {
  bool flag(String name) => flags.contains(name);
  if (flag('isTextField')) return 'textfield';
  if (flag('isButton')) return 'button';
  if (flag('isLink')) return 'link';
  if (flag('isSlider')) return 'slider';
  if (flag('hasToggledState')) return 'switch';
  if (flag('hasCheckedState')) {
    return flag('isInMutuallyExclusiveGroup') ? 'radio' : 'checkbox';
  }
  if (flag('isImage')) return 'image';
  if (flag('isHeader')) return 'header';
  if (actions.any((action) => action.startsWith('scroll'))) return 'scrollable';
  if (actions.contains('tap')) return 'tappable';
  return 'text';
}

/// One line of a snapshot, e.g.
/// `[7] button "Sign in" (disabled)  <- FilledButton key=sign_in lib/login.dart:70`
String renderNode(Map<String, dynamic> node) {
  final flags = (node['flags'] as List? ?? const []).cast<String>();
  final actions = (node['actions'] as List? ?? const []).cast<String>();
  final role = _role(flags, actions);
  final notes = [
    if (flags.contains('hasEnabledState') && !flags.contains('isEnabled'))
      'disabled',
    if (role == 'switch' && !flags.contains('isToggled')) 'off',
    for (final state in _states.entries)
      if (flags.contains(state.key)) state.value,
    for (final action in _shownActions.entries)
      if (actions.contains(action.key)) action.value,
    if (node['scroll'] case [final int at, final int max])
      'scrolled $at of ${max < 0 ? 'endless' : max}',
    if (node['offscreen'] == true) 'off screen',
  ];
  final tooltip = node['tooltip'];
  final origin = [
    ?node['widget'],
    if (node['key'] case final key?) 'key=$key',
    ?node['src'],
  ].join(' ');
  final line = [
    '[${node['ref']}]',
    role,
    if (node['label'] case final label?) jsonEncode(label),
    if (node['value'] case final value?) '= ${jsonEncode(value)}',
    if (node['hint'] case final hint?) 'hint ${jsonEncode(hint)}',
    if (tooltip != null && tooltip != node['label'])
      'tooltip ${jsonEncode(tooltip)}',
    if (node['id'] case final id?) 'id=$id',
    if (notes.isNotEmpty) '(${notes.join(', ')})',
    if (origin.isNotEmpty) ' <- $origin',
    if (node['changed'] == true) ' *changed*',
  ].join(' ');
  return '${'  ' * (node['depth'] as int? ?? 0)}$line';
}

String renderSnapshot(Map<String, dynamic> snapshot) {
  final size = snapshot['size'] as List;
  final nodes = snapshot['nodes'] as List;
  return [
    'screen ${size[0]}x${size[1]}'
        '${snapshot['route'] == null ? '' : '  route ${snapshot['route']}'}',
    for (final node in nodes) renderNode(node as Map<String, dynamic>),
    if (nodes.isEmpty)
      '(nothing is on screen: the app is showing a blank page)',
    if (snapshot['changed'] case final Map changed)
      ..._renderChanged(
        changed,
        nodes.where((node) => (node as Map)['changed'] == true).length,
      ),
  ].join('\n');
}

/// The lines under a snapshot that say how much of a change it shows.
List<String> _renderChanged(Map<dynamic, dynamic> changed, int marked) {
  final base = changed['base'];
  if (changed['files'] == 0) return ['changed since $base: nothing in lib/'];
  final elsewhere = (changed['elsewhere'] as Map).entries.toList();
  const shown = 10;
  return [
    'changed since $base: $marked of these elements'
        '${elsewhere.isEmpty ? '' : '. Changed, but no widget on this screen:'}',
    for (final entry in elsewhere.take(shown)) '  ${entry.key}:${entry.value}',
    if (elsewhere.length > shown)
      '  and ${elsewhere.length - shown} more files',
  ];
}

/// The lines each file gained or had rewritten, read from the output of
/// `git diff -U0`: `{'lib/cart.dart': [(12, 18), (40, 40)]}`.
Map<String, List<(int, int)>> changedLines(String diff) {
  final changed = <String, List<(int, int)>>{};
  final hunk = RegExp(r'^@@ -\S+ \+(\d+)(?:,(\d+))? @@');
  List<(int, int)>? ranges;
  for (final line in const LineSplitter().convert(diff)) {
    if (line.startsWith('+++ b/')) {
      ranges = changed[line.substring(6)] = [];
    } else if (line == '+++ /dev/null') {
      ranges = null; // a deleted file has no line left to find on screen
    } else if (hunk.firstMatch(line) case final match?) {
      final start = int.parse(match[1]!);
      final count = int.parse(match[2] ?? '1');
      // A hunk that only removes lines sits just after line [start].
      final first = start == 0 ? 1 : start;
      ranges?.add((first, count == 0 ? first : start + count - 1));
    }
  }
  return changed;
}

/// The last line of the expression that opens on [line], counted from 1.
// shortcut: goes by indentation, so it needs `dart format` layout; match the
// brackets instead if hand-formatted code gets the wrong elements marked.
int _endOf(List<String> source, int line) {
  int indent(String text) => text.length - text.trimLeft().length;
  if (line > source.length) return line;
  final own = indent(source[line - 1]);
  var end = line;
  for (var next = line + 1; next <= source.length; next++) {
    final text = source[next - 1];
    if (text.trim().isEmpty) continue;
    final closes = indent(text) == own && ')]}'.contains(text.trimLeft()[0]);
    if (indent(text) <= own && !closes) break;
    end = next;
    if (closes) break;
  }
  return end;
}

/// `[12, 13, 14, 40]` as `12-14, 40`.
String _ranges(List<int> lines) {
  final ranges = <String>[];
  for (var i = 0; i < lines.length; i++) {
    final first = lines[i];
    while (i + 1 < lines.length && lines[i + 1] == lines[i] + 1) {
      i++;
    }
    ranges.add(first == lines[i] ? '$first' : '$first-${lines[i]}');
  }
  return ranges.join(', ');
}

/// Sets `changed` on the nodes of [snapshot] that the [changed] lines built,
/// and returns the changed lines that built no widget on screen, as
/// `{'lib/cart.dart': '12-18, 40'}`. [read] gives a file's lines.
///
/// A changed line belongs to the innermost widget whose constructor call it
/// lies in, among the widgets around the snapshot's nodes. Every node at or
/// under that widget is marked: a wrapper's new padding moves its children.
Map<String, String> markChanged(
  Map<String, dynamic> snapshot,
  Map<String, List<(int, int)>> changed,
  List<String> Function(String file) read,
) {
  final nodes = (snapshot['nodes'] as List).cast<Map<String, dynamic>>();
  Iterable<String> places(Map<String, dynamic> node) => [
    ?node['src'] as String?,
    ...(node['chain'] as List? ?? const []).cast<String>(),
  ];

  final owners = <String>{};
  final elsewhere = <String, String>{};
  for (final MapEntry(key: file, value: ranges) in changed.entries) {
    final source = read(file);
    // Where each widget of this file starts, and where its call ends.
    final spans = <int, int>{};
    for (final place in nodes.expand(places)) {
      final colon = place.lastIndexOf(':');
      if (place.substring(0, colon) != file) continue;
      final line = int.parse(place.substring(colon + 1));
      spans[line] ??= _endOf(source, line);
    }
    final loose = <int>[];
    for (final (first, last) in ranges) {
      for (var line = first; line <= last && line <= source.length; line++) {
        final around = [
          for (final span in spans.entries)
            if (span.key <= line && line <= span.value) span.key,
        ];
        if (around.isEmpty) {
          loose.add(line);
        } else {
          // Calls nest, so the one that starts last is the innermost.
          owners.add('$file:${around.reduce((a, b) => a > b ? a : b)}');
        }
      }
    }
    if (loose.isNotEmpty) elsewhere[file] = _ranges(loose);
  }
  for (final node in nodes) {
    if (places(node).any(owners.contains)) node['changed'] = true;
  }
  return elsewhere;
}

/// The lines of the app's own Dart code that differ from the commit where
/// its history left [base], uncommitted and untracked work included.
// shortcut: lib/ only, so a local package elsewhere in the repository is not
// followed; widen the pathspec when someone's widgets live outside lib/.
Map<String, List<(int, int)>> _changedSince(String project, String base) {
  // The value goes to git as an argument; an option must not get through.
  if (base.startsWith('-')) throw Fail('--changed takes a branch or commit.');
  String git(List<String> arguments) {
    final ProcessResult result;
    try {
      result = Process.runSync('git', arguments, workingDirectory: project);
    } on ProcessException {
      throw Fail('--changed needs git on the PATH.');
    }
    if (result.exitCode != 0) {
      throw Fail('git ${arguments.first} failed: ${'${result.stderr}'.trim()}');
    }
    return '${result.stdout}';
  }

  const code = ['--', 'lib/*.dart'];
  final from = git(['merge-base', base, 'HEAD']).trim();
  final changed = changedLines(
    git([
      'diff',
      '-U0',
      '--relative',
      '--no-color',
      '--no-ext-diff',
      '--src-prefix=a/',
      '--dst-prefix=b/',
      from,
      ...code,
    ]),
  );
  final added = git(['ls-files', '--others', '--exclude-standard', ...code]);
  for (final file in const LineSplitter().convert(added)) {
    changed[file] = [(1, 1 << 30)]; // a new file: every line
  }
  return changed;
}

/// The app's package name, from its pubspec.
String packageName(String pubspec) =>
    RegExp(r'^name:\s*(\S+)', multiLine: true).firstMatch(pubspec)?.group(1) ??
    (throw Fail('pubspec.yaml has no name.'));

/// The entrypoint that installs the bridge and then runs the app's own main.
String entrypoint({
  required String package,
  required String target,
  required String targetSource,
}) {
  final import = target.startsWith('lib/')
      ? 'package:$package/${target.substring(4)}'
      : '../../$target';
  final takesArgs = RegExp(r'\bmain\(\s*List<String>').hasMatch(targetSource);
  return '''
// Generated by flutter-qa's pilot. Safe to delete.
import '$import' as app;

import 'pilot_bridge.dart';

void main() {
  installPilot();
  app.main(${takesArgs ? 'const <String>[]' : ''});
}
''';
}

/// The WebSocket address of a VM service given its http address.
Uri webSocketUri(String httpUri) {
  final uri = Uri.parse(httpUri.trim());
  final path = uri.path.endsWith('/') ? uri.path : '${uri.path}/';
  return uri.replace(scheme: 'ws', path: '${path}ws');
}

class Session {
  Session._(this._socket, this.project, this._root, this._package) {
    _socket.listen(
      (data) {
        final reply = jsonDecode(data as String) as Map<String, dynamic>;
        _pending.remove(reply['id'])?.complete(reply);
      },
      onDone: () {
        for (final waiter in _pending.values) {
          waiter.completeError(
            Fail('The app stopped while a command was running.'),
          );
        }
        _pending.clear();
      },
    );
  }

  final WebSocket _socket;
  final String project;
  final String _root;
  final String _package;
  final _pending = <String, Completer<Map<String, dynamic>>>{};
  var _nextId = 0;
  late String _isolateId;

  /// Exceptions the app reported while this session's commands ran.
  final appErrors = <String>[];

  static Future<Session> connect(String project) async {
    final file = File('${pilotDir(project)}/vmservice');
    if (!file.existsSync()) {
      throw Fail('No session is running. Start one with: pilot.dart start');
    }
    final WebSocket socket;
    try {
      socket = await WebSocket.connect(
        '${webSocketUri(file.readAsStringSync())}',
      );
    } on Exception {
      throw Fail('The app is not running any more. Start a new session.');
    }
    final root = Directory(Directory(project).resolveSymbolicLinksSync()).uri;
    final pubspec = File('$project/pubspec.yaml');
    final session = Session._(
      socket,
      project,
      '$root',
      pubspec.existsSync() ? packageName(pubspec.readAsStringSync()) : '',
    );
    try {
      await session.attach(DateTime.now());
      return session;
    } on Fail {
      await session.close();
      rethrow;
    }
  }

  /// Finds the isolate that runs the bridge. A hot restart replaces it, so
  /// this is repeated after one, retrying until [until].
  Future<void> attach(DateTime until) async {
    while (true) {
      final vm = await _call('getVM');
      for (final isolate in vm['isolates'] as List) {
        final id = (isolate as Map)['id'] as String;
        final info = await _call('getIsolate', {'isolateId': id});
        final extensions = info['extensionRPCs'] as List? ?? const [];
        if (extensions.contains('ext.pilot')) {
          _isolateId = id;
          return;
        }
      }
      if (DateTime.now().isAfter(until)) {
        throw Fail(
          'The app is running without the bridge. Start it with: pilot.dart start',
        );
      }
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
  }

  Future<void> close() => _socket.close();

  Future<Map<String, dynamic>> _call(
    String method, [
    Map<String, String> params = const {},
  ]) async {
    final id = '${_nextId++}';
    final waiter = _pending[id] = Completer<Map<String, dynamic>>();
    _socket.add(
      jsonEncode({
        'jsonrpc': '2.0',
        'id': id,
        'method': method,
        'params': params,
      }),
    );
    final reply = await waiter.future.timeout(
      const Duration(seconds: 30),
      onTimeout: () => throw Fail(
        'The app did not answer in 30 seconds. It may be paused on an '
        'exception or frozen: check .dart_tool/flutter_pilot/run.log.',
      ),
    );
    if (reply['error'] case final Map error) {
      throw Fail('$method failed: ${error['message']} ${error['data'] ?? ''}');
    }
    return reply['result'] as Map<String, dynamic>;
  }

  /// Sends one command to the bridge; null [until] means a single try.
  /// A widget that is not there yet is retried until [until].
  Future<Map<String, dynamic>> send(
    String command, [
    Map<String, String> params = const {},
    DateTime? until,
  ]) async {
    while (true) {
      final reply = await _call('ext.pilot', {
        ...params,
        'cmd': command,
        'root': _root,
        'isolateId': _isolateId,
      });
      for (final error in reply['errors'] as List? ?? const []) {
        // A stack frame names the app's files by package; show them as paths.
        appErrors.add('$error'.replaceAll('package:$_package/', 'lib/'));
      }
      if (reply['ok'] == true) return reply;
      final retry = reply['retry'] == true && until != null;
      if (!retry || DateTime.now().isAfter(until)) {
        throw Fail('${reply['error']}');
      }
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
  }
}

String pilotDir(String project) => '$project/.dart_tool/flutter_pilot';

int? _pid(String project, String name) {
  final file = File('${pilotDir(project)}/$name');
  return file.existsSync()
      ? int.tryParse(file.readAsStringSync().trim())
      : null;
}

/// Whether a process exists. SIGCONT does nothing to a process that is
/// running, and sending it needs no child process the way `kill -0` would.
bool _alive(int pid) => Platform.isWindows
    ? '${Process.runSync('tasklist', ['/FI', 'PID eq $pid']).stdout}'.contains(
        '$pid',
      )
    : Process.killPid(pid, ProcessSignal.sigcont);

String _logTail(String project, {int from = 0, int lines = 25}) {
  final log = File('${pilotDir(project)}/run.log');
  if (!log.existsSync()) return '';
  final text = utf8.decode(
    log.readAsBytesSync().skip(from).toList(),
    allowMalformed: true,
  );
  final all = const LineSplitter().convert(text);
  return all.skip(all.length > lines ? all.length - lines : 0).join('\n');
}

Future<void> _start(Args args, String project, Duration timeout) async {
  final pubspec = File('$project/pubspec.yaml');
  if (!pubspec.existsSync()) {
    throw Fail('$project is not a Flutter project: it has no pubspec.yaml.');
  }
  final config = File('$project/.dart_tool/package_config.json');
  if (!config.existsSync() ||
      !config.readAsStringSync().contains('"flutter_test"')) {
    throw Fail(
      'The bridge needs flutter_test, which every new Flutter project has as '
      'a dev dependency. Add it back and run `flutter pub get`:\n'
      '  flutter pub add "dev:flutter_test:{\\"sdk\\":\\"flutter\\"}"',
    );
  }
  final running = _pid(project, 'pid') ?? _pid(project, 'launcher.pid');
  if (running != null && _alive(running)) {
    throw Fail('A session is already running. Use it, or `stop` it first.');
  }

  final target = args.options['target'] ?? 'lib/main.dart';
  final targetFile = File('$project/$target');
  if (!targetFile.existsSync()) throw Fail('$target does not exist.');
  final dir = Directory(pilotDir(project))..createSync(recursive: true);
  File('${dir.path}/main.dart').writeAsStringSync(
    entrypoint(
      package: packageName(pubspec.readAsStringSync()),
      target: target,
      targetSource: targetFile.readAsStringSync(),
    ),
  );
  File.fromUri(Platform.script.resolve('pilot_bridge.dart'))
      .copySync('${dir.path}/pilot_bridge.dart');
  for (final stale in ['vmservice', 'pid', 'run.log']) {
    final file = File('${dir.path}/$stale');
    if (file.existsSync()) file.deleteSync();
  }

  final run = [
    'run',
    if (args.options['device'] case final device?) ...['-d', device],
    '-t',
    '.dart_tool/flutter_pilot/main.dart',
    '--vmservice-out-file=.dart_tool/flutter_pilot/vmservice',
    '--pid-file=.dart_tool/flutter_pilot/pid',
    ...args.passthrough,
  ];
  if (Platform.isWindows) {
    // shortcut: no detached launch on Windows; add one when it can be tested there.
    throw Fail(
      'On Windows, run this in the background yourself, then `ready`:\n'
      '  flutter ${run.join(' ')} > .dart_tool\\flutter_pilot\\run.log 2>&1',
    );
  }
  final process = await Process.start(
    '/bin/sh',
    [
      '-c',
      r'exec flutter "$@" > .dart_tool/flutter_pilot/run.log 2>&1',
      'flutter',
      ...run,
    ],
    workingDirectory: project,
    mode: ProcessStartMode.detached,
  );
  File('${dir.path}/launcher.pid').writeAsStringSync('${process.pid}');
  await _ready(project, timeout);
}

Future<void> _ready(String project, Duration timeout) async {
  final deadline = DateTime.now().add(timeout);
  final launcher = _pid(project, 'launcher.pid');
  while (true) {
    try {
      final session = await Session.connect(project);
      try {
        await session.send('ping');
      } finally {
        await session.close();
      }
      stdout.writeln('ready');
      return;
    } on Fail catch (failure) {
      if (launcher != null && !_alive(launcher)) {
        throw Fail(
          'flutter run exited before the app was up:\n${_logTail(project)}',
        );
      }
      if (DateTime.now().isAfter(deadline)) {
        // Once the app is up, the reason it cannot be driven is the news.
        final up = File('${pilotDir(project)}/vmservice').existsSync();
        throw Fail(
          'Not ready after ${timeout.inSeconds}s'
          '${up ? ': ${failure.message}' : '. A first build can take minutes'}. '
          'Run `ready` again. Last output:\n${_logTail(project, lines: 8)}',
        );
      }
      await Future<void>.delayed(const Duration(seconds: 1));
    }
  }
}

Future<void> _stop(String project) async {
  final pid = _pid(project, 'pid') ?? _pid(project, 'launcher.pid');
  if (pid != null && _alive(pid)) {
    Process.killPid(pid); // flutter run quits the app on SIGTERM
    for (var i = 0; i < 60 && _alive(pid); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    if (_alive(pid)) Process.killPid(pid, ProcessSignal.sigkill);
    stdout.writeln('stopped');
  } else {
    stdout.writeln('No session was running.');
  }
  for (final name in ['vmservice', 'pid', 'launcher.pid']) {
    final file = File('${pilotDir(project)}/$name');
    if (file.existsSync()) file.deleteSync();
  }
}

/// Asks `flutter run` for a hot reload or restart and reports what it said.
Future<String> _reload(
  String project,
  Duration timeout, {
  required bool restart,
}) async {
  if (Platform.isWindows) {
    throw Fail(
      'Hot reload by signal is not available on Windows: stop and start.',
    );
  }
  final pid = _pid(project, 'pid');
  if (pid == null || !_alive(pid)) throw Fail('No session is running.');
  final log = File('${pilotDir(project)}/run.log');
  final before = log.existsSync() ? log.lengthSync() : 0;
  Process.killPid(pid, restart ? ProcessSignal.sigusr2 : ProcessSignal.sigusr1);
  final deadline = DateTime.now().add(timeout);
  while (true) {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    final output = _logTail(project, from: before, lines: 40);
    if (RegExp(r'Reloaded \d+|Restarted application').hasMatch(output)) {
      return const LineSplitter().convert(output).last;
    }
    final failed = output.contains('Error:') || output.contains('rejected');
    if (failed || DateTime.now().isAfter(deadline)) {
      throw Fail('${restart ? 'Restart' : 'Reload'} did not finish:\n$output');
    }
  }
}

const _actions = {
  'tap': 'tap',
  'type': 'type',
  'scroll': 'scroll',
  'swipe': 'swipe',
  'scroll-to': 'scrollTo',
  'back': 'back',
};

/// Runs one command against a connected session and returns what to print.
Future<String> command(Session session, Args args, Duration timeout) async {
  final name = args.positional.first;
  final until = DateTime.now().add(timeout);
  switch (name) {
    case 'snapshot':
      final base = args.options['changed'];
      final changed = base == null
          ? null
          : _changedSince(session.project, base);
      final snapshot = await session.send('snapshot', {
        if (changed != null && changed.isNotEmpty)
          'files': changed.keys.join('\n'),
      }, until);
      if (changed != null) {
        snapshot['changed'] = {
          'base': base,
          'files': changed.length,
          'elsewhere': markChanged(snapshot, changed, (file) {
            final source = File('${session.project}/$file');
            return source.existsSync() ? source.readAsLinesSync() : const [];
          }),
        };
      }
      return args.has('json') ? jsonEncode(snapshot) : renderSnapshot(snapshot);
    case 'reload' || 'restart':
      final report = await _reload(
        session.project,
        timeout,
        restart: name == 'restart',
      );
      await session.attach(until);
      await session.send('ping', const {}, until);
      return report;
    case 'errors':
      await session.send('ping');
      return session.appErrors.isEmpty ? 'No app errors.' : '';
    case 'shot':
      // After the command: a file to write, a ref to frame, both or neither.
      final words = args.positional.skip(1);
      final refs = words.where((word) => int.tryParse(word) != null);
      final path =
          words.where((word) => int.tryParse(word) == null).firstOrNull ??
          '.dart_tool/flutter_pilot/shot.png';
      final reply = await session.send(
        'shot',
        targetOf(
          Args()
            ..positional.addAll(['shot', ...refs])
            ..options.addAll(args.options),
        ),
        until,
      );
      try {
        File(path)
          ..parent.createSync(recursive: true)
          ..writeAsBytesSync(base64Decode(reply['png'] as String));
      } on FileSystemException catch (problem) {
        throw Fail('Could not write $path: ${problem.osError?.message}.');
      }
      final hit = reply['hit'];
      final framed = hit is Map<String, dynamic>
          ? [', framed', ?hit['widget'], ?hit['src']].join(' ')
          : '';
      return 'saved $path$framed';
    case 'wait':
      final target = targetOf(args);
      if (target.isEmpty) throw Fail('wait needs a target.');
      final gone = args.has('gone');
      while (true) {
        final reply = await session.send('find', target);
        if ((reply['count'] as int > 0) != gone) return 'ok';
        if (DateTime.now().isAfter(until)) {
          throw Fail(
            'Timed out after ${timeout.inSeconds}s: it is '
            '${gone ? 'still on screen' : 'not on screen'}. '
            'Run `snapshot` to see what is.',
          );
        }
        await Future<void>.delayed(const Duration(milliseconds: 250));
      }
  }
  final bridgeCommand =
      _actions[name] ?? (throw Fail('Unknown command "$name".\n$usage'));
  final typing = name == 'type';
  if (typing && args.positional.length < 2)
    throw Fail('type needs the text to enter.');
  final reply = await session.send(bridgeCommand, {
    ...targetOf(args, skip: typing ? 2 : 1),
    if (typing) 'value': args.positional[1],
    if (args.has('long')) 'mode': 'long',
    if (args.has('double')) 'mode': 'double',
    for (final option in ['submit', 'up', 'dx', 'dy'])
      if (args.options[option] case final value?) option: value,
  }, until);
  // Name what the action landed on, so a wrong target is noticed at once.
  final hit = reply['hit'];
  final landed = hit is Map<String, dynamic>
      ? [
          ':',
          ?hit['widget'],
          if (hit['key'] case final key?) 'key=$key',
          ?hit['src'],
          'at ${(hit['at'] as List).join(',')}',
        ].join(' ')
      : '';
  final moving = reply['settled'] == false
      ? ' (the screen is still animating)'
      : '';
  if (args.has('quiet')) return 'ok$landed$moving';
  return 'ok$landed$moving\n${renderSnapshot(await session.send('snapshot'))}';
}

String _errorReport(Session session) {
  final errors = session.appErrors.toList();
  session.appErrors.clear();
  return [for (final error in errors) '! app error: $error'].join('\n');
}

/// Runs a flow file. Returns false at the first step that fails or that makes
/// the app throw.
Future<bool> runFlow(Session session, String path, Duration timeout) async {
  final file = File(path);
  if (!file.existsSync()) throw Fail('$path does not exist.');
  // Read every line before touching the app, so that a typo or a missing
  // environment variable does not leave a flow half run.
  final steps = <({String label, Args args})>[];
  for (final (index, line) in file.readAsLinesSync().indexed) {
    try {
      final tokens = [
        for (final token in splitLine(line))
          expandEnv(token, Platform.environment),
      ];
      if (tokens.isEmpty) continue;
      steps.add((
        label: '${index + 1}: ${line.trim()}',
        args: parseArgs([...tokens, '--quiet']),
      ));
    } on Fail catch (failure) {
      throw Fail('$path line ${index + 1}: ${failure.message}');
    }
  }

  await session.send('ping');
  session.appErrors.clear(); // errors from before the flow are not its fault
  for (final step in steps) {
    String problem;
    try {
      final seconds = int.tryParse(step.args.options['timeout'] ?? '');
      await command(
        session,
        step.args,
        seconds == null ? timeout : Duration(seconds: seconds),
      );
      problem = _errorReport(session);
    } on Fail catch (failure) {
      problem = [
        failure.message,
        _errorReport(session),
      ].where((s) => s.isNotEmpty).join('\n');
    }
    if (problem.isEmpty) {
      stdout.writeln('ok    ${step.label}');
      continue;
    }
    stdout.writeln('FAIL  ${step.label}\n$problem');
    try {
      stdout.writeln(renderSnapshot(await session.send('snapshot')));
      final shot =
          '${pilotDir(session.project)}/${file.uri.pathSegments.last}.failure.png';
      Map<String, dynamic> picture;
      try {
        // Frame what the step was aimed at, when it can still be found.
        final typing = step.args.positional.first == 'type';
        picture = await session.send(
          'shot',
          targetOf(step.args, skip: typing ? 2 : 1),
        );
      } on Fail {
        picture = await session.send('shot');
      }
      File(shot).writeAsBytesSync(base64Decode(picture['png'] as String));
      stdout.writeln('screenshot: $shot');
    } on Fail {
      // The app is gone; the step's own message already says why.
    }
    return false;
  }
  stdout.writeln('PASS  $path');
  return true;
}

Future<void> run(List<String> argv) async {
  final args = parseArgs(argv);
  if (args.positional.isEmpty) throw Fail(usage);
  final name = args.positional.first;
  final project = args.options['project'] ?? '.';
  final seconds = int.tryParse(args.options['timeout'] ?? '');
  if (args.has('timeout') && seconds == null)
    throw Fail('--timeout takes whole seconds.');
  final starting = name == 'start' || name == 'ready';
  final timeout = Duration(seconds: seconds ?? (starting ? 100 : 10));

  switch (name) {
    case 'start':
      return _start(args, project, timeout);
    case 'ready':
      return _ready(project, timeout);
    case 'stop':
      return _stop(project);
  }

  final session = await Session.connect(project);
  try {
    if (name == 'run') {
      final flow =
          args.positional.elementAtOrNull(1) ??
          (throw Fail('run needs a flow file.'));
      if (!await runFlow(session, flow, timeout)) exitCode = 1;
      return;
    }
    String output;
    try {
      output = await command(session, args, timeout);
    } on Fail catch (failure) {
      // Whatever the app threw is likely why the command failed.
      throw Fail(
        [
          failure.message,
          _errorReport(session),
        ].where((s) => s.isNotEmpty).join('\n'),
      );
    }
    final report = [output, _errorReport(session)].where((s) => s.isNotEmpty);
    stdout.writeln(report.join('\n'));
  } finally {
    await session.close();
  }
}

Future<void> main(List<String> argv) => runZonedGuarded(
  () async {
    try {
      await run(argv);
    } on Fail catch (failure) {
      stderr.writeln(failure.message);
      exitCode = 1;
    }
  },
  (error, stack) {
    // Writing to a reader that has gone, as in `pilot ... | head`, fails
    // later and outside any try. There is nobody left to tell.
    if (error is FileSystemException && (error.path ?? '').isEmpty) return;
    Error.throwWithStackTrace(error, stack);
  },
)!;
