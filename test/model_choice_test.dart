import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ii_os/models/models.dart';
import 'package:ii_os/widgets/model_choice.dart';
import 'package:ii_os_design_system/ii_os_design_system.dart';

WorkflowTemplateModel _template(
  String workflowId, {
  bool enabled = true,
  String disabledReason = '',
}) => WorkflowTemplateModel(
  id: workflowId,
  workflowId: workflowId,
  version: '1',
  displayName: workflowId,
  model: workflowId,
  repository: 'acme/example',
  enabled: enabled,
  disabledReason: disabledReason,
);

Widget _host(Widget child, {double width = 720}) => MaterialApp(
  theme: IiOsTheme.light(),
  home: Scaffold(
    body: SizedBox(width: width, child: SingleChildScrollView(child: child)),
  ),
);

void main() {
  group('ModelChoice', () {
    testWidgets('gives every model the sentence that decides it', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          ModelChoice(
            templates: [
              _template('image-create'),
              _template('image-create-qwen-2512'),
              _template('image-create-flux2-klein'),
            ],
            selectedId: 'image-create',
            enabled: true,
            onSelected: (_) {},
          ),
        ),
      );

      expect(find.byType(IiOsChoiceCard), findsNWidgets(3));
      expect(
        find.text('Fast, clean images from a plain description.'),
        findsOneWidget,
      );
      expect(
        find.text('Follows a long, specific description closely.'),
        findsOneWidget,
      );
    });

    testWidgets('reports the model that was chosen', (tester) async {
      String? chosen;
      await tester.pumpWidget(
        _host(
          ModelChoice(
            templates: [
              _template('image-create'),
              _template('image-create-qwen-2512'),
            ],
            selectedId: 'image-create',
            enabled: true,
            onSelected: (id) => chosen = id,
          ),
        ),
      );

      await tester.tap(find.text('Follows a long, specific description closely.'));
      expect(chosen, 'image-create-qwen-2512');
    });

    testWidgets('a model this workspace cannot run says why', (tester) async {
      await tester.pumpWidget(
        _host(
          ModelChoice(
            templates: [
              _template('image-create'),
              _template(
                'image-create-flux2-klein',
                enabled: false,
                disabledReason: 'The workflow is not installed on dev.',
              ),
            ],
            selectedId: 'image-create',
            enabled: true,
            onSelected: (_) {},
          ),
        ),
      );

      expect(
        find.text('The workflow is not installed on dev.'),
        findsOneWidget,
      );
    });

    testWidgets('one model is stated, not offered as a choice', (tester) async {
      await tester.pumpWidget(
        _host(
          ModelChoice(
            templates: [_template('image-create')],
            selectedId: 'image-create',
            enabled: true,
            onSelected: (_) {},
          ),
        ),
      );

      expect(find.byType(IiOsChoiceCard), findsNothing);
      expect(
        find.text('Fast, clean images from a plain description.'),
        findsOneWidget,
      );
    });

    testWidgets('renders nothing at all with no models', (tester) async {
      await tester.pumpWidget(
        _host(
          ModelChoice(
            templates: const [],
            selectedId: null,
            enabled: true,
            onSelected: (_) {},
          ),
        ),
      );

      expect(find.byType(IiOsChoiceCard), findsNothing);
      expect(find.text('Model'), findsNothing);
    });

    testWidgets('cards sharing a row share a height', (tester) async {
      await tester.pumpWidget(
        _host(
          ModelChoice(
            templates: [
              // Two very different sentence lengths, which is what makes a
              // wrapped run render two different bottom edges.
              _template('image-create'),
              _template('image-create-flux2-klein'),
            ],
            selectedId: 'image-create',
            enabled: true,
            onSelected: (_) {},
          ),
          width: 720,
        ),
      );

      final cards = find.byType(IiOsChoiceCard);
      expect(
        tester.getSize(cards.at(0)).height,
        tester.getSize(cards.at(1)).height,
      );
    });

    testWidgets('stacks on a narrow window and pairs on a wide one', (
      tester,
    ) async {
      final templates = [
        _template('image-create'),
        _template('image-create-qwen-2512'),
      ];
      Widget subject() => ModelChoice(
        templates: templates,
        selectedId: 'image-create',
        enabled: true,
        onSelected: (_) {},
      );

      await tester.pumpWidget(_host(subject(), width: 420));
      final narrow = tester.getSize(find.byType(IiOsChoiceCard).first).width;

      await tester.pumpWidget(_host(subject(), width: 720));
      final wide = tester.getSize(find.byType(IiOsChoiceCard).first).width;

      expect(narrow, greaterThan(360));
      expect(wide, lessThan(400));
    });
  });
}
