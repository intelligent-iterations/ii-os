import 'dart:async';

final class EditorRenderCancelledException implements Exception {
  const EditorRenderCancelledException();

  @override
  String toString() => 'EditorRenderCancelledException';
}

final class EditorRenderCancellationToken {
  final Completer<void> _cancelledSignal = Completer<void>();
  bool _cancelled = false;

  bool get isCancelled => _cancelled;
  Future<void> get whenCancelled => _cancelledSignal.future;

  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    _cancelledSignal.complete();
  }

  void throwIfCancelled() {
    if (_cancelled) throw const EditorRenderCancelledException();
  }
}
