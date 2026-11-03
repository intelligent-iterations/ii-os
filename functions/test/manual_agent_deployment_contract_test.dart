import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('human Deploy is the only agent dispatch trigger', () {
    final server = File('bin/server.dart').readAsStringSync();
    final manifest = File('functions.yaml').readAsStringSync();
    final activation = File(
      'lib/src/api_agent_ticket_activation_route.dart',
    ).readAsStringSync();
    final dispatcher = File(
      'lib/src/agent_ticket_dispatcher.dart',
    ).readAsStringSync();
    final workflow = File(
      'lib/src/workflow_agent_dispatch.dart',
    ).readAsStringSync();

    expect(server, isNot(contains("name: 'agentScheduler'")));
    expect(manifest, isNot(contains('agent-scheduler:')));
    expect(manifest, isNot(contains('II_OS_AGENT_SCHEDULER')));
    expect(activation, contains('AgentTicketDispatcher'));
    expect(activation, contains('dispatchHumanDeployment'));
    expect(
      activation.indexOf('await activations.activate('),
      lessThan(activation.indexOf('await github.updateProjectItemField(')),
      reason:
          'the recovery transaction must win before Project status is changed',
    );
    expect(dispatcher, isNot(contains('agentWorkingStatusUpdate(')));
    expect(dispatcher, isNot(contains('github.updateProjectItemField(')));
    expect(workflow, contains("if (state == 'running')"));
    expect(workflow, contains('github.updateProjectItemField('));
  });
}
