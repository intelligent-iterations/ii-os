/// Cost-reviewed cadence for a user-started operation with a terminal state.
///
/// Passive collection, feed, and snapshot polling is intentionally absent.
/// Those surfaces refresh only on an explicit user action or a push event.
abstract final class IiOsPollingCostPolicy {
  /// One explicitly active operation whose watcher stops at a terminal state.
  static const activeOperation = Duration(seconds: 2);
}
