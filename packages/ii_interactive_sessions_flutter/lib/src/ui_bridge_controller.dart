import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:ii_interactive_sessions/ii_interactive_sessions.dart';

typedef UiElementAction = FutureOr<void> Function(UiActionRequest request);
typedef UiActionApproval =
    Future<bool> Function(UiSemanticNode node, UiActionRequest request);
typedef UiScreenshotCapture = Future<UiScreenshot> Function(int revision);

final class UiElementBinding {
  const UiElementBinding({required this.node, required this.onAction});

  final UiSemanticNode node;
  final UiElementAction onAction;
}

final class InteractiveUiBridgeController extends ChangeNotifier {
  InteractiveUiBridgeController({
    required this.client,
    required this.route,
    required this.approveSensitiveAction,
    this.captureScreenshot,
    this.maxNodes = 500,
  });

  final InteractiveSessionClient client;
  final String Function() route;
  final UiActionApproval approveSensitiveAction;
  final UiScreenshotCapture? captureScreenshot;
  final int maxNodes;
  final Map<String, UiElementBinding> _bindings = {};
  final Set<String> _completedActions = {};
  StreamSubscription<SessionFrame>? _frames;
  int _revision = 1;
  bool _enabled = false;
  bool _disposed = false;

  int get revision => _revision;
  bool get enabled => _enabled;
  List<UiSemanticNode> get nodes =>
      _bindings.values.map((item) => item.node).toList(growable: false);

  Future<void> enable() async {
    if (_disposed) return;
    if (_enabled) return;
    _enabled = true;
    _frames = client.frames.listen(_onFrame);
    await publishState();
    if (!_disposed) notifyListeners();
  }

  Future<void> disable() async {
    _enabled = false;
    _revision++;
    await _frames?.cancel();
    _frames = null;
    if (!_disposed) notifyListeners();
  }

  void register(UiElementBinding binding) {
    if (!_safeId.hasMatch(binding.node.id)) {
      throw ArgumentError.value(binding.node.id, 'id', 'is not a stable ID');
    }
    if (!_bindings.containsKey(binding.node.id) &&
        _bindings.length >= maxNodes) {
      throw StateError('Semantic node limit reached.');
    }
    _bindings[binding.node.id] = binding;
    _changed();
  }

  void unregister(String id) {
    if (_bindings.remove(id) != null) _changed();
  }

  Future<void> publishState() async {
    if (!_enabled) return;
    await client.publishUiState(
      UiSemanticSnapshot(revision: _revision, route: route(), nodes: nodes),
    );
  }

  void _changed() {
    _revision++;
    if (_enabled) unawaited(publishState());
    notifyListeners();
  }

  void _onFrame(SessionFrame frame) {
    if (!_enabled) return;
    if (frame.type == 'ui.action') {
      unawaited(_act(frame));
    } else if (frame.type == 'ui.screenshot.request') {
      unawaited(_screenshot(frame));
    }
  }

  Future<void> _act(SessionFrame frame) async {
    if (!_completedActions.add(frame.id)) {
      await _result(frame.id, 'duplicate');
      return;
    }
    late UiActionRequest request;
    try {
      request = UiActionRequest.fromFrame(frame.id, frame.payload);
    } on FormatException {
      await _result(frame.id, 'invalid');
      return;
    }
    final binding = _bindings[request.targetId];
    if (request.expectedRevision != _revision) {
      await _result(frame.id, 'stale');
      return;
    }
    if (binding == null || !binding.node.visible || !binding.node.enabled) {
      await _result(frame.id, 'target_unavailable');
      return;
    }
    if (binding.node.sensitive &&
        !await approveSensitiveAction(binding.node, request)) {
      await _result(frame.id, 'approval_denied');
      return;
    }
    // Approval may outlive sharing or the UI it described. Re-check authority
    // at the action boundary, including a disable/re-enable cycle.
    if (!_enabled || _disposed) return;
    if (request.expectedRevision != _revision ||
        !identical(_bindings[request.targetId], binding)) {
      await _result(frame.id, 'stale');
      return;
    }
    try {
      await binding.onAction(request);
      if (!_enabled || _disposed) return;
      _revision++;
      await publishState();
      await _result(frame.id, 'applied');
      if (!_disposed) notifyListeners();
    } on Object {
      await _result(frame.id, 'failed');
    }
  }

  Future<void> _screenshot(SessionFrame frame) async {
    final capture = captureScreenshot;
    if (capture == null) {
      await _result(frame.id, 'screenshot_unavailable');
      return;
    }
    try {
      final requestedRevision = _revision;
      final screenshot = await capture(_revision);
      if (!_enabled || _disposed) return;
      if (requestedRevision != _revision || screenshot.revision != _revision) {
        await _result(frame.id, 'stale');
        return;
      }
      await client.publishScreenshot(
        screenshot,
        isCancelled: () =>
            !_enabled || _disposed || requestedRevision != _revision,
      );
    } on Object {
      await _result(frame.id, 'approval_denied');
    }
  }

  Future<void> _result(String actionId, String status) async {
    if (_disposed) return;
    await client.sendFrame(
      SessionFrame(
        type: 'ui.action.result',
        id: actionId,
        payload: {'status': status, 'revision': _revision},
      ),
    );
  }

  @override
  void dispose() {
    _disposed = true;
    _enabled = false;
    _revision++;
    unawaited(_frames?.cancel());
    super.dispose();
  }
}

final _safeId = RegExp(r'^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$');
