// The in-app half of the pilot. pilot.dart copies this file next to a generated
// entrypoint in .dart_tool/flutter_pilot/, where it registers one VM service
// extension, ext.pilot, that inspects and drives the running app.
// Debug builds only. Uses nothing outside the Flutter SDK.
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Call first thing in main(), before the app's own main().
void installPilot() {
  _hookErrors();
  developer.registerExtension('ext.pilot', (method, params) async {
    // Apps often replace the error handlers in their own main().
    _hookErrors();
    final reply = await pilotCommand(params);
    reply['errors'] = _drainErrors(params['root'] ?? '');
    return developer.ServiceExtensionResponse.result(jsonEncode(reply));
  });
}

final _errors = <({String summary, String? where})>[];
FlutterExceptionHandler? _nextFlutterHandler;
ui.ErrorCallback? _nextPlatformHandler;

// The handlers that were in place before the app's main() ran. An app that
// installs its own handler often calls "the previous one", which is ours.
FlutterExceptionHandler? _firstFlutterHandler;
ui.ErrorCallback? _firstPlatformHandler;
var _hooked = false;
var _reporting = false;

void _hookErrors() {
  final dispatcher = ui.PlatformDispatcher.instance;
  if (!_hooked) {
    _firstFlutterHandler = FlutterError.onError;
    _firstPlatformHandler = dispatcher.onError;
    _hooked = true;
  }
  if (FlutterError.onError != _onFlutterError) {
    _nextFlutterHandler = FlutterError.onError;
    FlutterError.onError = _onFlutterError;
  }
  if (dispatcher.onError != _onPlatformError) {
    _nextPlatformHandler = dispatcher.onError;
    dispatcher.onError = _onPlatformError;
  }
}

void _onFlutterError(FlutterErrorDetails details) {
  if (_reporting) {
    // The app's handler passed the error back down the chain: finish the
    // chain with whatever was there first, instead of looping.
    (_firstFlutterHandler ?? FlutterError.presentError)(details);
    return;
  }
  _reporting = true;
  try {
    _record(
      '${details.summary}',
      errorLocation('$details', '${details.stack}'),
    );
    (_nextFlutterHandler ?? FlutterError.presentError)(details);
  } finally {
    _reporting = false;
  }
}

bool _onPlatformError(Object error, StackTrace stack) {
  if (_reporting) return _firstPlatformHandler?.call(error, stack) ?? false;
  _reporting = true;
  try {
    _record('$error', errorLocation('', '$stack'));
    return _nextPlatformHandler?.call(error, stack) ?? false;
  } finally {
    _reporting = false;
  }
}

/// Lets a test hook the error handlers the way a command does, and read what
/// they caught.
@visibleForTesting
void debugHookPilotErrors() => _hookErrors();

@visibleForTesting
List<String> debugDrainPilotErrors() => _drainErrors('');

/// Where in the app an error comes from: the widget a layout error blames,
/// or else the first stack frame that is neither Flutter's nor the bridge's.
String? errorLocation(String details, String stack) =>
    RegExp(r'error-causing widget was:[\s\S]*?(file://\S+?\.dart:\d+)')
        .firstMatch(details)
        ?.group(1) ??
    RegExp(r'\((package:(?!flutter/|flutter_test/)[^):]+:\d+)')
        .firstMatch(stack)
        ?.group(1);

void _record(String summary, String? where) {
  if (_errors.any((e) => e.summary == summary && e.where == where)) return;
  if (_errors.length == 50) _errors.removeAt(0);
  _errors.add((summary: summary, where: where));
}

List<String> _drainErrors(String root) {
  final drained = [
    for (final error in _errors)
      error.where == null
          ? error.summary
          : '${error.summary}  at ${_short(error.where!, root)}',
  ];
  _errors.clear();
  return drained;
}

/// [file] relative to the project [root] when it is inside it.
String _short(String file, String root) =>
    root.isNotEmpty && file.startsWith(root)
    ? file.substring(root.length)
    : file;

class _Failure implements Exception {
  _Failure(this.message, {this.retry = false});
  final String message;

  /// True when waiting a moment and asking again may succeed.
  final bool retry;
}

SemanticsHandle? _semantics;

/// Lets a test release what [pilotCommand] holds on to.
@visibleForTesting
void debugResetPilot() {
  _semantics?.dispose();
  _semantics = null;
  _errors.clear();
}

