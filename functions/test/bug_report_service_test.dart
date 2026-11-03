import 'package:ii_os_functions/src/api_error.dart';
import 'package:ii_os_functions/src/bug_report_service.dart';
import 'package:test/test.dart';

void main() {
  group('BugReportInput', () {
    test('normalizes user details and bounded client context', () {
      final input = BugReportInput.parse({
        'description': '  The preview stayed empty.  ',
        'expectedBehavior': '  The generated image should appear. ',
        'route': '/workspaces/workspace-1/generate',
        'clientPlatform': 'web',
        'screenshotId': '123e4567-e89b-42d3-a456-426614174000',
      });

      expect(input.description, 'The preview stayed empty.');
      expect(input.expectedBehavior, 'The generated image should appear.');
      expect(input.route, '/workspaces/workspace-1/generate');
      expect(input.clientPlatform, 'web');
      expect(input.screenshotId, '123e4567-e89b-42d3-a456-426614174000');
    });

    test('requires a description and app-relative route', () {
      expect(
        () => BugReportInput.parse({'description': '   '}),
        throwsA(_apiError('invalid_bug_report')),
      );
      expect(
        () => BugReportInput.parse({
          'description': 'Something broke.',
          'route': 'https://example.com/private?token=secret',
        }),
        throwsA(_apiError('invalid_bug_report')),
      );
    });
  });

  group('BugReportScreenshotSpec', () {
    test('normalizes a supported screenshot filename', () {
      final spec = BugReportScreenshotSpec.parse({
        'filename': r'../Broken preview (1).PNG',
        'contentType': 'image/png',
        'sizeBytes': 2048,
        'sha256': List.filled(32, 'AB').join(),
      });

      expect(spec.safeFilename, 'Broken-preview-1.png');
      expect(spec.sizeBytes, 2048);
      expect(spec.sha256, List.filled(32, 'ab').join());
    });

    test('rejects unsupported or oversized screenshots', () {
      for (final metadata in [
        {
          'filename': 'bug.gif',
          'contentType': 'image/gif',
          'sizeBytes': 100,
          'sha256': List.filled(64, 'a').join(),
        },
        {
          'filename': 'bug.png',
          'contentType': 'image/png',
          'sizeBytes': 10 * 1024 * 1024 + 1,
          'sha256': List.filled(64, 'a').join(),
        },
      ]) {
        expect(
          () => BugReportScreenshotSpec.parse(metadata),
          throwsA(_apiError('invalid_bug_report_screenshot')),
        );
      }
    });
  });
}

Matcher _apiError(String code) =>
    isA<ApiError>().having((error) => error.code, 'code', code);
