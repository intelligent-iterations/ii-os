import 'dart:io';

import 'package:ii_os_functions/src/workflow_catalog.dart';
import 'package:test/test.dart';

/// The workflow kit under examples/implementation is what an operator copies
/// into their connected repository. Its catalog must parse with the same
/// parser the dashboard uses, and every entry must name a workflow the kit
/// actually ships that can receive what ii-os dispatches.
const _kitRoot = '../examples/implementation';

/// Generation ids the dashboard dispatches; the kit serves every one of them.
const _dispatchedGenerationIds = [
  'image-create',
  'image-create-flux2-klein',
  'image-create-qwen-2512',
  'image-create-reference-qwen-2511',
  'image-create-reference-flux2-klein',
  'image-edit',
  'image-inpaint',
  'image-edit-qwen-2511',
  'image-edit-flux2-klein',
  'image-inpaint-qwen',
  'image-to-video',
  'text-to-video-minimax-h3',
  'seedvr2-video-upscale',
  'song-create-acestep-xl-sft',
  'narration-create-chatterbox-tts',
  'classification-open-jev-9b',
  'video-editor-render',
];

void main() {
  final catalog = WorkflowCatalog.parse(
    repository: 'acme-co/example-app',
    repositoryId: 1,
    ref: 'main',
    sha: 'abc123',
    content: File('$_kitRoot/.ii-os/catalog.yaml').readAsStringSync(),
  );

  test('serves every generation id the dashboard dispatches', () {
    final ids = catalog.workflows.map((workflow) => workflow.id).toSet();
    expect(ids, containsAll(_dispatchedGenerationIds));
  });

  test('describes hardware generically', () {
    final source = File('$_kitRoot/.ii-os/catalog.yaml').readAsStringSync();
    for (final line in source.split('\n')) {
      if (!line.trimLeft().startsWith('hardware:')) continue;
      expect(line, contains('NVIDIA GPU'), reason: line);
      expect(line, isNot(contains('RTX')), reason: line);
    }
  });

  for (final workflow in catalog.workflows) {
    group(workflow.id, () {
      final file = File('$_kitRoot/${workflow.dispatchWorkflow}');

      test('dispatches a workflow the kit ships', () {
        expect(file.existsSync(), isTrue, reason: workflow.dispatchWorkflow);
      });

      test('declares every input ii-os may dispatch', () {
        if (!file.existsSync()) return;
        final source = file.readAsStringSync();
        final dispatch = source.substring(
          source.indexOf('workflow_dispatch:'),
          source.indexOf('\npermissions:'),
        );
        for (final name in ['ii_request_id', ...workflow.inputs.keys]) {
          expect(dispatch, contains('\n      $name:\n'), reason: name);
        }
      });

      test('publishes only what the catalog declares', () {
        if (!file.existsSync()) return;
        final source = file.readAsStringSync();
        final declared = RegExp(
          r'allowed-content-types: ([^\n]+)',
        ).firstMatch(source);
        if (declared == null) return;
        final types = declared.group(1)!.split(',').map((type) => type.trim());
        final peers = catalog.workflows.where(
          (other) => other.dispatchWorkflow == workflow.dispatchWorkflow,
        );
        final catalogTypes = {
          for (final peer in peers)
            for (final output in peer.outputs) ...output.contentTypes,
          // A video may be published with a poster image beside it; ii-os
          // verifies posters as their own artifacts, outside the catalog.
          if (peers.any(
            (peer) => peer.outputs.any((o) => o.kind == 'video'),
          )) ...const ['image/png', 'image/jpeg', 'image/webp'],
        };
        expect(catalogTypes, containsAll(types));
        final maxBytes = int.parse(
          RegExp(r'max-bytes: "(\d+)"').firstMatch(source)!.group(1)!,
        );
        final catalogMax = peers
            .expand((peer) => peer.outputs)
            .map((output) => output.maxBytes)
            .reduce((a, b) => a > b ? a : b);
        expect(maxBytes, lessThanOrEqualTo(catalogMax));
      });
    });
  }
}
