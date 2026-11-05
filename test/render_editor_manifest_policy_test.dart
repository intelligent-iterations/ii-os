import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../tool/render_editor_manifest_policy.dart';

void main() {
  group('render input files', () {
    late Directory inputs;

    setUp(() async {
      inputs = await Directory.systemTemp.createTemp('render-policy-test-');
    });

    tearDown(() async {
      await inputs.delete(recursive: true);
    });

    test('resolves a plain input name inside the input directory', () {
      final file = renderInputFile(inputs, 'input-0.mp4');
      expect(file.path, '${inputs.path}/input-0.mp4');
    });

    test('refuses a name that would leave the input directory', () {
      for (final name in ['../secret.mp4', 'nested/input-0.mp4', r'a\b.mp4']) {
        expect(
          () => renderInputFile(inputs, name),
          throwsA(isA<StateError>()),
          reason: name,
        );
      }
    });
  });

  group('render timeout', () {
    test('allows twenty times the running time', () {
      expect(
        renderTimeoutFor(const Duration(minutes: 1)),
        const Duration(minutes: 20),
      );
    });

    test('never drops below five minutes', () {
      expect(
        renderTimeoutFor(const Duration(seconds: 2)),
        const Duration(minutes: 5),
      );
    });

    test('never exceeds thirty minutes', () {
      expect(
        renderTimeoutFor(const Duration(hours: 1)),
        const Duration(minutes: 30),
      );
    });
  });
}
