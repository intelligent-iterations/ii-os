part of 'composition_compiler.dart';

enum _EditorSourceRole { image, video, audio }

enum _EditorInputFormat {
  image2,
  mov,
  matroska,
  avi,
  mpeg,
  mp3,
  aac,
  wav,
  ogg,
  flac,
}

extension on _EditorInputFormat {
  String get ffmpegName => switch (this) {
    _EditorInputFormat.image2 => 'image2',
    _EditorInputFormat.mov => 'mov',
    _EditorInputFormat.matroska => 'matroska',
    _EditorInputFormat.avi => 'avi',
    _EditorInputFormat.mpeg => 'mpeg',
    _EditorInputFormat.mp3 => 'mp3',
    _EditorInputFormat.aac => 'aac',
    _EditorInputFormat.wav => 'wav',
    _EditorInputFormat.ogg => 'ogg',
    _EditorInputFormat.flac => 'flac',
  };
}

_EditorInputFormat? _inputFormatForSource(
  MediaSource source,
  _EditorSourceRole role,
) => switch (role) {
  _EditorSourceRole.image => switch (source.fileExtension) {
    'png' || 'jpg' || 'jpeg' || 'webp' => _EditorInputFormat.image2,
    _ => null,
  },
  _EditorSourceRole.video => switch (source.fileExtension) {
    'mp4' || 'mov' || 'm4v' => _EditorInputFormat.mov,
    'webm' || 'mkv' => _EditorInputFormat.matroska,
    'avi' => _EditorInputFormat.avi,
    'mpg' || 'mpeg' => _EditorInputFormat.mpeg,
    'png' || 'jpg' || 'jpeg' || 'webp' => _EditorInputFormat.image2,
    _ => null,
  },
  _EditorSourceRole.audio => switch (source.fileExtension) {
    'mp4' || 'mov' || 'm4v' || 'm4a' => _EditorInputFormat.mov,
    'webm' || 'mkv' => _EditorInputFormat.matroska,
    'mp3' => _EditorInputFormat.mp3,
    'aac' => _EditorInputFormat.aac,
    'wav' => _EditorInputFormat.wav,
    'ogg' || 'opus' => _EditorInputFormat.ogg,
    'flac' => _EditorInputFormat.flac,
    _ => null,
  },
};

String _inputFormatFor(MediaLayer layer) {
  final role = switch (layer) {
    MediaImageLayer() => _EditorSourceRole.image,
    MediaVideoLayer() => _EditorSourceRole.video,
    MediaAudioLayer() => _EditorSourceRole.audio,
  };
  final format = _inputFormatForSource(layer.source, role);
  if (format != null) return format.ffmpegName;
  throw EditorValidationException(
    'Unsupported ${role.name} extension .${layer.source.fileExtension}.',
  );
}

typedef _Placement = ({int left, int top, int width, int height});

_Placement _placement(MediaLayer layer, MediaComposition composition) {
  final destination = switch (layer) {
    MediaVideoLayer() => layer.destination,
    MediaImageLayer() => layer.destination,
    _ => throw StateError('not a visual layer'),
  };
  final left = (destination.x * composition.width).round();
  final right = ((destination.x + destination.width) * composition.width)
      .round();
  final top = (destination.y * composition.height).round();
  final bottom = ((destination.y + destination.height) * composition.height)
      .round();
  return (left: left, top: top, width: right - left, height: bottom - top);
}

MediaVisualTransition? _transitionOf(MediaLayer layer) =>
    layer is MediaVideoLayer ? layer.transitionIn : null;

MediaTime _holdOf(MediaLayer layer) =>
    layer is MediaVideoLayer ? layer.holdAfter : MediaTime.zero;

MediaTime _half(MediaTime value) =>
    MediaTime.microseconds(value.microseconds ~/ 2);

