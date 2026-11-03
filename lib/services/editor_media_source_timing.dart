part of 'editor_media_source.dart';

EditorMediaProbe parseEditorMediaProbe(Object? value) {
  if (value is! Map) {
    throw const FormatException('FFprobe returned invalid media metadata.');
  }
  final streams = value['streams'];
  if (streams is! List) {
    throw const FormatException('The file has no readable media streams.');
  }
  final format = value['format'] is Map ? value['format']! as Map : const {};
  final formatStart = _secondsMicros(format['start_time']);
  final formatDuration = _positiveSecondsMicros(format['duration']);
  _RawStreamTiming? rawVideo;
  _RawStreamTiming? rawAudio;
  int? width;
  int? height;
  for (final stream in streams.whereType<Map>()) {
    final kind = stream['codec_type'];
    if (kind != 'video' && kind != 'audio') continue;
    if (kind == 'video' && rawVideo != null) continue;
    if (kind == 'audio' && rawAudio != null) continue;
    final timing = _rawStreamTiming(stream, formatStartMicros: formatStart);
    if (kind == 'video') {
      rawVideo = timing;
      final candidateWidth = _positiveInt(stream['width']);
      final candidateHeight = _positiveInt(stream['height']);
      if (candidateWidth != null && candidateHeight != null) {
        width ??= candidateWidth;
        height ??= candidateHeight;
      }
    } else {
      rawAudio = timing;
    }
  }
  if (rawVideo == null && rawAudio == null) {
    throw const FormatException(
      'The file needs a finite video or audio duration.',
    );
  }
  _RationalMicros? sourceOrigin;
  for (final timing in [rawVideo, rawAudio].whereType<_RawStreamTiming>()) {
    if (sourceOrigin == null ||
        _compareRational(timing.start, sourceOrigin) < 0) {
      sourceOrigin = timing.start;
    }
  }
  final videoTiming = _normaliseStreamTiming(
    rawVideo,
    sourceOrigin!,
    formatStartMicros: formatStart,
    formatDurationMicros: formatDuration,
  );
  final audioTiming = _normaliseStreamTiming(
    rawAudio,
    sourceOrigin,
    formatStartMicros: formatStart,
    formatDurationMicros: formatDuration,
  );
  final duration = _presentationDuration(videoTiming, audioTiming);
  if (duration <= Duration.zero || duration > maxEditorDuration) {
    throw FormatException(
      'Local editor media must be no longer than '
      '${maxEditorDuration.inMinutes} minutes on this platform.',
    );
  }
  return EditorMediaProbe(
    videoTiming: videoTiming,
    audioTiming: audioTiming,
    width: width,
    height: height,
  );
}

typedef _RationalMicros = ({BigInt numerator, BigInt denominator});
typedef _RawStreamTiming = ({_RationalMicros start, _RationalMicros? duration});

final BigInt _maxExactWebInteger = BigInt.from(9007199254740991);

_RawStreamTiming _rawStreamTiming(
  Map stream, {
  required int? formatStartMicros,
}) {
  final start =
      _timestampRationalMicros(stream['start_pts'], stream['time_base']) ??
      _secondsRationalMicros(stream['start_time']) ??
      _integerMicros(formatStartMicros ?? 0);
  final duration =
      _positiveTimestampRationalMicros(
        stream['duration_ts'],
        stream['time_base'],
      ) ??
      _positiveSecondsRationalMicros(stream['duration']);
  return (start: start, duration: duration);
}

