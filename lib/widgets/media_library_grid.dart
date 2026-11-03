import 'dart:async';

import 'package:flutter/material.dart';
import 'package:ii_os_design_system/ii_os_design_system.dart';

import '../models/generation_history.dart';
import '../repositories/generation_history_repository.dart';
import 'media_library_body.dart';
import 'media_library_view.dart';

/// The workspace library as a grid of pictures.
/// Pages on scroll and only builds previews for visible tiles.
class MediaLibraryGrid extends StatefulWidget {
  const MediaLibraryGrid({
    required this.history,
    required this.loadPreview,
    required this.onPick,
    this.contentTypePrefix,
    super.key,
    this.chosen = const <String>{},
    this.multiple = false,
  });

  final GenerationHistoryRepository history;
  final LibraryPreviewLoader loadPreview;
  final ValueChanged<HistoryEntryModel> onPick;
  final String? contentTypePrefix;

  /// Identities already chosen, when the picker takes several.
  final Set<String> chosen;
  final bool multiple;

  @override
  State<MediaLibraryGrid> createState() => _MediaLibraryGridState();
}

class _MediaLibraryGridState extends State<MediaLibraryGrid> {
  /// How close to the end the viewer gets before the next page is requested.
  /// Roughly two rows, so the fetch is in flight before they reach the bottom.
  static const _prefetchExtent = IiOsWidths.form;

  final ScrollController _scroll = ScrollController();
  late MediaKind _kind = MediaKind.forPrefix(widget.contentTypePrefix);
  bool _fillKindAfterActiveLoad = false;

  bool get _locked => widget.contentTypePrefix != null;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_maybeLoadMore);
    widget.history.addListener(_changed);
    if (widget.history.entries.isEmpty) {
      unawaited(widget.history.loadInitial(contentTypePrefix: _kind.prefix));
    } else {
      unawaited(_refreshAndFillKind());
    }
  }

  Future<void> _refreshAndFillKind() async {
    await widget.history.refresh(reportError: true);
    if (!mounted || _visible.isNotEmpty) return;
    _loadMore();
  }

  @override
  void dispose() {
    _scroll
      ..removeListener(_maybeLoadMore)
      ..dispose();
    widget.history.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (!mounted) return;
    setState(() {});
    final history = widget.history;
    if (_fillKindAfterActiveLoad &&
        !history.initializing &&
        !history.loadingMore) {
      _fillKindAfterActiveLoad = false;
      if (_visible.isEmpty) _loadMore();
    }
  }

  void _maybeLoadMore() {
    if (!_scroll.hasClients) return;
    final position = _scroll.position;
    if (position.pixels < position.maxScrollExtent - _prefetchExtent) return;
    final history = widget.history;
    if (!history.hasMore || history.loadingMore || history.initializing) return;
    _loadMore();
  }

  void _loadMore() {
    final history = widget.history;
    if (!history.hasMore || history.loadingMore || history.initializing) return;
    unawaited(history.loadMore(contentTypePrefix: _kind.prefix));
  }

  void _retry() {
    unawaited(widget.history.loadInitial(contentTypePrefix: _kind.prefix));
  }

  void _selectKind(MediaKind kind) {
    setState(() => _kind = kind);
    final history = widget.history;
    if (history.initializing || history.loadingMore) {
      _fillKindAfterActiveLoad = true;
      return;
    }
    if (_visible.isEmpty) _loadMore();
  }

  List<HistoryEntryModel> get _visible {
    return widget.history.entries.where(_kind.includes).toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final history = widget.history;
    final entries = _visible;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!_locked)
          MediaLibraryKindSelector(selected: _kind, onSelected: _selectKind),
        Flexible(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: IiOsSpacing.lg),
            child: MediaLibraryBody(
              history: history,
              entries: entries,
              kindLabel: _kind.label,
              loadPreview: widget.loadPreview,
              scroll: _scroll,
              onPick: widget.onPick,
              chosen: widget.chosen,
              multiple: widget.multiple,
              onLoadMore: _loadMore,
              onRetry: _retry,
            ),
          ),
        ),
      ],
    );
  }
}
