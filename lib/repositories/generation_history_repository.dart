import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/generation_history.dart';
import '../models/models.dart';
import '../services/api_client.dart';

typedef GenerationHistoryPageLoader =
    Future<JsonMap> Function(Map<String, String> query);

final class GenerationHistoryRepository extends ChangeNotifier {
  GenerationHistoryRepository({
    required ApiClient api,
    required this.workspaceId,
    required this.retentionDays,
    this.pageSize = 20,
    this.freshFor = const Duration(seconds: 10),
  }) : _loadPage = ((query) =>
           api.get('v1/workspaces/$workspaceId/jobs', query: query));

  @visibleForTesting
  GenerationHistoryRepository.withLoader({
    required GenerationHistoryPageLoader loader,
    required this.workspaceId,
    required this.retentionDays,
    this.pageSize = 20,
    this.freshFor = const Duration(seconds: 10),
  }) : _loadPage = loader;

  final String workspaceId;
  final int retentionDays;
  final int pageSize;

  /// How long a completed sync answers the next request for one.
  ///
  /// Several media fields on a screen each open a picker against this shared
  /// repository and each asks it to refresh. The delta sync is cheap but not
  /// free, and the second and third can only return what the first already
  /// brought back.
  final Duration freshFor;
  final GenerationHistoryPageLoader _loadPage;
  DateTime? _syncedAt;
  final Map<String, JsonMap> _jobs = {};

  // A burst of jobs without the requested media kind should not hide older
  // matches, but one screen load must not turn into an unbounded scan of the
  // workspace's retained jobs. The picker offers another explicit bounded
  // batch when this limit is reached.
  static const int _maxEmptyPagesPerLoad = 5;

  List<HistoryEntryModel> _entries = const [];
  String? _nextCursor;
  String? _syncAfter;
  String? _errorMessage;
  bool _initializing = false;
  bool _refreshing = false;
  bool _loadingMore = false;
  bool _disposed = false;
  bool _hasMore = false;

  List<HistoryEntryModel> get entries => _entries;
  String? get errorMessage => _errorMessage;
  bool get initializing => _initializing;
  bool get refreshing => _refreshing;
  bool get loadingMore => _loadingMore;
  bool get hasMore => _hasMore;

  void startWatching() {
    if (_disposed) return;
    if (_entries.isEmpty) {
      unawaited(loadInitial());
    } else {
      unawaited(refresh());
    }
  }

  void stopWatching() {}

