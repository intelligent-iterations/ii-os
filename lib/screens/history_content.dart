part of 'history_screen.dart';

class _HistoryGrid extends StatelessWidget {
  const _HistoryGrid({
    required this.controller,
    required this.entries,
    required this.error,
    required this.hasMore,
    required this.loadingMore,
    required this.onLoadMore,
    this.selectedJobId,
    this.selectedObject,
  });

  final AppController controller;
  final List<HistoryEntryModel> entries;
  final String? selectedJobId;
  final String? selectedObject;
  final String? error;
  final bool hasMore;
  final bool loadingMore;
  final Future<void> Function() onLoadMore;


  bool _isSelected(HistoryEntryModel entry) {
    final job = selectedJobId;
    if (job == null || job.isEmpty || entry.jobId != job) return false;
    final object = selectedObject;
    return object == null || object.isEmpty || entry.objectName == object;
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final columns = switch (constraints.maxWidth) {
        >= 1120 => 4,
        >= 780 => 3,
        >= 520 => 2,
        _ => 1,
      };
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (error != null) ...[
            Text(error!, style: const TextStyle(color: IiOsColors.red)),
            IiOsGap.vSm,
          ],
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: entries.length,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: columns == 1 ? 1.12 : 0.8,
            ),
            itemBuilder: (context, index) => _HistoryCard(
              key: ValueKey(entries[index].identity),
              controller: controller,
              workspaceId: controller.workspace!.id,
              entry: entries[index],
              selected: _isSelected(entries[index]),
            ),
          ),
          if (hasMore || loadingMore) ...[
            IiOsGap.vMd,
            Center(
              child: loadingMore
                  ? const CircularProgressIndicator(strokeWidth: 2)
                  : OutlinedButton.icon(
                      onPressed: onLoadMore,
                      icon: const Icon(LucideIcons.chevronsDown, size: 17),
                      label: const Text('Load more'),
                    ),
            ),
          ],
        ],
      );
    },
  );
}
