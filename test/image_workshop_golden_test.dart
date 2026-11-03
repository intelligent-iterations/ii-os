@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ii_os/models/image_workflow_capabilities.dart';
import 'package:ii_os/models/models.dart';
import 'package:ii_os/repositories/workflow_template_repository.dart';
import 'package:ii_os/screens/generate_screen.dart';
import 'package:ii_os/screens/image_edit_panel.dart';

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

WorkflowTemplateModel _template(
  String id,
  String workflowId,
  String model,
  Map<String, WorkflowInputModel> inputs,
) => WorkflowTemplateModel(
  id: id,
  workflowId: workflowId,
  version: '2',
  displayName: model,
  model: model,
  repository: 'acme/media',
  enabled: true,
  disabledReason: '',
  inputs: inputs,
);

final _qwenReferences = _template(
  'qwen-references',
  'image-create-reference-qwen-2511',
  'Qwen Image Edit 2511',
  const {
    'mode': WorkflowInputModel(type: 'string', required: true),
    'source_asset_id': WorkflowInputModel(type: 'string', required: true),
    'source_asset_id_2': WorkflowInputModel(type: 'string', required: false),
    'source_asset_id_3': WorkflowInputModel(type: 'string', required: false),
    'prompt': WorkflowInputModel(
      type: 'string',
      required: true,
      maxLength: 30000,
    ),
    'seed': WorkflowInputModel(type: 'number', required: false),
  },
);

final _qwenEdit = _template(
  'qwen-edit',
  'image-edit-qwen-2511',
  'Qwen Image Edit 2511',
  _qwenReferences.inputs,
);

void main() {
  setUpAll(loadPageFonts);

  testWidgets('create with references', (tester) async {
    final controller = pageController();
    addTearDown(controller.dispose);

    await pumpPage(
      tester,
      GenerateScreen(
        controller: controller,
        initialMode: ImageGenerationMode.references,
        initialTemplateId: _qwenReferences.id,
        templateRepository: _Templates([_qwenReferences]),
      ),
    );

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/image_workshop/create-references.png'),
    );
  });

  testWidgets('whole image edit with supporting references', (tester) async {
    final controller = pageController();
    addTearDown(controller.dispose);

    await pumpPage(
      tester,
      ImageEditScreen(
        controller: controller,
        initialTemplateId: _qwenEdit.id,
        templateRepository: _Templates([_qwenEdit]),
      ),
    );

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/image_workshop/edit-references.png'),
    );
  });
}
