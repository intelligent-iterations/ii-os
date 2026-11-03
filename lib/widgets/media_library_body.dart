import 'package:flutter/material.dart';
import 'package:ii_os_design_system/ii_os_design_system.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../models/generation_history.dart';
import '../repositories/generation_history_repository.dart';
import 'media_library_view.dart';

/// The four states a library grid can be in: loading, unavailable, empty, and
/// the pictures. Each one grew a different spinner and a different silence
/// while they lived inside the loader.
class MediaLibraryBody extends StatelessWidget {
  const MediaLibraryBody({
    required this.history,
    required this.entries,
    required this.kindLabel,
    required this.loadPreview,
    required this.scroll,
    required this.onPick,
    required this.onLoadMore,
    required this.onRetry,
    super.key,
    this.chosen = const <String>{},
    this.multiple = false,
  });

  final GenerationHistoryRepository history;
  final List<HistoryEntryModel> entries;
  final String kindLabel;
  final LibraryPreviewLoader loadPreview;
  final ScrollController scroll;
  final ValueChanged<HistoryEntryModel> onPick;
  final VoidCallback onLoadMore;
  final VoidCallback onRetry;

  /// Identities already chosen, when the grid takes several.
  final Set<String> chosen;
  final bool multiple;

  @override
  Widget build(BuildContext context) {
    final error = history.errorMessage;
    if (entries.isEmpty && (history.initializing || history.loadingMore)) {
      return const Center(
        child: SizedBox.square(
          dimension: IiOsIconSize.xl,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    if (entries.isEmpty && error != null) {
      return EmptyState(
        title: 'The asset library is unavailable',
        message: error,
        icon: LucideIcons.triangleAlert,
        action: FilledButton(onPressed: onRetry, child: const Text('Retry')),
      );
    }
    if (entries.isEmpty) {
      return EmptyState(
        title: 'Nothing here yet',
        message: history.hasMore
            ? 'No completed ${kindLabel.toLowerCase()} were found in the '
                  'recent results. You can look further back.'
            : 'Completed ${kindLabel.toLowerCase()} generations in this '
                  'workspace appear here.',
        icon: LucideIcons.images,
        action: history.hasMore
            ? FilledButton(
                onPressed: onLoadMore,
                child: const Text('Look further back'),
              )
            : null,
      );
    }
    return MediaLibraryView(
      entries: entries,
      controller: scroll,
      loadPreview: loadPreview,
      loadingMore: history.loadingMore,
      onPick: onPick,
      chosen: chosen,
      multiple: multiple,
    );
  }
}
