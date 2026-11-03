import 'dart:async';

import 'package:meta/meta.dart';

typedef MediaByteStreamFactory = Stream<List<int>> Function();

@immutable
final class MediaTime implements Comparable<MediaTime> {
  const MediaTime._(this.microseconds);

  factory MediaTime.microseconds(int value) {
    if (value < 0) {
      throw ArgumentError.value(value, 'value', 'must not be negative');
    }
    return MediaTime._(value);
  }

  factory MediaTime.milliseconds(int value) =>
      MediaTime.microseconds(value * Duration.microsecondsPerMillisecond);

  factory MediaTime.seconds(num value) {
    if (!value.isFinite || value < 0) {
      throw ArgumentError.value(
        value,
        'value',
        'must be finite and non-negative',
      );
    }
    return MediaTime.microseconds(
      (value * Duration.microsecondsPerSecond).round(),
    );
  }

  static const zero = MediaTime._(0);

  final int microseconds;

  double get inSeconds => microseconds / Duration.microsecondsPerSecond;

  MediaTime operator +(MediaTime other) =>
      MediaTime.microseconds(microseconds + other.microseconds);

  MediaTime operator -(MediaTime other) {
    if (other.microseconds > microseconds) {
      throw ArgumentError('MediaTime subtraction cannot produce a negative');
    }
    return MediaTime.microseconds(microseconds - other.microseconds);
  }

  @override
  int compareTo(MediaTime other) => microseconds.compareTo(other.microseconds);

  bool operator <(MediaTime other) => microseconds < other.microseconds;
  bool operator <=(MediaTime other) => microseconds <= other.microseconds;
  bool operator >(MediaTime other) => microseconds > other.microseconds;
  bool operator >=(MediaTime other) => microseconds >= other.microseconds;

  @override
  bool operator ==(Object other) =>
      other is MediaTime && microseconds == other.microseconds;

  @override
  int get hashCode => microseconds.hashCode;

  @override
  String toString() => '${inSeconds.toStringAsFixed(6)}s';
}

@immutable
final class MediaRange {
  MediaRange({required this.start, required this.duration}) {
    if (duration == MediaTime.zero) {
      throw ArgumentError.value(duration, 'duration', 'must be greater than 0');
    }
  }

  final MediaTime start;
  final MediaTime duration;

  MediaTime get end => start + duration;
}

@immutable
final class MediaSource {
  MediaSource({
    required this.id,
    required this.byteLength,
    required this.fileExtension,
    required this.openRead,
  }) {
    if (!_safeId.hasMatch(id)) {
      throw ArgumentError.value(id, 'id', 'must match ${_safeId.pattern}');
    }
    if (byteLength <= 0) {
      throw ArgumentError.value(byteLength, 'byteLength', 'must be positive');
    }
    if (!_safeExtension.hasMatch(fileExtension)) {
      throw ArgumentError.value(
        fileExtension,
        'fileExtension',
        'must be 1-10 lowercase ASCII letters or numbers',
      );
    }
  }

  static final RegExp _safeId = RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$');
  static final RegExp _safeExtension = RegExp(r'^[a-z0-9]{1,10}$');

  final String id;
  final int byteLength;
  final String fileExtension;
  final MediaByteStreamFactory openRead;
}

enum MediaFit { contain, cover, fill }

enum MediaContainer { mp4, webm, mov }

enum MediaVideoCodec { automatic, h264, vp9, mpeg4 }

enum MediaAudioCodec { automatic, aac, opus }

@immutable
final class MediaRect {
  const MediaRect({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });

  const MediaRect.full() : x = 0, y = 0, width = 1, height = 1;

  final double x;
  final double y;
  final double width;
  final double height;
}

sealed class MediaLayer {
  const MediaLayer({
    required this.id,
    required this.source,
    required this.sourceRange,
    required this.timelineStart,
  });

  final String id;
  final MediaSource source;
  final MediaRange sourceRange;
  final MediaTime timelineStart;

  MediaTime get timelineEnd => timelineStart + sourceRange.duration;
}

enum MediaTransitionKind {
  dissolve,
  dipToColor,
  slideFromLeft,
  slideFromRight,
  slideFromTop,
  slideFromBottom,
}

/// A transition resolved against the clips it joins, ready to compile.
@immutable
final class MediaVisualTransition {
  const MediaVisualTransition({
    required this.kind,
    required this.duration,
    this.color = '000000',
    this.overCut = false,
  });

  final MediaTransitionKind kind;
  final MediaTime duration;
  final String color;

  /// Whether a picture is leaving underneath this one, rather than the
  /// project background.
  final bool overCut;
}

@immutable
final class MediaVideoLayer extends MediaLayer {
  const MediaVideoLayer({
    required super.id,
    required super.source,
    required super.sourceRange,
    required super.timelineStart,
    this.destination = const MediaRect.full(),
    this.fit = MediaFit.contain,
    this.opacity = 1,
    this.transitionIn,
    this.holdAfter = MediaTime.zero,
  });