/// Runs one pilot command. Only tests pass a [controller].
Future<Map<String, Object?>> pilotCommand(
  Map<String, String> params, {
  WidgetController? controller,
}) async {
  try {
    final binding = WidgetsBinding.instance;
    if (binding.rootElement == null) {
      throw _Failure('The app has not called runApp yet.', retry: true);
    }
    final pilot = _Pilot(params, controller ?? _PilotController(binding));
    _semantics ??= SemanticsBinding.instance.ensureSemantics();
    // One frame before every command: it builds what the app has changed
    // since the last one, which nothing else does while the window is hidden.
    await pilot.controller.pump();
    return {'ok': true, ...await pilot.run()};
  } on _Failure catch (failure) {
    return {
      'ok': false,
      'error': failure.message,
      if (failure.retry) 'retry': true,
    };
  } catch (error, stack) {
    final frames = '$stack'.split('\n').take(4).join('\n');
    return {'ok': false, 'error': 'Pilot bridge error: $error\n$frames'};
  }
}

/// Actions a screen reader needs but a person looking at the screen does not.
const _silentActions = {
  'showOnScreen',
  'focus',
  'didGainAccessibilityFocus',
  'didLoseAccessibilityFocus',
};

class _Target {
  _Target(this.point, this.what, [this.element, this.rect]);
  final Offset point;
  final String what;
  final Element? element;

  /// The widget's rectangle on screen; null for a bare point.
  final Rect? rect;
}

/// A copy of [image] with a red frame round [rect], or a ring round [point]
/// when there is no rectangle. This is how a screenshot shows where a defect
/// is.
Future<ui.Image> markImage(ui.Image image, {Rect? rect, Offset? point}) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder)..drawImage(image, Offset.zero, Paint());
  // A white edge under the red keeps the mark visible on any background.
  for (final (color, width) in [
    (const Color(0xFFFFFFFF), 7.0),
    (const Color(0xFFE53935), 3.5),
  ]) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..color = color;
    if (rect != null) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect.inflate(5), const Radius.circular(6)),
        paint,
      );
    } else if (point != null) {
      canvas.drawCircle(point, 20, paint);
    }
  }
  return recorder.endRecording().toImage(image.width, image.height);
}

final _sinceLastFrame = Stopwatch()..start();
var _displayIsSilent = false;
var _drawingByHand = false;
var _watchingFrames = false;

/// Draws frames even when the display is not asking for any.
///
/// A desktop window that is hidden or covered gets no vsync, so the app stops
/// drawing and an ordinary pump would wait for ever. When no frame comes in
/// time, this draws them itself and moves the animation clock on by the real
/// time that has passed, so that transitions still run to their end. It goes
/// back to the display's frames as soon as one arrives.
class _PilotController extends LiveWidgetController {
  _PilotController(super.binding) {
    if (_watchingFrames) return;
    _watchingFrames = true;
    binding.addPersistentFrameCallback((_) {
      _sinceLastFrame.reset();
      if (!_drawingByHand) _displayIsSilent = false;
    });
  }

  @override
  Future<void> pump([Duration? duration]) async {
    if (duration != null) await Future<void>.delayed(duration);
    binding.scheduleFrame();
    if (!_displayIsSilent) {
      final drawn = await binding.endOfFrame
          .then((_) => true)
          .timeout(const Duration(milliseconds: 300), onTimeout: () => false);
      if (drawn) return;
      _displayIsSilent = true;
    }
    if (binding.schedulerPhase != SchedulerPhase.idle) {
      await binding.endOfFrame;
      return;
    }
    final passed = _sinceLastFrame.elapsed;
    const longest = Duration(seconds: 2);
    // Two frames in an epoch of their own: the first carries the time stamp
    // of the last frame drawn, the second one that is `passed` later. Ending
    // the epoch afterwards lets the display's frames resume without a jump.
    _drawingByHand = true;
    try {
      binding.resetEpoch();
      await _frame(Duration.zero);
      await _frame(passed > longest ? longest : passed);
      binding.resetEpoch();
    } finally {
      _drawingByHand = false;
    }
  }

  Future<void> _frame(Duration rawTimeStamp) async {
    binding.handleBeginFrame(rawTimeStamp);
    await null; // microtasks run between the two halves, as in a real frame
    binding.handleDrawFrame();
  }
}