String _visualFilter(
  String input,
  String label,
  MediaLayer layer,
  MediaComposition composition,
) {
  final fit = switch (layer) {
    MediaVideoLayer() => layer.fit,
    MediaImageLayer() => layer.fit,
    _ => throw StateError('not a visual layer'),
  };
  final opacity = switch (layer) {
    MediaVideoLayer() => layer.opacity,
    MediaImageLayer() => layer.opacity,
    _ => throw StateError('not a visual layer'),
  };
  final place = _placement(layer, composition);
  final width = place.width;
  final height = place.height;
  final sizing = switch (fit) {
    MediaFit.fill => 'format=rgba,scale=$width:$height',
    MediaFit.contain =>
      'format=rgba,scale=$width:$height:force_original_aspect_ratio=decrease,'
          'pad=$width:$height:(ow-iw)/2:(oh-ih)/2:color=black@0',
    MediaFit.cover =>
      'format=rgba,scale=$width:$height:force_original_aspect_ratio=increase,'
          'crop=$width:$height',
  };
  final alpha = opacity == 1
      ? ''
      : ',format=rgba,colorchannelmixer=aa=${opacity.toStringAsFixed(4)}';
  final hold = _holdOf(layer);
  final timing = hold == MediaTime.zero
      ? 'setpts=PTS-STARTPTS+${_seconds(layer.timelineStart)}/TB'
      : 'setpts=PTS-STARTPTS,'
            'tpad=stop_duration=${_seconds(hold)}:stop_mode=clone,'
            'setpts=PTS-STARTPTS+${_seconds(layer.timelineStart)}/TB';
  return '[$input]setpts=PTS-STARTPTS,'
      'trim=start=${_seconds(layer.sourceRange.start)}:'
      'duration=${_seconds(layer.sourceRange.duration)},'
      '$timing,$sizing$alpha${_arrivalFade(layer)}[$label]';
}

String _arrivalFade(MediaLayer layer) {
  final transition = _transitionOf(layer);
  if (transition == null || transition.kind != MediaTransitionKind.dissolve) {
    return '';
  }
  return ',format=rgba,fade=t=in:st=${_seconds(layer.timelineStart)}:'
      'd=${_seconds(transition.duration)}:alpha=1';
}

String _overlayFilter(
  String base,
  String layerLabel,
  String output,
  MediaLayer layer,
  MediaComposition composition,
) {
  final place = _placement(layer, composition);
  final hold = _holdOf(layer);
  final end = MediaTime.microseconds(
    (layer.timelineEnd.microseconds + hold.microseconds).clamp(
      0,
      composition.duration.microseconds,
    ),
  );
  return '[$base][$layerLabel]'
      'overlay=x=${_slideExpression(layer, place, composition, horizontal: true)}'
      ':y=${_slideExpression(layer, place, composition, horizontal: false)}'
      ':eof_action=pass:repeatlast=0:'
      "enable='gte(t,${_seconds(layer.timelineStart)})*"
      "lt(t,${_seconds(end)})'[$output]";
}

String _slideExpression(
  MediaLayer layer,
  _Placement place,
  MediaComposition composition, {
  required bool horizontal,
}) {
  final settled = horizontal ? place.left : place.top;
  final transition = _transitionOf(layer);
  final offscreen = switch (transition?.kind) {
    MediaTransitionKind.slideFromLeft when horizontal => -place.width,
    MediaTransitionKind.slideFromRight when horizontal => composition.width,
    MediaTransitionKind.slideFromTop when !horizontal => -place.height,
    MediaTransitionKind.slideFromBottom when !horizontal => composition.height,
    _ => null,
  };
  if (offscreen == null || transition == null) return '$settled';
  final from = _seconds(layer.timelineStart);
  final until = _seconds(layer.timelineStart + transition.duration);
  final span = _seconds(transition.duration);
  final travel = settled - offscreen;
  final term = travel < 0 ? '-${-travel}' : '+$travel';
  return "'if(lt(t,$until),"
      '$offscreen$term*(t-$from)/$span,$settled)\'';
}