  Future<void> loadInitial({String? contentTypePrefix}) async {
    if (_disposed || _initializing) return;
    _initializing = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final response = await _loadPage({
        'limit': '$pageSize',
        'reconcile': 'false',
      });
      _jobs.clear();
      _mergeJobs(response);
      _applyPageState(response);
      _syncAfter = response['syncAfter']?.toString();
      // A full load is a completed sync, so it opens the freshness window too;
      // otherwise the first picker to open after startup syncs immediately
      // over data it has only just fetched.
      _syncedAt = DateTime.now();
      _rebuildEntries();
      await _loadOlderPagesUntilMediaAdded(
        startingEntryCount: 0,
        contentTypePrefix: contentTypePrefix,
      );
    } on Object catch (error) {
      _errorMessage = error.toString();
    } finally {
      _initializing = false;
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> refresh({bool reportError = false}) async {
    if (_disposed || _refreshing || _initializing) return;
    final syncedAt = _syncedAt;
    if (syncedAt != null && DateTime.now().difference(syncedAt) < freshFor) {
      return;
    }
    final syncAfter = _syncAfter;
    if (syncAfter == null || syncAfter.isEmpty) {
      await loadInitial();
      return;
    }
    _refreshing = true;
    if (reportError) {
      _errorMessage = null;
      notifyListeners();
    }
    try {
      String? cursor;
      while (!_disposed) {
        final response = await _loadPage({
          'limit': '50',
          'reconcile': 'false',
          'changesSince': syncAfter,
          'cursor': ?cursor,
        });
        _mergeJobs(response);
        final hasMoreChanges = response['hasMore'] == true;
        final next = response['nextCursor']?.toString();
        if (!hasMoreChanges || next == null || next.isEmpty) {
          _syncAfter = response['syncAfter']?.toString() ?? _syncAfter;
          break;
        }
        cursor = next;
      }
      _errorMessage = null;
      _syncedAt = DateTime.now();
      _rebuildEntries();
    } on Object catch (error) {
      if (reportError) _errorMessage = error.toString();
    } finally {
      _refreshing = false;
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> loadMore({String? contentTypePrefix}) async {
    final cursor = _nextCursor;
    if (_disposed || _loadingMore || !_hasMore || cursor == null) return;
    _loadingMore = true;
    notifyListeners();
    try {
      await _loadOlderPagesUntilMediaAdded(
        startingEntryCount: _matchingEntryCount(contentTypePrefix),
        contentTypePrefix: contentTypePrefix,
      );
      _errorMessage = null;
    } on Object catch (error) {
      _errorMessage = error.toString();
    } finally {
      _loadingMore = false;
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> _loadOlderPagesUntilMediaAdded({
    required int startingEntryCount,
    required String? contentTypePrefix,
  }) async {
    var pagesLoaded = 0;
    while (!_disposed &&
        _hasMore &&
        _nextCursor != null &&
        _matchingEntryCount(contentTypePrefix) == startingEntryCount &&
        pagesLoaded < _maxEmptyPagesPerLoad) {
      final cursor = _nextCursor!;
      final response = await _loadPage({
        'limit': '$pageSize',
        'reconcile': 'false',
        'cursor': cursor,
      });
      _mergeJobs(response);
      _applyPageState(response);
      _rebuildEntries();
      pagesLoaded += 1;
      if (_nextCursor == cursor) break;
    }
  }

  int _matchingEntryCount(String? contentTypePrefix) {
    if (contentTypePrefix == null) return _entries.length;
    return _entries
        .where((entry) => entry.contentType.startsWith(contentTypePrefix))
        .length;
  }

  void _mergeJobs(JsonMap response) {
    for (final job in (response['jobs'] as List<Object?>? ?? const []).map(
      asJsonMap,
    )) {
      final jobId = job['jobId']?.toString() ?? '';
      if (jobId.isNotEmpty) _jobs[jobId] = job;
    }
  }

  void _applyPageState(JsonMap response) {
    _hasMore = response['hasMore'] == true;
    final cursor = response['nextCursor']?.toString();
    _nextCursor = _hasMore && cursor != null && cursor.isNotEmpty
        ? cursor
        : null;
  }

  void _rebuildEntries() {
    final cutoff = DateTime.now().toUtc().subtract(
      Duration(days: retentionDays),
    );
    final entries = <HistoryEntryModel>[];
    for (final job in _jobs.values) {
      final submittedAt = DateTime.tryParse(
        job['submittedAt']?.toString() ?? job['createdAt']?.toString() ?? '',
      );
      if (submittedAt != null && submittedAt.isBefore(cutoff)) continue;
      final artifacts = (job['artifacts'] as List<Object?>? ?? const [])
          .map(asJsonMap)
          .toList();
      // Indexed before the entries are built: a poster is not a generation in
      // its own right, so it must never become a card, and the artifact it
      // depicts may appear either side of it in the list.
      final posters = <String, JsonMap>{
        for (final artifact in artifacts)
          if (artifact['role'] == 'poster' && artifact['poster_for'] is String)
            artifact['poster_for']! as String: artifact,
      };
      for (final artifact in artifacts) {
        if (artifact['role'] == 'poster') continue;
        final entry = HistoryEntryModel.fromJobArtifact(
          job: job,
          artifact: artifact,
          poster: posters[artifact['path']?.toString() ?? ''],
        );
        if (entry.isGeneratedMedia) entries.add(entry);
      }
    }
    entries.sort((left, right) {
      final byDate = (right.submittedAt ?? DateTime(0)).compareTo(
        left.submittedAt ?? DateTime(0),
      );
      return byDate != 0 ? byDate : left.identity.compareTo(right.identity);
    });
    _entries = List.unmodifiable(entries);
  }

  @override
  void dispose() {
    _disposed = true;
    stopWatching();
    super.dispose();
  }
}