class _Pilot {
  _Pilot(this.params, this.controller);

  final Map<String, String> params;
  final WidgetController controller;

  String get _root => params['root'] ?? '';
  RenderView get _view => RendererBinding.instance.renderViews.first;
  Rect get _screen => Offset.zero & _view.size;

  Future<Map<String, Object?>> run() async => switch (params['cmd']) {
    'ping' => const {},
    'snapshot' => _snapshot(),
    'find' => _find(),
    'tap' => await _tap(),
    'type' => await _type(),
    'scroll' => await _drag(fling: false),
    'swipe' => await _drag(fling: true),
    'scrollTo' => await _scrollTo(),
    'back' => await _back(),
    'shot' => await _shot(),
    _ => throw _Failure('Unknown pilot command "${params['cmd']}".'),
  };

  // ---- reading the screen ----

  SemanticsNode get _semanticsRoot =>
      _view.owner?.semanticsOwner?.rootSemanticsNode ??
      (throw _Failure('The semantics tree is not ready yet.', retry: true));

  Map<String, Object?> _snapshot() {
    final owners = _owners();
    final nodes = <Map<String, Object?>>[];
    void visit(SemanticsNode node, int depth) {
      if (node.isInvisible || node.isMergedIntoParent) return;
      final entry = _describeNode(node, owners[node.id]);
      if (entry != null) nodes.add({...entry, 'depth': depth});
      final children = node.debugListChildrenInOrder(
        DebugSemanticsDumpOrder.traversalOrder,
      );
      for (final child in children) {
        visit(child, entry == null ? depth : depth + 1);
      }
    }

    visit(_semanticsRoot, 0);
    return {
      'size': [_screen.width.round(), _screen.height.round()],
      'route': _route(),
      'nodes': nodes,
    };
  }

  /// What a node says and offers, or null for one that only groups others.
  Map<String, Object?>? _describeNode(SemanticsNode node, Element? owner) {
    final data = node.getSemanticsData();
    // Read flags and actions as names: their typed API changed between
    // Flutter versions, the diagnostics did not.
    var flags = const <String>[];
    var actions = const <String>[];
    for (final property in data.toDiagnosticsNode().getProperties()) {
      final value = property.value;
      if (value is! Iterable) continue;
      if (property.name == 'flags') flags = [for (final v in value) '$v'];
      if (property.name == 'actions') actions = [for (final v in value) '$v'];
    }
    actions = actions.where((a) => !_silentActions.contains(a)).toList();
    final texts = {
      'label': data.label,
      'value': data.value,
      'hint': data.hint,
      'tooltip': data.tooltip,
      'id': data.identifier,
    }..removeWhere((_, text) => text.isEmpty);
    if (texts.isEmpty && actions.isEmpty) return null;

    final rect = _rectOfNode(node);
    final max = data.scrollExtentMax;
    return {
      'ref': node.id,
      ...texts,
      if (flags.isNotEmpty) 'flags': flags,
      if (actions.isNotEmpty) 'actions': actions,
      'rect': _ints(rect),
      if (!rect.overlaps(_screen) || flags.contains('isHidden'))
        'offscreen': true,
      if (max != null && max > 0)
        'scroll': [
          data.scrollPosition?.round() ?? 0,
          max.isFinite ? max.round() : -1,
        ],
      ..._origin(owner, node: node.id),
      if (owner != null && _traced != null) 'chain': _chain(owner, _traced!),
    };
  }

  /// The files a snapshot was asked to trace, one path per line.
  late final _traced = params['files']?.split('\n').toSet();

  final _places = <Element, String?>{};

  /// Where the widgets around [element] were created in [files], nearest
  /// first, each as `lib/cart.dart:57`.
  List<String> _chain(Element element, Set<String> files) {
    final chain = <String>[];
    void add(Element at) {
      // Nodes share most of their ancestors, so each is looked up once.
      final place = _places.putIfAbsent(at, () => _createdAt(at));
      if (place == null) return;
      if (files.contains(place.substring(0, place.lastIndexOf(':')))) {
        chain.add(place);
      }
    }

    add(element);
    element.visitAncestorElements((ancestor) {
      add(ancestor);
      return true;
    });
    return chain;
  }

