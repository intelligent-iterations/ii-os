import 'package:ii_os_functions/src/api_error.dart';
import 'package:ii_os_functions/src/workspace_prompt_enhancement.dart';
import 'package:test/test.dart';

const _secretVersion =
    'projects/example-project/secrets/deepseek-api-key/versions/latest';

Matcher _apiError(String code) =>
    throwsA(isA<ApiError>().having((error) => error.code, 'code', code));

void main() {
  test('accepts an enabled DeepSeek Google secret version reference', () {
    expect(
      validatedPromptEnhancement({
        'provider': 'deepseek',
        'enabled': true,
        'apiKeySecretVersion': _secretVersion,
      }),
      {
        'provider': 'deepseek',
        'enabled': true,
        'apiKeySecretVersion': _secretVersion,
        'hasApiKey': false,
        'apiKeyLast4': '',
      },
    );
  });

  test('lets a disabled workspace omit every credential', () {
    expect(
      validatedPromptEnhancement({
        'provider': 'deepseek',
        'enabled': false,
        'apiKeySecretVersion': '',
      }),
      {
        'provider': 'deepseek',
        'enabled': false,
        'apiKeySecretVersion': '',
        'hasApiKey': false,
        'apiKeyLast4': '',
      },
    );
  });

  test('a stored key is credential enough to enable enhancement', () {
    expect(
      validatedPromptEnhancement({
        'provider': 'deepseek',
        'enabled': true,
        'apiKeySecretVersion': '',
        'hasApiKey': true,
        'apiKeyLast4': 'a1b2',
      }),
      {
        'provider': 'deepseek',
        'enabled': true,
        'apiKeySecretVersion': '',
        'hasApiKey': true,
        'apiKeyLast4': 'a1b2',
      },
    );
  });

  test('rejects a malformed secret version resource', () {
    for (final value in ['deepseek-api-key', 'projects/p/secrets/s']) {
      expect(
        () => validatedPromptEnhancement({
          'provider': 'deepseek',
          'enabled': true,
          'apiKeySecretVersion': value,
        }),
        _apiError('invalid_deepseek_secret'),
        reason: value,
      );
    }
  });

  test('refuses to enable enhancement with no credential at all', () {
    expect(
      () => validatedPromptEnhancement({
        'provider': 'deepseek',
        'enabled': true,
        'apiKeySecretVersion': '',
      }),
      _apiError('missing_deepseek_credential'),
    );
  });

  test('fails closed when a pasted key reaches the workspace document', () {
    expect(
      () => validatedPromptEnhancement({
        'provider': 'deepseek',
        'enabled': true,
        'apiKeySecretVersion': '',
        'apiKey': 'sk-live-should-never-be-persisted',
      }),
      _apiError('unstored_prompt_enhancement_key'),
    );
  });

  group('parsePromptEnhancement', () {
    test('separates the pasted key from the persisted configuration', () {
      final submission = parsePromptEnhancement({
        'provider': 'deepseek',
        'enabled': true,
        'apiKeySecretVersion': '',
        'apiKey': '  sk-example-key-value  ',
      });

      expect(submission.enabled, isTrue);
      expect(submission.hasPastedKey, isTrue);
      expect(submission.apiKey, 'sk-example-key-value');
      expect(submission.clearApiKey, isFalse);
    });

    test('an untouched key field keeps whatever is installed', () {
      final submission = parsePromptEnhancement({
        'provider': 'deepseek',
        'enabled': true,
        'apiKeySecretVersion': _secretVersion,
      });

      expect(submission.hasPastedKey, isFalse);
      expect(submission.clearApiKey, isFalse);
    });

    test('rejects a key that is too short to be one', () {
      expect(
        () => parsePromptEnhancement({
          'provider': 'deepseek',
          'enabled': true,
          'apiKeySecretVersion': '',
          'apiKey': 'sk-1',
        }),
        _apiError('invalid_deepseek_api_key'),
      );
    });

    test('refuses to both set and clear the key', () {
      expect(
        () => parsePromptEnhancement({
          'provider': 'deepseek',
          'enabled': false,
          'apiKeySecretVersion': '',
          'apiKey': 'sk-example-key-value',
          'clearApiKey': true,
        }),
        _apiError('invalid_prompt_enhancement'),
      );
    });

    test('rejects an unknown field rather than ignoring it', () {
      expect(
        () => parsePromptEnhancement({
          'provider': 'deepseek',
          'enabled': false,
          'apiKeySecretVersion': '',
          'apiKeyPlaintext': 'sk-example-key-value',
        }),
        _apiError('invalid_prompt_enhancement'),
      );
    });
  });

  group('promptEnhancementDocument', () {
    test('records the key state it is given, not the one submitted', () {
      final submission = parsePromptEnhancement({
        'provider': 'deepseek',
        'enabled': true,
        'apiKeySecretVersion': '',
        'apiKey': 'sk-example-key-value',
      });

      expect(
        promptEnhancementDocument(
          submission: submission,
          hasApiKey: true,
          apiKeyLast4: 'alue',
        ),
        {
          'provider': 'deepseek',
          'enabled': true,
          'apiKeySecretVersion': '',
          'hasApiKey': true,
          'apiKeyLast4': 'alue',
        },
      );
    });

    test('drops a stale tail when no key is installed', () {
      final submission = parsePromptEnhancement({
        'provider': 'deepseek',
        'enabled': false,
        'apiKeySecretVersion': '',
      });

      expect(
        promptEnhancementDocument(
          submission: submission,
          hasApiKey: false,
          apiKeyLast4: 'alue',
        )['apiKeyLast4'],
        '',
      );
    });
  });
}
