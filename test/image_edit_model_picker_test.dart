import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ii_os/models/models.dart';
import 'package:ii_os/widgets/image_edit_model_picker.dart';

void main() {
  testWidgets('one model does not show an unavailable comparison control', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ImageEditModelPicker(
            templates: [_template('edit-a', 'Model A')],
            selectedId: 'edit-a',
            useAll: false,
            enabled: true,
            onSelected: (_) {},
            onUseAllChanged: (_) {},
          ),
        ),
      ),
    );

    expect(find.text('Try every model'), findsNothing);
  });

  testWidgets('model comparison picker fits mobile and offers every model', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(360, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var useAll = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: StatefulBuilder(
              builder: (context, setState) => ImageEditModelPicker(
                templates: [
                  _template('edit-a', 'Model A'),
                  _template('edit-b', 'Model B'),
                ],
                selectedId: 'edit-a',
                useAll: useAll,
                enabled: true,
                onSelected: (_) {},
                onUseAllChanged: (value) => setState(() => useAll = value),
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.text('Try every model'), findsOneWidget);
    // Each model states what it is for, so the comparison switch is a shortcut
    // rather than the only way to find out.
    expect(
      find.text('Quick changes that keep the original composition.'),
      findsNWidgets(2),
    );
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Try every model'));
    await tester.pump();

    expect(useAll, isTrue);
    expect(tester.takeException(), isNull);
  });
}

WorkflowTemplateModel _template(String id, String model) =>
    WorkflowTemplateModel(
      id: id,
      workflowId: 'image-edit',
      version: '1',
      displayName: '$model Edit',
      model: model,
      repository: 'acme/$id',
      enabled: true,
      disabledReason: '',
    );
