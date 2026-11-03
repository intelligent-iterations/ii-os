import 'package:file_selector/file_selector.dart';

import '../models/minimax_h3_generation_spec.dart';

XTypeGroup minimaxH3ReferenceTypeGroup(MiniMaxH3ReferenceKind kind) =>
    switch (kind) {
      MiniMaxH3ReferenceKind.image => const XTypeGroup(
        label: 'Images',
        extensions: ['jpg', 'jpeg', 'png', 'webp'],
        mimeTypes: ['image/jpeg', 'image/png', 'image/webp'],
      ),
      MiniMaxH3ReferenceKind.video => const XTypeGroup(
        label: 'Videos',
        extensions: ['mp4', 'm4v', 'mov', 'webm'],
        mimeTypes: ['video/mp4', 'video/webm'],
      ),
      MiniMaxH3ReferenceKind.audio => const XTypeGroup(
        label: 'Audio',
        extensions: ['wav', 'mp3', 'm4a', 'aac'],
        mimeTypes: ['audio/wav', 'audio/mpeg', 'audio/mp4'],
      ),
    };
