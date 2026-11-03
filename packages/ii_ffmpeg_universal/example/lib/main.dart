import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:ii_ffmpeg_universal/ii_ffmpeg_universal.dart';

import 'desktop_bundle_stub.dart' if (dart.library.io) 'desktop_bundle_io.dart';

const _webCoreScriptSha256 = String.fromEnvironment(
  'II_FFMPEG_WEB_CORE_JS_SHA256',
);
const _webCoreWasmSha256 = String.fromEnvironment(
  'II_FFMPEG_WEB_CORE_WASM_SHA256',
);
void main() => runApp(const UniversalFfmpegExample());

class UniversalFfmpegExample extends StatefulWidget {
  const UniversalFfmpegExample({super.key});

  @override
  State<UniversalFfmpegExample> createState() => _UniversalFfmpegExampleState();
}

class _UniversalFfmpegExampleState extends State<UniversalFfmpegExample> {
  String _status = 'Ready';
  bool _running = false;

  Future<void> _render() async {
    setState(() {
      _running = true;
      _status = 'Loading FFmpeg';
    });
    UniversalFfmpeg? ffmpeg;
    try {
      ffmpeg = UniversalFfmpeg(configuration: await _configuration());
      final result = await ffmpeg.execute(
        FfmpegJob(
          id: 'example-render',
          arguments: const [
            '-f',
            'lavfi',
            '-i',
            'color=c=purple:s=160x90:r=10:d=0.2',
            '-c:v',
            'mpeg4',
            '-frames:v',
            '2',
            '-f',
            'mp4',
            'output.mp4',
          ],
          outputs: const [FfmpegOutput('output.mp4')],
        ),
      );
      if (!mounted) return;
      setState(() {
        _status = result.isSuccess
            ? 'Rendered ${result.outputBytes['output.mp4']!.length} bytes'
            : 'Failed with ${result.exitCode}';
      });
    } catch (error) {
      if (mounted) setState(() => _status = 'Failed: $error');
    } finally {
      await ffmpeg?.dispose();
      if (mounted) setState(() => _running = false);
    }
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    home: Scaffold(
      appBar: AppBar(title: const Text('ii-ffmpeg-universal')),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_running) const CircularProgressIndicator(),
            Text(_status, key: const Key('status')),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _running ? null : _render,
              child: const Text('Render test clip'),
            ),
          ],
        ),
      ),
    ),
  );
}

Future<FfmpegConfiguration> _configuration() async {
  if (kIsWeb) {
    return const FfmpegConfiguration(
      webBundle: FfmpegWebBundle(
        ffmpegScriptUrl: 'ffmpeg/ffmpeg.js',
        ffmpegScriptSha256:
            'ad4cfe957589995dea03fc8de1fd5e9f5cb4558a7282913172203082a65bbfaa',
        coreScriptUrl: 'ffmpeg/ffmpeg-core.js',
        coreScriptSha256: _webCoreScriptSha256,
        coreWasmUrl: 'ffmpeg/ffmpeg-core.wasm',
        coreWasmSha256: _webCoreWasmSha256,
      ),
    );
  }
  if (const {
    TargetPlatform.linux,
    TargetPlatform.macOS,
    TargetPlatform.windows,
  }.contains(defaultTargetPlatform)) {
    return FfmpegConfiguration(
      desktopBundle: await loadExampleDesktopBundle(),
      nativeWorkspaceRoot: exampleNativeWorkspaceRoot(),
    );
  }
  return const FfmpegConfiguration();
}
