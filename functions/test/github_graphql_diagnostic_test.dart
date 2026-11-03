import 'package:ii_os_functions/src/github_app_transport.dart';
import 'package:test/test.dart';

void main() {
  test('keeps GraphQL detail internal and bounded for error telemetry', () {
    final diagnostic = githubGraphqlDiagnostic([
      {
        'type': 'FORBIDDEN',
        'path': ['node', 'items'],
        'message': 'Resource not accessible by integration',
      },
    ], statusCode: 200);

    expect(diagnostic, contains('FORBIDDEN'));
    expect(diagnostic, contains('node.items'));
    expect(diagnostic, contains('Resource not accessible by integration'));
    expect(diagnostic.length, lessThanOrEqualTo(1200));
  });
}
