import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../services/picked_media_reader.dart';
import '../state/app_controller.dart';
import '../widgets/media_picker.dart';

Future<ReadPickedMedia?> pickCharacterImage(
  BuildContext context, {
  required AppController controller,
  required int maxBytes,
}) async {
  final workspace = controller.workspace;
  if (workspace == null) return null;
  const images = XTypeGroup(
    label: 'Images',
    extensions: ['png', 'jpg', 'jpeg', 'webp'],
    mimeTypes: ['image/png', 'image/jpeg', 'image/webp'],
  );
  final picked = await showMediaPicker(
    context: context,
    history: controller.media.history(
      workspaceId: workspace.id,
      retentionDays: workspace.artifactStorage?.retentionDays ?? 30,
    ),
    loadPreview: (entry) => controller.readVerifiedArtifact(
      workspaceId: workspace.id,
      jobId: entry.jobId,
      artifact: entry.previewArtifact ?? entry.artifact,
    ),
    contentTypePrefix: 'image/',
    title: 'Choose character image',
    uploadTypes: const [images],
    maxUploadBytes: maxBytes,
  );
  if (picked == null || !context.mounted) return null;
  return readPickedMedia(
    picked,
    readLibrary: (entry) => controller.readVerifiedArtifact(
      workspaceId: workspace.id,
      jobId: entry.jobId,
      artifact: entry.artifact,
    ),
  );
}
