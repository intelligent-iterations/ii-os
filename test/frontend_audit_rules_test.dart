import 'package:flutter_test/flutter_test.dart';

import '../tool/frontend_audit_rules.dart';

void main() {
  group('blankNonCode', () {
    test('blanks literal text but keeps interpolated code visible', () {
      // The regression this guards: the workshop health card rendered
      // '* ${check.label}: ${check.guidance}' -- operator vocabulary on a
      // primary surface -- and R12 reported the file clean, because the whole
      // line sat inside quotes and was blanked before any rule read it.
      const source = "final s = '\u2022 \${check.label}: \${check.guidance}';";
      final blanked = blankNonCode(source);

      expect(blanked, contains('check.label'));
      expect(blanked, contains('check.guidance'));
      expect(blanked, isNot(contains('\u2022')));
      expect(
        blanked.length,
        source.length,
        reason: 'offsets must stay meaningful for line reporting',
      );
    });

    test('treats a string nested in an interpolation as text again', () {
      const source = "final s = '\${a ? 'yes' : check.detail}';";
      final blanked = blankNonCode(source);

      expect(blanked, contains('check.detail'));
      expect(blanked, isNot(contains('yes')));
    });

    test(
      'does not let a brace inside a nested string end the interpolation',
      () {
        const source = "final s = '\${fmt('}')} \${check.label}';";
        final blanked = blankNonCode(source);

        expect(blanked, contains('check.label'));
      },
    );

    test('leaves a raw string wholly blank', () {
      const source = r"final s = r'${check.label}';";
      final blanked = blankNonCode(source);

      expect(blanked, isNot(contains('check.label')));
      expect(blanked.length, source.length);
    });

    test('still blanks comments and preserves line numbers', () {
      const source = '// check.label\nfinal a = 1;';
      final blanked = blankNonCode(source);

      expect(blanked, isNot(contains('check.label')));
      expect(blanked.split('\n').length, 2);
      expect(blanked, contains('final a = 1;'));
    });
  });

  group('blankComments', () {
    test('keeps a string literal so its interpolation stays visible', () {
      // blankNonCode blanks a bare `\$error` as literal text, which is why
      // R21 cannot use it: the thing the rule exists to find would be gone
      // before the rule ran.
      const source = "final s = 'failed: \$error';";
      expect(blankComments(source), contains('\$error'));
    });

    test('removes a comment that merely mentions one', () {
      const source = '/// Never write \$error into copy.\nfinal a = 1;';
      final blanked = blankComments(source);

      expect(blanked, isNot(contains('\$error')));
      expect(blanked, contains('final a = 1;'));
    });

    test('preserves newlines so reported line numbers stay true', () {
      const source = '/* a\nb */\nfinal a = 1;';

      expect(
        blankComments(source).split('\n').length,
        source.split('\n').length,
      );
    });

    test('does not let a quote inside a comment swallow the file', () {
      const source = "// it's fine\nfinal s = '\$error';";

      expect(blankComments(source), contains('\$error'));
    });
  });

  group('R19 behaviour is reachable from a test', () {
    test('flags a private extension on a private State', () {
      // _SoftwareWorkshopActions held fourteen methods that merged pull
      // requests, deleted tickets and paused agents. Nothing could reach them
      // except by rendering the screen, and the only thing that renders a
      // screen is a golden, which CI does not run.
      final files = [
        SourceFile(
          'lib/screens/software_workshop_screen_actions.dart',
          'extension _SoftwareWorkshopActions '
              'on _SoftwareWorkshopScreenState {}\n',
        ),
      ];

      final found = checkBehaviourIsTestable(files);

      expect(found, hasLength(1));
      expect(found.single.rule, 'R19');
      expect(found.single.line, 1);
    });

    test('allows an extension a test can construct the receiver for', () {
      final files = [
        SourceFile(
          'lib/view_models/workshop_view_model.dart',
          'extension WorkshopActions on WorkshopViewModel {}\n',
        ),
        SourceFile(
          'lib/screens/software_workshop_screen.dart',
          'extension _Formatting on Duration {}\n',
        ),
      ];

      expect(checkBehaviourIsTestable(files), isEmpty);
    });

    test('does not fire on a type that merely starts with State', () {
      final files = [
        SourceFile(
          'lib/screens/a.dart',
          'extension _Helper on _StateMachine {}\n',
        ),
      ];

      expect(checkBehaviourIsTestable(files), isEmpty);
    });
  });

  group('R21 errors are mapped, never interpolated', () {
    test('flags an exception interpolated into a sentence', () {
      // This exact line rendered on the Software Workshop's health card,
      // directly beside a badge claiming the same subject was verified.
      final files = [
        SourceFile(
          'lib/repositories/workshop_repository.dart',
          "advisories.add('Permission profiles could not be verified: "
              "\$error');\n",
        ),
      ];

      final found = checkErrorsAreMapped(files);

      expect(found, hasLength(1));
      expect(found.single.rule, 'R21');
    });

    test('flags error.toString() becoming user-facing state', () {
      final files = [
        SourceFile(
          'lib/screens/storyboards_screen.dart',
          'setState(() => _error = error.toString());\n',
        ),
      ];

      expect(checkErrorsAreMapped(files), hasLength(1));
    });

    test('leaves a developer-facing debug log alone', () {
      final files = [
        SourceFile(
          'lib/main.dart',
          "debugPrint('Uncaught ii-os error: \$error');\n",
        ),
      ];

      expect(checkErrorsAreMapped(files), isEmpty);
    });

    test('does not read a doc comment as an interpolation', () {
      final files = [
        SourceFile(
          'lib/screens/a.dart',
          '/// Never write \$error into copy.\nfinal a = 1;\n',
        ),
      ];

      expect(checkErrorsAreMapped(files), isEmpty);
    });

    test('does not fire on an identifier that merely starts with error', () {
      final files = [
        SourceFile(
          'lib/widgets/character_selected_sheet.dart',
          "final s = 'No image was produced (\$errorCode).';\n",
        ),
      ];

      expect(checkErrorsAreMapped(files), isEmpty);
    });

    test('reports the line the interpolation sits on', () {
      final files = [
        SourceFile(
          'lib/screens/a.dart',
          "final a = 1;\nfinal b = 2;\nfinal c = '\$error';\n",
        ),
      ];

      expect(checkErrorsAreMapped(files).single.line, 3);
    });

    test('exempts the reporter whose job is to carry the exception', () {
      final files = [
        SourceFile(
          'lib/services/client_error_reporter.dart',
          'body = error.toString();\n',
        ),
      ];

      expect(checkErrorsAreMapped(files), isEmpty);
    });
  });
}
