/// Fails when recurring application timers bypass the reviewed cost policy.
///
/// Run from the ii-os root:
///
///   dart run tool/audit_polling_cost.dart
library;

import 'dart:io';

const _localOnlyPeriodicTimers = {
  'lib/view_models/auth_view_model.dart':
      'updates an in-memory authentication countdown and performs no read',
};

void main() {
  final root = Directory.current;
  if (!File('${root.path}/pubspec.yaml').existsSync()) {
    stderr.writeln('Run from the ii-os package root.');
    exit(2);
  }

  final violations = <String>[];
  var activeOperationTimers = 0;
  var localOnlyTimers = 0;
  final files = Directory('lib')
      .listSync(recursive: true)
      .whereType<File>()
      .where((file) => file.path.endsWith('.dart'))
      .toList(growable: false);
  final timerPattern = RegExp(r'Timer\.periodic\(\s*([^,\n]+)');

  for (final file in files) {
    final path = file.path.replaceAll('\\', '/');
    final source = file.readAsStringSync();
    for (final match in timerPattern.allMatches(source)) {
      final line = '\n'.allMatches(source.substring(0, match.start)).length + 1;
      final localOnlyReason = _localOnlyPeriodicTimers[path];
      if (localOnlyReason != null) {
        localOnlyTimers++;
        continue;
      }
      final intervalExpression = match.group(1)!.trim();
      if (intervalExpression != 'IiOsPollingCostPolicy.activeOperation') {
        violations.add(
          '$path:$line uses Timer.periodic($intervalExpression, ...) without '
          'the terminal active-operation policy.',
        );
        continue;
      }
      activeOperationTimers++;
    }
  }

  if (violations.isNotEmpty) {
    stderr.writeln('Polling cost audit failed:');
    for (final violation in violations) {
      stderr.writeln('  $violation');
    }
    stderr.writeln(
      'Passive network polling is prohibited. A recurring read must be tied '
      'to a user-started operation, use IiOsPollingCostPolicy.activeOperation, '
      'and stop at a documented terminal state.',
    );
    exit(1);
  }

  stdout.writeln(
    'Polling cost audit passed: $activeOperationTimers terminal active-operation '
    'timers use the reviewed cadence; $localOnlyTimers local-only timer is '
    'explicitly exempt.',
  );
}