  /// A node's rectangle in logical screen coordinates.
  Rect _rectOfNode(SemanticsNode node) {
    var toScreen = Matrix4.identity();
    for (SemanticsNode? n = node; n != null; n = n.parent) {
      final transform = n.transform;
      if (transform != null) toScreen = transform.multiplied(toScreen);
    }
    // The chain ends in physical pixels; pointer events use logical ones.
    final physical = MatrixUtils.transformRect(toScreen, node.rect);
    final ratio = _view.flutterView.devicePixelRatio;
    return Rect.fromLTRB(
      physical.left / ratio,
      physical.top / ratio,
      physical.right / ratio,
      physical.bottom / ratio,
    );
  }

  Rect? _rectOfElement(Element element) {
    final box = element.renderObject;
    if (box is! RenderBox || !box.attached || !box.hasSize) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  List<int> _ints(Rect rect) => [
    rect.left.round(),
    rect.top.round(),
    rect.right.round(),
    rect.bottom.round(),
  ];

  /// The element whose render object produced each semantics node.
  Map<int, Element> _owners() {
    final owners = <int, Element>{};
    final root = WidgetsBinding.instance.rootElement!;
    for (final element in collectAllElementsFrom(root, skipOffstage: true)) {
      if (element is! RenderObjectElement) continue;
      final node = element.renderObject.debugSemantics;
      if (node != null) owners.putIfAbsent(node.id, () => element);
    }
    return owners;
  }

  late final _inspector = InspectorSerializationDelegate(
    service: WidgetInspectorService.instance,
  );

  /// Where [element]'s widget was created, as `lib/cart.dart:57`.
  String? _createdAt(Element element) {
    final location = _inspector.additionalNodeProperties(
      element.toDiagnosticsNode(),
    )['creationLocation'];
    if (location is! Map) return null;
    return '${_short('${location['file']}', _root)}:${location['line']}';
  }

  /// The widget the app's own code created that [element] belongs to: its
  /// type, key and source line.
  ///
  /// For the element behind semantics node [node] that is the nearest such
  /// widget around it, or else the first one inside it, without wandering
  /// into a different node's part of the tree. A list row, for one, is
  /// wrapped by the list, so its own widget is found inside it.
  Map<String, Object?> _origin(Element? element, {int? node}) {
    if (element == null) return const {};

    Map<String, Object?>? appWidget(Element candidate) {
      final location = _inspector.additionalNodeProperties(
        candidate.toDiagnosticsNode(),
      )['creationLocation'];
      if (location is! Map) return null;
      final file = '${location['file']}';
      final fromPackage =
          file.contains('/packages/flutter') ||
          file.contains('/.pub-cache/') ||
          file.contains('/Pub/Cache/');
      if (fromPackage) return null;
      final key = candidate.widget.key;
      return {
        'widget': '${candidate.widget.runtimeType}',
        if (key is ValueKey) 'key': '${key.value}',
        'src': '${_short(file, _root)}:${location['line']}',
      };
    }

    bool inAnotherNode(Element candidate) {
      if (node == null || candidate is! RenderObjectElement) return false;
      final other = candidate.renderObject.debugSemantics;
      return other != null && other.id != node;
    }

    Map<String, Object?>? around({required bool withinNode}) {
      Map<String, Object?>? found;
      element.visitAncestorElements((ancestor) {
        if (withinNode && inAnotherNode(ancestor)) return false;
        found = appWidget(ancestor);
        return found == null;
      });
      return found;
    }

    Map<String, Object?>? inside() {
      Map<String, Object?>? found;
      void visit(Element child) {
        if (found != null || inAnotherNode(child)) return;
        found = appWidget(child);
        if (found == null) child.visitChildren(visit);
      }

      element.visitChildren(visit);
      return found;
    }

    return appWidget(element) ??
        around(withinNode: true) ??
        (node == null ? null : inside() ?? around(withinNode: false)) ??
        const {};
  }

  NavigatorState? get _navigator {
    NavigatorState? navigator;
    void visit(Element element) {
      if (navigator != null) return;
      if (element is StatefulElement && element.state is NavigatorState) {
        navigator = element.state as NavigatorState;
      } else {
        element.visitChildren(visit);
      }
    }

    WidgetsBinding.instance.rootElement!.visitChildren(visit);
    return navigator;
  }

  /// The top route, e.g. `/cart (MaterialPageRoute<void>)`.
  String? _route() {
    String? top;
    // popUntil hands over the top route first; returning true pops nothing.
    _navigator?.popUntil((route) {
      top = '${route.settings.name ?? ''} (${route.runtimeType})'.trim();
      return true;
    });
    return top;
  }

  // ---- finding widgets ----

  Finder? _finder() {
    if (params['text'] case final text?) {
      return find.text(text, findRichText: true);
    }
    if (params['contains'] case final text?) {
      return find.textContaining(text, findRichText: true);
    }
    if (params['key'] case final key?) return find.byKey(ValueKey<String>(key));
    if (params['tooltip'] case final message?) return find.byTooltip(message);
    if (params['label'] case final label?) return find.bySemanticsLabel(label);
    if (params['src'] case final src?) {
      return find.byElementPredicate(
        (element) => _createdAt(element) == src,
        description: 'widget created at $src',
      );
    }
    if (params['type'] case final type?) {
      return find.byWidgetPredicate(
        (widget) => '${widget.runtimeType}' == type,
        description: 'widget of type $type',
      );
    }
    return null;
  }

  Map<String, Object?> _find() {
    final finder = _finder() ?? (throw _Failure('find needs a finder.'));
    final matches = _matches(finder);
    return {
      'count': matches.length,
      'matches': [
        for (final match in matches.take(10)) _describeElement(match),
      ],
    };
  }

  /// The finder's matches in reading order, so that --index counts the way
  /// the screen reads, not the way the widget tree happens to be built.
  List<Element> _matches(Finder finder) {
    final found = [
      for (final (order, element) in finder.evaluate().indexed)
        (order: order, element: element, rect: _rectOfElement(element)),
    ];
    found.sort((a, b) {
      final (ra, rb) = (a.rect, b.rect);
      if (ra == null || rb == null) {
        return ra == rb ? a.order - b.order : (ra == null ? 1 : -1);
      }
      final byPlace = ra.top != rb.top
          ? ra.top.compareTo(rb.top)
          : ra.left.compareTo(rb.left);
      return byPlace != 0 ? byPlace : a.order - b.order;
    });
    return [for (final match in found) match.element];
  }

  Map<String, Object?> _describeElement(Element element) {
    final rect = _rectOfElement(element);
    return {
      if (rect != null) 'rect': _ints(rect),
      if (rect == null || !rect.overlaps(_screen)) 'offscreen': true,
      ..._origin(element),
    };
  }

  /// The point a command aims at, or null when it names none.
  Future<_Target?> _target() async {
    if (params['at'] case final at?) {
      final xy = at.split(',').map(double.tryParse).toList();
      if (xy.length != 2 || xy.contains(null)) {
        throw _Failure('--at takes x,y in logical pixels, e.g. --at 120,300.');
      }
      return _Target(Offset(xy[0]!, xy[1]!), 'The point $at');
    }

    if (params['ref'] case final ref?) {
      final id = int.tryParse(ref);
      SemanticsNode? node;
      bool search(SemanticsNode candidate) {
        if (candidate.id == id) node = candidate;
        if (node == null) candidate.visitChildren(search);
        return node == null;
      }

      search(_semanticsRoot);
      final found =
          node ??
          (throw _Failure(
            'Ref $ref is not on screen any more. Take a new snapshot.',
          ));
      var rect = _rectOfNode(found);
      if (!rect.overlaps(_screen)) {
        found.owner?.performAction(found.id, SemanticsAction.showOnScreen);
        await _settle();
        rect = _rectOfNode(found);
      }
      if (!rect.overlaps(_screen)) {
        throw _Failure('Ref $ref is off screen. Scroll to it first.');
      }
      return _Target(
        rect.intersect(_screen).center,
        'Ref $ref',
        _owners()[id],
        rect,
      );
    }

    final finder = _finder();
    if (finder == null) return null;
    final what = finder.describeMatch(Plurality.one);
    final matches = _matches(finder);
    if (matches.isEmpty) {
      throw _Failure('Nothing on screen matches: $what.', retry: true);
    }
    // Several widgets can be created on one source line; the outermost is
    // the one an error message means.
    final index =
        int.tryParse(params['index'] ?? '') ??
        (params.containsKey('src') ? 0 : null);
    if (index == null && matches.length > 1) {
      final list = [
        for (final (i, match) in matches.take(10).indexed)
          '  --index $i  ${jsonEncode(_describeElement(match))}',
      ].join('\n');
      throw _Failure(
        '${matches.length} widgets match: $what. Pick one:\n$list',
      );
    }
    if (index != null && (index < 0 || index >= matches.length)) {
      throw _Failure(
        '--index $index is out of range: ${matches.length} match.',
      );
    }
    final element = matches[index ?? 0];
    var rect = _rectOfElement(element);
    if (rect != null && !rect.overlaps(_screen)) {
      await Scrollable.ensureVisible(element, alignment: 0.5);
      await _settle();
      rect = _rectOfElement(element);
    }
    if (rect == null || !rect.overlaps(_screen)) {
      throw _Failure('It is off screen: $what. Scroll to it first.');
    }
    return _Target(rect.intersect(_screen).center, 'The $what', element, rect);
  }

  /// Fails when a tap at the target's point would land on something else.
  void _checkReachable(_Target target) {
    final renderObject = target.element?.renderObject;
    if (renderObject == null) return;
    final result = HitTestResult();
    WidgetsBinding.instance.hitTestInView(
      result,
      target.point,
      _view.flutterView.viewId,
    );
    if (result.path.any((entry) => identical(entry.target, renderObject)))
      return;

    var cover = 'nothing that takes taps';
    final top = result.path.firstOrNull?.target;
    if (top is RenderObject) {
      final creator = top.debugCreator;
      final origin = creator is DebugCreator ? _origin(creator.element) : null;
      cover = origin == null || origin.isEmpty
          ? '${top.runtimeType}'
          : '${origin['widget']} (${origin['src']})';
    }
    final at = '${target.point.dx.round()},${target.point.dy.round()}';
    throw _Failure(
      '${target.what} cannot be tapped: at $at a tap lands on $cover. '
      'It may be covered or disabled. Use --at x,y to tap a point anyway.',
    );
  }

  // ---- acting ----

  /// What an action landed on, so that the caller can check it was the
  /// widget it meant.
  Map<String, Object?> _landedOn(_Target target) => {
    'at': [target.point.dx.round(), target.point.dy.round()],
    ..._origin(target.element),
  };

  /// Lets the frames an action caused play out, without waiting for ever on
  /// an animation that never stops. False when the screen is still moving.
  ///
  /// Bounded two ways: twelve frames in a test's fake time, and a second and
  /// a half of real time on a device that is slow to draw, so that a message
  /// shown briefly after the action is still there for the next command.
  Future<bool> _settle() async {
    final elapsed = Stopwatch()..start();
    for (var i = 0; i < 12 && elapsed.elapsedMilliseconds < 1500; i++) {
      await controller.pump(const Duration(milliseconds: 100));
      if (!controller.binding.hasScheduledFrame) return true;
    }
    return false;
  }

  Future<Map<String, Object?>> _tap() async {
    final target =
        await _target() ??
        (throw _Failure('tap needs a ref, a finder or --at x,y.'));
    _checkReachable(target);
    switch (params['mode']) {
      case 'long':
        await controller.longPressAt(target.point);
      case 'double':
        await controller.tapAt(target.point);
        await controller.pump(kDoubleTapMinTime);
        await controller.tapAt(target.point);
      default:
        await controller.tapAt(target.point);
    }
    final hit = _landedOn(target);
    return {'settled': await _settle(), 'hit': hit};
  }

  Future<Map<String, Object?>> _type() async {
    final text = params['value'] ?? (throw _Failure('type needs text.'));
    EditableTextState? field;
    final target = await _target();
    final hit = target == null ? null : _landedOn(target);
    if (target != null) {
      _checkReachable(target);
      await controller.tapAt(target.point);
      await _settle();
      field = target.element == null ? null : _editableIn(target.element!);
    }
    field ??= FocusManager.instance.primaryFocus?.context
        ?.findAncestorStateOfType<EditableTextState>();
    if (field == null) {
      throw _Failure(
        target == null
            ? 'No text field is focused: name the field to type into.'
            : '${target.what} is not a text field.',
      );
    }
    if (field.widget.readOnly) throw _Failure('That text field is read-only.');
    // Goes through the field's formatters and onChanged, as typing does.
    field.userUpdateTextEditingValue(
      TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
      ),
      SelectionChangedCause.keyboard,
    );
    if (params['submit'] == 'true') {
      field.performAction(
        field.widget.textInputAction ??
            (field.widget.maxLines == 1
                ? TextInputAction.done
                : TextInputAction.newline),
      );
    }
    return {'settled': await _settle(), 'hit': ?hit};
  }