VideoProjectStreamTiming? _normaliseStreamTiming(
  _RawStreamTiming? timing,
  _RationalMicros sourceOrigin, {
  required int? formatStartMicros,
  required int? formatDurationMicros,
}) {
  if (timing == null) return null;
  final start = _roundRationalMicros(
    _subtractRational(timing.start, sourceOrigin),
  );
  final formatEnd = formatDurationMicros == null
      ? null
      : _addRational(
          formatStartMicros == null
              ? sourceOrigin
              : _integerMicros(formatStartMicros),
          _integerMicros(formatDurationMicros),
        );
  final duration =
      timing.duration ??
      (formatEnd == null ? null : _subtractRational(formatEnd, timing.start));
  if (duration == null || _compareRational(duration, _integerMicros(0)) <= 0) {
    throw const FormatException(
      'The file needs a finite video or audio duration.',
    );
  }
  final roundedDuration = _roundRationalMicros(duration);
  if (roundedDuration <= 0) {
    throw const FormatException(
      'The file needs a finite video or audio duration.',
    );
  }
  final result = VideoProjectStreamTiming(
    presentationStart: Duration(microseconds: start),
    duration: Duration(microseconds: roundedDuration),
  );
  _validateStreamTiming(result, true, 'decoded');
  if (result.presentationEnd > maxEditorDuration) {
    throw FormatException(
      'Local editor media must be no longer than '
      '${maxEditorDuration.inMinutes} minutes on this platform.',
    );
  }
  return result;
}

_RationalMicros? _timestampRationalMicros(Object? timestamp, Object? timeBase) {
  final ticks = BigInt.tryParse('$timestamp');
  final parts = '$timeBase'.split('/');
  if (ticks == null || parts.length != 2) return null;
  final numerator = BigInt.tryParse(parts[0]);
  final denominator = BigInt.tryParse(parts[1]);
  if (numerator == null ||
      denominator == null ||
      numerator <= BigInt.zero ||
      denominator <= BigInt.zero) {
    return null;
  }
  return _rationalMicros(
    ticks * numerator * BigInt.from(Duration.microsecondsPerSecond),
    denominator,
  );
}

_RationalMicros? _positiveTimestampRationalMicros(
  Object? timestamp,
  Object? timeBase,
) {
  final micros = _timestampRationalMicros(timestamp, timeBase);
  return micros != null && _compareRational(micros, _integerMicros(0)) > 0
      ? micros
      : null;
}

int? _positiveSecondsMicros(Object? value) {
  final micros = _secondsMicros(value);
  return micros != null && micros > 0 ? micros : null;
}

int? _secondsMicros(Object? value) {
  final parsed = value is num ? value.toDouble() : double.tryParse('$value');
  if (parsed == null || !parsed.isFinite) return null;
  final scaled = parsed * Duration.microsecondsPerSecond;
  if (!scaled.isFinite || scaled.abs() > _maxExactWebInteger.toDouble()) {
    return null;
  }
  return scaled.round();
}

_RationalMicros? _secondsRationalMicros(Object? value) {
  final micros = _secondsMicros(value);
  return micros == null ? null : _integerMicros(micros);
}

_RationalMicros? _positiveSecondsRationalMicros(Object? value) {
  final micros = _positiveSecondsMicros(value);
  return micros == null ? null : _integerMicros(micros);
}

_RationalMicros _integerMicros(int value) =>
    (numerator: BigInt.from(value), denominator: BigInt.one);

_RationalMicros _rationalMicros(BigInt numerator, BigInt denominator) {
  final divisor = numerator.abs().gcd(denominator);
  return (numerator: numerator ~/ divisor, denominator: denominator ~/ divisor);
}

_RationalMicros _addRational(_RationalMicros left, _RationalMicros right) =>
    _rationalMicros(
      left.numerator * right.denominator + right.numerator * left.denominator,
      left.denominator * right.denominator,
    );

_RationalMicros _subtractRational(
  _RationalMicros left,
  _RationalMicros right,
) => _rationalMicros(
  left.numerator * right.denominator - right.numerator * left.denominator,
  left.denominator * right.denominator,
);

int _compareRational(_RationalMicros left, _RationalMicros right) =>
    (left.numerator * right.denominator).compareTo(
      right.numerator * left.denominator,
    );

int _roundRationalMicros(_RationalMicros value) {
  final negative = value.numerator.isNegative;
  final magnitude = negative ? -value.numerator : value.numerator;
  final rounded =
      (magnitude + value.denominator ~/ BigInt.two) ~/ value.denominator;
  if (rounded > _maxExactWebInteger) {
    throw const FormatException(
      'The file contains media timing outside the supported range.',
    );
  }
  final signed = negative ? -rounded : rounded;
  return signed.toInt();
}
