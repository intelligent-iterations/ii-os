import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ii_os_design_system/ii_os_design_system.dart';

Widget _host(Widget child) {
  return MaterialApp(
    theme: IiOsTheme.light(),
    home: Scaffold(body: SingleChildScrollView(child: child)),
  );
}

void main() {
  group('GenerationWorkspace', () {
    testWidgets('sits form and preview side by side once there is room', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1100, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        _host(
          const GenerationWorkspace(
            form: Text('Form'),
            preview: Text('Preview'),
          ),
        ),
      );

      final formRect = tester.getRect(find.text('Form'));
      final previewRect = tester.getRect(find.text('Preview'));
      expect(formRect.right, lessThanOrEqualTo(previewRect.left));
      expect(formRect.top, previewRect.top);
    });

    testWidgets('stacks the form above the preview on a narrow window', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(500, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        _host(
          const GenerationWorkspace(
            form: Text('Form'),
            preview: Text('Preview'),
          ),
        ),
      );

      final formRect = tester.getRect(find.text('Form'));
      final previewRect = tester.getRect(find.text('Preview'));
      expect(formRect.bottom, lessThanOrEqualTo(previewRect.top));
    });
  });
}
