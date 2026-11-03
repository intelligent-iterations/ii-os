import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ii_ffmpeg_universal/ii_ffmpeg_universal.dart';
import 'package:ii_ffmpeg_universal/src/backend.dart';
import 'package:ii_ffmpeg_universal/src/backends/io_workspace.dart';
import 'package:path/path.dart' as path;

void main() {
  test(
    'destination publication waits for every output validation',
    () async {
      final token =
          'ii-ffmpeg-publication-test-$pid-'
          '${DateTime.now().microsecondsSinceEpoch}';
      final root = await Directory.systemTemp.createTemp(
        'ii_ffmpeg_universal_publication_test_',
      );
      final rootMarker = File(path.join(root.path, '.ii-test-owner'));
      await rootMarker.writeAsString(token, flush: true);
      addTearDown(() async {
        if (!await root.exists()) return;
        if (await rootMarker.exists() &&
            await rootMarker.readAsString() == token) {
          await root.delete(recursive: true);
        }
      });

      final workspace = await IoWorkspace.create(
        'publication',
        root: Directory(path.join(root.path, 'workspaces')),
      );
      addTearDown(() async {
        if (await workspace.directory.exists()) await workspace.dispose();
      });
      final destination = File(path.join(root.path, 'published.bin'));
      await destination.writeAsString('existing-owner-data', flush: true);
      await File(
        workspace.filePath('first.bin'),
      ).writeAsBytes(Uint8List.fromList([1, 2, 3]), flush: true);
      await File(
        workspace.filePath('second.bin'),
      ).writeAsBytes(Uint8List(8), flush: true);
      final job = FfmpegJob(
        id: 'publication',
        arguments: const ['-f', 'rawvideo', 'first.bin'],
        outputs: [
          FfmpegOutput(
            'first.bin',
            destinationPath: destination.path,
            captureBytes: false,
          ),
          const FfmpegOutput('second.bin', maxBytes: 4),
        ],
        overwriteOutput: true,
      );

      await expectLater(
        workspace.collectOutputs(
          job,
          const FfmpegSafetyPolicy(),
          FfmpegExecutionContext(const Duration(seconds: 5)),
        ),
        throwsA(
          isA<FfmpegException>().having(
            (error) => error.code,
            'code',
            FfmpegErrorCode.outputTooLarge,
          ),
        ),
      );
      expect(await destination.readAsString(), 'existing-owner-data');
      await workspace.dispose();
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