  EditableTextState? _editableIn(Element root) {
    EditableTextState? found;
    void visit(Element element) {
      if (found != null) return;
      if (element is StatefulElement && element.state is EditableTextState) {
        found = element.state as EditableTextState;
      } else {
        element.visitChildren(visit);
      }
    }

    visit(root);
    return found ?? root.findAncestorStateOfType<EditableTextState>();
  }

  Future<Map<String, Object?>> _drag({required bool fling}) async {
    final start = (await _target())?.point ?? _screen.center;
    final offset = Offset(
      double.tryParse(params['dx'] ?? '0') ?? 0,
      double.tryParse(params['dy'] ?? '0') ?? 0,
    );
    if (offset == Offset.zero) throw _Failure('Give --dx and/or --dy.');
    if (fling) {
      await controller.flingFrom(start, offset, 1500);
    } else {
      await controller.dragFrom(start, offset);
    }
    return {'settled': await _settle()};
  }

  /// Moves the screen's main scrollable until the finder matches. Lazy lists
  /// only build what is near the viewport, so this is how to reach the rest.
  Future<Map<String, Object?>> _scrollTo() async {
    final finder = _finder() ?? (throw _Failure('scroll-to needs a finder.'));
    final backwards = params['up'] == 'true';
    ScrollableState? scrollable;
    for (var step = 0; step < 100; step++) {
      final matches = finder.evaluate();
      if (matches.isNotEmpty) {
        await Scrollable.ensureVisible(matches.first, alignment: 0.5);
        return {'settled': await _settle()};
      }
      scrollable ??= _mainScrollable();
      final position = scrollable.position;
      final limit = backwards
          ? position.minScrollExtent
          : position.maxScrollExtent;
      if (position.pixels == limit) break;
      final stride = position.viewportDimension * 0.8 * (backwards ? -1 : 1);
      position.jumpTo(
        (position.pixels + stride).clamp(
          position.minScrollExtent,
          position.maxScrollExtent,
        ),
      );
      await controller.pump(const Duration(milliseconds: 50));
    }
    throw _Failure(
      'Scrolled to the ${backwards ? 'start' : 'end'} without finding: '
      '${finder.describeMatch(Plurality.one)}.',
    );
  }