/// The flat colour a dip passes through, laid over everything composited so
/// far and taken away again once the next picture is established.
List<String> _dipFilters(
  String base,
  String source,
  String faded,
  String output,
  MediaLayer layer,
  MediaComposition composition,
) {
  final transition = _transitionOf(layer)!;
  final duration = transition.duration;
  final half = _half(duration);
  final start = transition.overCut
      ? MediaTime.microseconds(
          (layer.timelineStart.microseconds - half.microseconds).clamp(
            0,
            composition.duration.microseconds,
          ),
        )
      : layer.timelineStart;
  final ramps = transition.overCut
      ? 'fade=t=in:st=${_seconds(MediaTime.zero)}:d=${_seconds(half)}:alpha=1,'
            'fade=t=out:st=${_seconds(half)}:d=${_seconds(half)}:alpha=1'
      : 'fade=t=out:st=${_seconds(MediaTime.zero)}:'
            'd=${_seconds(duration)}:alpha=1';
  final end = MediaTime.microseconds(
    (start.microseconds + duration.microseconds).clamp(
      0,
      composition.duration.microseconds,
    ),
  );
  return [
    'color=c=0x${transition.color}:s=${composition.width}x'
        '${composition.height}:r=${composition.framesPerSecond}'
        ':d=${_seconds(duration)}[$source]',
    '[$source]format=rgba,$ramps,'
        'setpts=PTS-STARTPTS+${_seconds(start)}/TB[$faded]',
    '[$base][$faded]overlay=x=0:y=0:eof_action=pass:repeatlast=0:'
        "enable='gte(t,${_seconds(start)})*lt(t,${_seconds(end)})'[$output]",
  ];
}

String _streamLabel(
  int input,
  String kind,
  Map<int, int> counts,
  Map<int, int> uses,
) {
  if (counts[input] == 1) return '$input:$kind';
  final use = uses[input] ?? 0;
  uses[input] = use + 1;
  return 'input$input$kind$use';
}

void _validateOutput(MediaOutputSettings output, MediaLimits limits) {
  if (output.videoBitrate <= 0 ||
      output.videoBitrate > limits.maxVideoBitrate ||
      output.audioBitrate <= 0 ||
      output.audioBitrate > limits.maxAudioBitrate) {
    throw const EditorValidationException('Output bitrate is out of bounds.');
  }
  final webm = output.container == MediaContainer.webm;
  if (webm &&
      (output.videoCodec == MediaVideoCodec.h264 ||
          output.videoCodec == MediaVideoCodec.mpeg4 ||
          output.audioCodec == MediaAudioCodec.aac)) {
    throw const EditorValidationException('WebM requires VP9 and Opus.');
  }
  if (!webm &&
      (output.videoCodec == MediaVideoCodec.vp9 ||
          output.audioCodec == MediaAudioCodec.opus)) {
    throw const EditorValidationException(
      'MP4/MOV requires H.264/MPEG-4 and AAC.',
    );
  }
}

String _videoEncoder(MediaOutputSettings output) => switch (output.videoCodec) {
  MediaVideoCodec.h264 => 'libx264',
  MediaVideoCodec.vp9 => 'libvpx-vp9',
  MediaVideoCodec.mpeg4 => 'mpeg4',
  MediaVideoCodec.automatic =>
    output.container == MediaContainer.webm ? 'libvpx-vp9' : 'mpeg4',
};

String _audioEncoder(MediaOutputSettings output) => switch (output.audioCodec) {
  MediaAudioCodec.aac => 'aac',
  MediaAudioCodec.opus => 'libopus',
  MediaAudioCodec.automatic =>
    output.container == MediaContainer.webm ? 'libopus' : 'aac',
};

String _extension(MediaContainer value) => switch (value) {
  MediaContainer.mp4 => 'mp4',
  MediaContainer.webm => 'webm',
  MediaContainer.mov => 'mov',
};

String _muxer(MediaContainer value) => switch (value) {
  MediaContainer.mp4 => 'mp4',
  MediaContainer.webm => 'webm',
  MediaContainer.mov => 'mov',
};

String _mediaType(MediaContainer value) => switch (value) {
  MediaContainer.mp4 => 'video/mp4',
  MediaContainer.webm => 'video/webm',
  MediaContainer.mov => 'video/quicktime',
};

String _seconds(MediaTime value) {
  final whole = value.microseconds ~/ Duration.microsecondsPerSecond;
  final fraction = value.microseconds.remainder(Duration.microsecondsPerSecond);
  return '$whole.${fraction.toString().padLeft(6, '0')}';
}

String _milliseconds(MediaTime value) {
  final whole = value.microseconds ~/ Duration.microsecondsPerMillisecond;
  final fraction = value.microseconds.remainder(
    Duration.microsecondsPerMillisecond,
  );
  return '$whole.${fraction.toString().padLeft(3, '0')}';
}
