import 'dart:io';

import 'package:ii_os_functions/src/workflow_catalog.dart';
import 'package:ii_os_functions/src/workflow_catalog_selection.dart';
import 'package:test/test.dart';

void main() {
  final catalog = WorkflowCatalog.parse(
    repository: 'acme/media',
    ref: 'dev',
    sha: 'abc123',
    content: File('test/fixtures/example-catalog.yaml').readAsStringSync(),
  );

  test('one approved model enables every model on the same workflow', () {
    final qwen = catalog.find('image-create-qwen-2512')!;

    expect(
      workspaceWorkflowSelectionIncludes(
        catalog: catalog,
        selectedWorkflowKeys: const {'acme/media#image-create'},
        workflow: qwen,
      ),
      isTrue,
    );
  });

  test('does not enable another operation that shares a wrapper', () {
    final inpaint = catalog.find('image-inpaint')!;

    expect(
      workspaceWorkflowSelectionIncludes(
        catalog: catalog,
        selectedWorkflowKeys: const {'acme/media#image-edit'},
        workflow: inpaint,
      ),
      isFalse,
    );
  });

  test('does not inherit approval from another repository', () {
    final qwen = catalog.find('image-create-qwen-2512')!;

    expect(
      workspaceWorkflowSelectionIncludes(
        catalog: catalog,
        selectedWorkflowKeys: const {'other/media#image-create'},
        workflow: qwen,
      ),
      isFalse,
    );
  });

  test('keeps an explicitly selected non-model operation enabled', () {
    final inpaint = catalog.find('image-inpaint')!;

    expect(
      workspaceWorkflowSelectionIncludes(
        catalog: catalog,
        selectedWorkflowKeys: const {'acme/media#image-inpaint'},
        workflow: inpaint,
      ),
      isTrue,
    );
  });
}
