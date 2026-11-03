final class ClientErrorRateLimiter {
  ClientErrorRateLimiter({
    this.maxEvents = 10,
    this.maxGlobalEvents = 5,
    this.window = const Duration(minutes: 1),
    this.maximumActors = 2000,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now {
    if (maxEvents < 1 ||
        maxGlobalEvents < 1 ||
        window <= Duration.zero ||
        maximumActors < 1) {
      throw ArgumentError('Client error rate limits must be positive.');
    }
  }

  final int maxEvents;
  final int maxGlobalEvents;
  final Duration window;
  final int maximumActors;
  final DateTime Function() _clock;
  final Map<String, List<DateTime>> _events = {};
  final List<DateTime> _globalEvents = [];

  bool allow(String actorId) {
    final now = _clock().toUtc();
    final cutoff = now.subtract(window);
    _globalEvents.removeWhere((occurredAt) => !occurredAt.isAfter(cutoff));
    final events = _events.putIfAbsent(actorId, () => []);
    events.removeWhere((occurredAt) => !occurredAt.isAfter(cutoff));
    if (events.length >= maxEvents || _globalEvents.length >= maxGlobalEvents) {
      return false;
    }
    events.add(now);
    _globalEvents.add(now);
    if (_events.length > maximumActors) _evictOldestActor(actorId);
    return true;
  }

  void _evictOldestActor(String currentActor) {
    String? oldestActor;
    DateTime? oldestEvent;
    for (final entry in _events.entries) {
      if (entry.key == currentActor || entry.value.isEmpty) continue;
      final candidate = entry.value.last;
      if (oldestEvent == null || candidate.isBefore(oldestEvent)) {
        oldestActor = entry.key;
        oldestEvent = candidate;
      }
    }
    if (oldestActor != null) _events.remove(oldestActor);
  }
}