  /// The largest scrollable on screen that has somewhere to scroll.
  ScrollableState _mainScrollable() {
    ScrollableState? best;
    var bestArea = 0.0;
    for (final element in find.byType(Scrollable).evaluate()) {
      final state = (element as StatefulElement).state as ScrollableState;
      final position = state.position;
      if (!position.hasContentDimensions ||
          position.maxScrollExtent <= position.minScrollExtent) {
        continue;
      }
      final rect = _rectOfElement(element);
      if (rect == null || !rect.overlaps(_screen)) continue;
      final visible = rect.intersect(_screen);
      final area = visible.width * visible.height;
      if (area > bestArea) {
        best = state;
        bestArea = area;
      }
    }
    return best ?? (throw _Failure('Nothing on this screen can scroll.'));
  }

  Future<Map<String, Object?>> _back() async {
    // What the system back button does, short of closing the app on the
    // first route.
    if (!(await _navigator?.maybePop() ?? false)) {
      throw _Failure('There is nothing to go back to.');
    }
    return {'settled': await _settle()};
  }

  /// The Flutter-rendered screen as a PNG, one image pixel per logical pixel
  /// so that image coordinates are the ones --at takes.
  Future<Map<String, Object?>> _shot() async {
    // Resolving the target first scrolls it into view if need be.
    final target = await _target();
    await controller.pump();
    final layer = _view.debugLayer! as OffsetLayer;
    var image = await layer.toImage(
      _view.paintBounds,
      pixelRatio: 1 / _view.flutterView.devicePixelRatio,
    );
    if (target != null) {
      final plain = image;
      image = await markImage(
        plain,
        rect: target.rect?.intersect(_screen),
        point: target.point,
      );
      plain.dispose();
    }
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return {
      'png': base64Encode(bytes!.buffer.asUint8List()),
      if (target != null) 'hit': _landedOn(target),
    };
  }
}
