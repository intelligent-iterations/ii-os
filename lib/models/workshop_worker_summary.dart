String workshopPermissionName(String value) => value
    .split('-')
    .where((part) => part.isNotEmpty)
    .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
    .join(' ');

String workshopWorkerSummary(int workers, Duration? longestRunning) {
  if (workers == 0) return 'No agents working';
  final workerLabel = workers == 1
      ? '1 agent working'
      : '$workers agents working';
  if (longestRunning == null) return workerLabel;
  final minutes = longestRunning.inMinutes;
  final elapsed = minutes < 1
      ? 'less than a minute'
      : minutes < 60
      ? '$minutes min'
      : '${minutes ~/ 60} hr ${minutes % 60} min';
  return '$workerLabel · longest running $elapsed';
}
