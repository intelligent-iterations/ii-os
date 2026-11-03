import 'package:flutter_test/flutter_test.dart';
import 'package:ii_os/models/prompt_enhancement_settings_change.dart';

void main() {
  test('choosing Secret Manager retires a stored pasted key', () {
    expect(
      promptEnhancementSettingsChange(
        enabled: true,
        usesSecretManager: true,
        secretVersion:
            'projects/example/secrets/deepseek-api-key/versions/latest',
        // A draft can still be in the hidden pasted-key field after switching
        // tabs. It must not keep the old stored key effective.
        pastedApiKey: 'sk-hidden-unsaved-draft',
        hasStoredPastedKey: true,
        removeStoredPastedKey: false,
      ),
      {
        'provider': 'deepseek',
        'enabled': true,
        'apiKeySecretVersion':
            'projects/example/secrets/deepseek-api-key/versions/latest',
        'clearApiKey': true,
      },
    );
  });

  test('a new pasted key replaces removal and yields its safe tail', () {
    final change = promptEnhancementSettingsChange(
      enabled: true,
      usesSecretManager: false,
      secretVersion: '',
      pastedApiKey: 'sk-example-key-value',
      hasStoredPastedKey: true,
      removeStoredPastedKey: true,
    );

    expect(change['apiKey'], 'sk-example-key-value');
    expect(change.containsKey('clearApiKey'), isFalse);
    expect(installedPastedKeyLast4AfterSave(change, current: 'old1'), 'alue');
  });

  test('a successful removal drops the installed-key tail', () {
    expect(
      installedPastedKeyLast4AfterSave(const {
        'clearApiKey': true,
      }, current: 'old1'),
      isEmpty,
    );
  });
}
