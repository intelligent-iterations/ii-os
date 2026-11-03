@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ii_flutter_video_editor/ii_flutter_video_editor.dart';
import 'package:ii_os/services/editor_media_source.dart';
import 'package:ii_os/services/video_editor_ffmpeg.dart';
import 'package:ii_os/services/video_editor_ffmpeg_workspace.dart';

/// Stands in for the owned temp workspace on a host that has one.
const _workspaceRoot = '/tmp/ii_os_video_editor_workspaces_v1';

void main() {
  group('render target profiles', () {
    test('web and native limits are explicit and internally valid', () {
      final web = videoEditorRenderTargetFor(browser: true);
      final native = videoEditorRenderTargetFor(browser: false);

      expect(() => web.validate(), returnsNormally);
      expect(() => native.validate(), returnsNormally);
      expect(web.editorLimits.maxDuration, const Duration(minutes: 2));
      expect(native.editorLimits.maxDuration, const Duration(minutes: 20));
      expect(web.maxOutputBytes, 64 * 1024 * 1024);
      expect(native.maxOutputBytes, 512 * 1024 * 1024);
      expect(web.maxInputBytes, 128 * 1024 * 1024);
      expect(native.maxInputBytes, 320 * 1024 * 1024);
      expect(web.maxDeclaredMediaBytes, 112 * 1024 * 1024);
      expect(native.maxDeclaredMediaBytes, 256 * 1024 * 1024);
      expect(
        web.maxDeclaredMediaBytes + web.editorLimits.maxCaptionTotalRasterBytes,
        web.maxInputBytes,
      );
      expect(
        native.maxDeclaredMediaBytes +
            native.editorLimits.maxCaptionTotalRasterBytes,
        native.maxInputBytes,
      );
      expect(web.maxEstimatedOutputBytes, web.maxOutputBytes * 92 ~/ 100);
      expect(native.maxEstimatedOutputBytes, native.maxOutputBytes * 92 ~/ 100);
      expect(videoEditorCompiler.target, same(videoEditorRenderTarget));
      expect(maxEditorSourceBytes, videoEditorRenderTarget.maxSourceBytes);
      expect(
        maxEditorTotalSourceBytes,
        videoEditorRenderTarget.maxDeclaredMediaBytes,
      );
      expect(maxEditorOutputBytes, videoEditorRenderTarget.maxOutputBytes);
      expect(
        maxEditorDuration,
        videoEditorRenderTarget.editorLimits.maxDuration,
      );
    });

    test('web output headroom rejects two minutes at the default bitrate', () {
      final compiler = EditorCompositionCompiler.forTarget(
        videoEditorRenderTargetFor(browser: true),
      );

      final below = compiler.preflight(_outputProject(119));
      final over = compiler.preflight(_outputProject(120));

      expect(below.isStructurallyFeasible, isTrue);
      expect(over.isStructurallyFeasible, isFalse);
      expect(
        over.issues.map((issue) => issue.code),
        contains(EditorRenderIssueCode.estimatedOutputBytesExceeded),
      );
    });
  });

  test('desktop FFmpeg receives its dedicated owned workspace root', () {
    final expected = videoEditorNativeWorkspaceRoot();
    final configuration = videoEditorFfmpegConfiguration();

    if (Platform.isLinux || Platform.isMacOS) {
      expect(expected, isNotNull);
      expect(Directory(expected!).isAbsolute, isTrue);
      expect(expected, endsWith('ii_os_video_editor_workspaces_v1'));
      expect(configuration.nativeWorkspaceRoot, expected);
    } else {
      expect(expected, isNull);
      expect(configuration.nativeWorkspaceRoot, isNull);
    }
  });

  group('videoEditorUsesDesktopBundle', () {
    test('every desktop platform gets the bundle', () {
      // Linux and macOS reach it through their owned workspace; Windows has
      // none and must still be recognised.
      for (final platform in const [
        TargetPlatform.linux,
        TargetPlatform.macOS,
      ]) {
        expect(
          videoEditorUsesDesktopBundle(
            platform: platform,
            nativeWorkspaceRoot: _workspaceRoot,
          ),
          isTrue,
          reason: '$platform',
        );
      }
    });

    test('Windows gets the bundle without an owned workspace', () {
      // The regression this guards: deriving desktop from the workspace root
      // alone drops Windows, because only Linux and macOS get a root. Windows
      // then silently loses its bundled binaries.
      expect(
        videoEditorUsesDesktopBundle(
          platform: TargetPlatform.windows,
          nativeWorkspaceRoot: null,
        ),
        isTrue,
      );
    });

    test('mobile never gets the desktop bundle', () {
      for (final platform in const [
        TargetPlatform.android,
        TargetPlatform.iOS,
        TargetPlatform.fuchsia,
      ]) {
        expect(
          videoEditorUsesDesktopBundle(
            platform: platform,
            nativeWorkspaceRoot: null,
          ),
          isFalse,
          reason: '$platform',
        );
      }
    });
  });
}

EditorProject _outputProject(int seconds) => EditorProject(
  id: 'output-project',
  width: 640,
  height: 360,
  framesPerSecond: 30,
  duration: MediaTime.seconds(seconds),
  lanes: const [],
  output: const MediaOutputSettings(
    container: MediaContainer.webm,
    videoCodec: MediaVideoCodec.vp9,
    audioCodec: MediaAudioCodec.opus,
    videoBitrate: 4 * 1000 * 1000,
    audioBitrate: 128 * 1000,
  ),
);
