import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../services/client_error_reporter.dart';
import '../services/local_playback_asset.dart';
import '../theme/ii_os_theme.dart';
import '../theme/ii_os_tokens.dart';

class AudioPlayerSurface extends StatefulWidget {
  const AudioPlayerSurface({
    required this.url,
    this.errorSource = 'audio.player',
    super.key,
  }) : bytes = null,
       contentType = null;

  const AudioPlayerSurface.memory({
    required this.bytes,
    required this.contentType,
    this.errorSource = 'audio.player',
    super.key,
  }) : url = null;

  final String? url;
  final Uint8List? bytes;
  final String? contentType;
  final String errorSource;

  @override
  State<AudioPlayerSurface> createState() => _AudioPlayerSurfaceState();
}

class _AudioPlayerSurfaceState extends State<AudioPlayerSurface> {
  late final AudioPlayer _player;
  late Future<Duration?> _initializing;
  LocalPlaybackAsset? _asset;
  int _epoch = 0;
  bool _disposed = false;

  @override
  void initState() {
    super.initState();
    _player = AudioPlayer();
    _initializing = _initialize();
  }

  @override
  void didUpdateWidget(covariant AudioPlayerSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url ||
        !identical(oldWidget.bytes, widget.bytes) ||
        oldWidget.contentType != widget.contentType) {
      _initializing = _initialize();
    }
  }

  Future<Duration?> _initialize() async {
    final epoch = ++_epoch;
    final previousAsset = _asset;
    _asset = null;
    try {
      await _player.stop();
      if (previousAsset != null) await previousAsset.dispose();
      final bytes = widget.bytes;
      final String url;
      if (bytes == null) {
        url = widget.url ?? '';
      } else {
        final asset = await LocalPlaybackAsset.create(
          bytes: bytes,
          contentType: widget.contentType ?? 'application/octet-stream',
        );
        if (_disposed || epoch != _epoch) {
          await asset.dispose();
          return null;
        }
        _asset = asset;
        url = asset.uri.toString();
      }
      if (url.isEmpty) throw const FormatException('Audio source missing.');
      if (_disposed || epoch != _epoch) return null;
      return await _player.setUrl(url);
    } on Object catch (error, stackTrace) {
      final failedAsset = _asset;
      _asset = null;
      if (failedAsset != null) await failedAsset.dispose();
      unawaited(
        ClientErrorReporter.reportGlobal(
          error,
          stackTrace,
          source: widget.errorSource,
          route: Uri.tryParse(widget.url ?? '')?.path,
        ),
      );
      rethrow;
    }
  }

  void _retry() {
    setState(() => _initializing = _initialize());
  }

  @override
  void dispose() {
    _disposed = true;
    _epoch++;
    final initializing = _initializing;
    unawaited(
      initializing.catchError((Object _) => null).whenComplete(() async {
        await _player.dispose();
        final asset = _asset;
        _asset = null;
        if (asset != null) await asset.dispose();
      }),
    );
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Duration?>(
      future: _initializing,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(IiOsSpacing.sm),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(LucideIcons.audioLines, color: IiOsColors.muted),
                  IiOsGap.vXs,
                  OutlinedButton.icon(
                    key: const Key('audio-player-retry'),
                    onPressed: _retry,
                    icon: const Icon(LucideIcons.refreshCw, size: 16),
                    label: const Text('Try again'),
                  ),
                ],
              ),
            ),
          );
        }
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator(strokeWidth: 2));
        }
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          child: Row(
            children: [
              const Icon(
                LucideIcons.audioLines,
                size: 28,
                color: IiOsColors.green,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: StreamBuilder<Duration>(
                  stream: _player.positionStream,
                  initialData: Duration.zero,
                  builder: (context, positionSnapshot) {
                    return StreamBuilder<Duration?>(
                      stream: _player.durationStream,
                      initialData: snapshot.data,
                      builder: (context, durationSnapshot) {
                        final duration = durationSnapshot.data ?? Duration.zero;
                        final position = _boundedPosition(
                          positionSnapshot.data ?? Duration.zero,
                          duration,
                        );
                        final max = duration.inMilliseconds.toDouble();
                        final sliderValue = max <= 0
                            ? 0.0
                            : position.inMilliseconds
                                  .toDouble()
                                  .clamp(0, max)
                                  .toDouble();
                        return Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Slider(
                              value: sliderValue,
                              max: max <= 0 ? 1 : max,
                              onChanged: max <= 0
                                  ? null
                                  : (value) => unawaited(
                                      _player.seek(
                                        Duration(milliseconds: value.round()),
                                      ),
                                    ),
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: IiOsSpacing.xs,
                              ),
                              child: Row(
                                children: [
                                  Text(
                                    _formatDuration(position),
                                    style: Theme.of(
                                      context,
                                    ).textTheme.labelSmall,
                                  ),
                                  const Spacer(),
                                  Text(
                                    _formatDuration(duration),
                                    style: Theme.of(
                                      context,
                                    ).textTheme.labelSmall,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        );
                      },
                    );
                  },
                ),
              ),
              const SizedBox(width: 10),
              StreamBuilder<PlayerState>(
                stream: _player.playerStateStream,
                builder: (context, playerSnapshot) {
                  final state = playerSnapshot.data;
                  final loading =
                      state?.processingState == ProcessingState.loading ||
                      state?.processingState == ProcessingState.buffering;
                  if (loading) {
                    return const SizedBox.square(
                      dimension: 42,
                      child: Padding(
                        padding: EdgeInsets.all(10),
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    );
                  }
                  final playing = state?.playing == true;
                  return IconButton.filled(
                    tooltip: playing ? 'Pause song' : 'Play song',
                    onPressed: () {
                      if (playing) {
                        unawaited(_player.pause());
                      } else {
                        unawaited(_playFromCurrentPosition());
                      }
                    },
                    icon: Icon(playing ? LucideIcons.pause : LucideIcons.play),
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _playFromCurrentPosition() async {
    if (_player.processingState == ProcessingState.completed) {
      await _player.seek(Duration.zero);
    }
    await _player.play();
  }
}

Duration _boundedPosition(Duration position, Duration duration) {
  if (duration <= Duration.zero || position <= duration) return position;
  return duration;
}

String _formatDuration(Duration value) {
  final minutes = value.inMinutes;
  final seconds = value.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '$minutes:$seconds';
}