  final MediaRect destination;
  final MediaFit fit;
  final double opacity;
  final MediaVisualTransition? transitionIn;

  /// How long this picture keeps its last frame on screen after its own
  /// media ends, so the next clip has something to arrive over.
  final MediaTime holdAfter;
}

@immutable
final class MediaImageLayer extends MediaLayer {
  const MediaImageLayer({
    required super.id,
    required super.source,
    required super.sourceRange,
    required super.timelineStart,
    this.destination = const MediaRect.full(),
    this.fit = MediaFit.contain,
    this.opacity = 1,
  });

  final MediaRect destination;
  final MediaFit fit;
  final double opacity;
}

@immutable
final class MediaAudioLayer extends MediaLayer {
  const MediaAudioLayer({
    required super.id,
    required super.source,
    required super.sourceRange,
    required super.timelineStart,
    this.volume = 1,
  });

  final double volume;
}

@immutable
final class MediaOutputSettings {
  const MediaOutputSettings({
    this.container = MediaContainer.mp4,
    this.videoCodec = MediaVideoCodec.automatic,
    this.audioCodec = MediaAudioCodec.automatic,
    this.videoBitrate = 6 * 1000 * 1000,
    this.audioBitrate = 192 * 1000,
  });

  final MediaContainer container;
  final MediaVideoCodec videoCodec;
  final MediaAudioCodec audioCodec;
  final int videoBitrate;
  final int audioBitrate;
}

@immutable
final class MediaComposition {
  MediaComposition({
    required this.width,
    required this.height,
    required this.framesPerSecond,
    required this.duration,
    required Iterable<MediaLayer> layers,
    this.output = const MediaOutputSettings(),
    this.backgroundColor = '000000',
  }) : layers = List<MediaLayer>.unmodifiable(layers);

  final int width;
  final int height;
  final int framesPerSecond;
  final MediaTime duration;
  final List<MediaLayer> layers;
  final MediaOutputSettings output;
  final String backgroundColor;
}

@immutable
final class MediaLimits {
  const MediaLimits({
    this.maxInputCount = 16,
    this.maxLayerCount = 24,
    this.maxInputBytes = 512 * 1024 * 1024,
    this.maxDeclaredMediaBytes,
    this.maxSourceBytes = 512 * 1024 * 1024,
    this.maxOutputBytes = 512 * 1024 * 1024,
    this.maxEstimatedOutputBytes,
    this.maxVideoBitrate = 100 * 1000 * 1000,
    this.maxAudioBitrate = 1000 * 1000,
    this.sourceReadTimeout = const Duration(minutes: 2),
    this.sourceCancellationTimeout = const Duration(seconds: 1),
  });

  final int maxInputCount;
  final int maxLayerCount;
  final int maxInputBytes;
  final int? maxDeclaredMediaBytes;
  final int maxSourceBytes;
  final int maxOutputBytes;
  final int? maxEstimatedOutputBytes;
  final int maxVideoBitrate;
  final int maxAudioBitrate;
  final Duration sourceReadTimeout;
  final Duration sourceCancellationTimeout;

  /// The bitrate-based planning ceiling, before the hard encoded byte cap.
  int get estimatedOutputByteLimit => maxEstimatedOutputBytes ?? maxOutputBytes;

  /// Media bytes a timeline may declare before prepared caption bytes.
  int get declaredMediaByteLimit => maxDeclaredMediaBytes ?? maxInputBytes;

  void validateSelf() {
    if (maxInputCount <= 0 ||
        maxInputCount > 16 ||
        maxLayerCount <= 0 ||
        maxLayerCount > 24 ||
        maxInputBytes <= 0 ||
        maxInputBytes > 512 * 1024 * 1024 ||
        (maxDeclaredMediaBytes != null &&
            (maxDeclaredMediaBytes! <= 0 ||
                maxDeclaredMediaBytes! > maxInputBytes)) ||
        maxSourceBytes <= 0 ||
        maxSourceBytes > 512 * 1024 * 1024 ||
        maxOutputBytes <= 0 ||
        maxOutputBytes > 512 * 1024 * 1024 ||
        (maxEstimatedOutputBytes != null &&
            (maxEstimatedOutputBytes! <= 0 ||
                maxEstimatedOutputBytes! > maxOutputBytes)) ||
        maxVideoBitrate <= 0 ||
        maxVideoBitrate > 100 * 1000 * 1000 ||
        maxAudioBitrate <= 0 ||
        maxAudioBitrate > 1000 * 1000 ||
        sourceReadTimeout <= Duration.zero ||
        sourceReadTimeout > const Duration(minutes: 10) ||
        sourceCancellationTimeout <= Duration.zero ||
        sourceCancellationTimeout > const Duration(seconds: 5)) {
      throw ArgumentError('Media limits are inconsistent or out of bounds.');
    }
  }
}
