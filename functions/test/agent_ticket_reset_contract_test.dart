import 'dart:io';

import 'package:test/test.dart';

void main() {
  test(
    'reset is two-phase, preserves tickets, and has no recurring trigger',
    () {
      final route = File(
        'lib/src/api_agent_ticket_reset_route.dart',
      ).readAsStringSync();
      final github = File('lib/src/github_projects.dart').readAsStringSync();
      final manifest = File('functions.yaml').readAsStringSync();

      expect(route, contains('beginReset('));
      expect(route, contains('clearProjectItemField('));
      expect(route, contains('clearIssueLabels('));
      expect(route, contains('completeReset('));
      expect(
        route.indexOf('beginReset('),
        lessThan(route.indexOf('clearProjectItemField(')),
      );
      expect(
        route.indexOf('clearProjectItemField('),
        lessThan(route.indexOf('clearIssueLabels(')),
      );
      expect(
        route.indexOf('clearIssueLabels('),
        lessThan(route.indexOf('completeReset(')),
      );
      expect(route, isNot(contains('updateIssue(')));
      expect(route, isNot(contains('deleteProjectV2Item')));
      expect(route, contains("'preservesIssue': true"));
      expect(route, contains("'clearsLabels': true"));
      expect(
        File('lib/src/github_client.dart').readAsStringSync(),
        contains("body: {'labels': <String>[]}"),
      );
      expect(github, contains('clearProjectV2ItemFieldValue'));
      expect(manifest, isNot(contains('ticket-reset-scheduler')));
    },
  );
}
