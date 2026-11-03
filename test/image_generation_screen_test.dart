import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ii_os/models/models.dart';
import 'package:ii_os/repositories/workflow_template_repository.dart';
import 'package:ii_os/screens/generate_screen.dart';

import 'page_golden_harness.dart';

final class _Templates implements WorkflowTemplateRepository {
  const _Templates(this.values);

  final List<WorkflowTemplateModel> values;

  @override
  Future<List<WorkflowTemplateModel>> list(
    String workspaceId, {
    String? workflowIdPrefix,
  }) async => values;
}

WorkflowTemplateModel _template({
  required String id,
  required String workflowId,
  required Map<String, WorkflowInputModel> inputs,
}) => WorkflowTemplateModel(
  id: id,
  workflowId: workflowId,
  version: '1',
  displayName: id,
  model: id,
  repository: 'acme/media',
  enabled: true,
  disabledReason: '',
  inputs: inputs,
);

void main() {
  testWidgets('text and reference modes both keep the prompt form', (
    tester,
  ) async {
    final controller = pageController();
    addTearDown(controller.dispose);
    final templates = _Templates([
      _template(
        id: 'text',
        workflowId: 'image-create-qwen-2512',
        inputs: const {
          'prompt': WorkflowInputModel(type: 'string', required: true),
          'aspect_ratio': WorkflowInputModel(type: 'string', required: true),
        },
      ),
      _template(
        id: 'references',
        workflowId: 'image-create-reference-qwen-2511',
        inputs: const {
          'source_asset_id': WorkflowInputModel(type: 'string', required: true),
          'source_asset_id_2': WorkflowInputModel(
            type: 'string',
            required: false,
          ),
          'prompt': WorkflowInputModel(type: 'string', required: true),
        },
      ),
    ]);

    await pumpPage(
      tester,
      GenerateScreen(controller: controller, templateRepository: templates),
    );

    expect(find.widgetWithText(TextField, 'Image prompt'), findsOneWidget);
    expect(find.text('Reference images'), findsNothing);

    await tester.tap(find.text('Use references'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(TextField, 'Image prompt'), findsOneWidget);
    expect(find.text('Reference images'), findsOneWidget);
    expect(find.text('Image A · main reference'), findsOneWidget);
  });
}
