part of 'io_backend.dart';

final class _BoundedLogStore {
  _BoundedLogStore(this.safety);

  final FfmpegSafetyPolicy safety;
  final List<String> _lines = [];
  var _storedBytes = 0;

  List<String> get snapshot => List.unmodifiable(_lines);

  void addLine(String line) {
    if (_lines.length >= IoFfmpegBackend._maxLogLines ||
        _storedBytes >= safety.maxLogBytes) {
      return;
    }
    final boundedLine = line.length <= safety.maxLogLineBytes
        ? line
        : line.substring(0, safety.maxLogLineBytes);
    final encoded = utf8.encode(boundedLine);
    final allowed = [
      safety.maxLogLineBytes,
      safety.maxLogBytes - _storedBytes,
    ].reduce((left, right) => left < right ? left : right);
    final kept = encoded.length <= allowed
        ? encoded
        : encoded.sublist(0, allowed);
    _lines.add(utf8.decode(kept, allowMalformed: true));
    _storedBytes += kept.length;
  }
}

final class _BoundedLogSink {
  _BoundedLogSink(this.store, {this.onLine});

  final _BoundedLogStore store;
  final void Function(String line)? onLine;
  final List<int> _current = [];
  bool _discardingRemainder = false;

  void add(List<int> chunk) {
    for (final byte in chunk) {
      if (byte == 10) {
        _flush();
        continue;
      }
      if (_current.length < store.safety.maxLogLineBytes) {
        _current.add(byte);
      } else {
        _discardingRemainder = true;
      }
    }
  }

  void close() {
    if (_current.isNotEmpty || _discardingRemainder) _flush();
  }

  void _flush() {
    final line = utf8.decode(_current, allowMalformed: true);
    store.addLine(line);
    onLine?.call(line);
    _current.clear();
    _discardingRemainder = false;
  }
}
