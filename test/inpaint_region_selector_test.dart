import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ii_os/widgets/image_edit_controls.dart';

void main() {
  testWidgets('each drag adds a mask and keyboard shortcuts undo and redo', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var masks = <Rect>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => SizedBox(
              width: 500,
              child: InpaintRegionSelector(
                imageBytes: null,
                imageUrl: null,
                aspectRatio: 1,
                masks: masks,
                allowMultiple: true,
                enabled: true,
                onChanged: (value) => setState(() => masks = value),
                onClear: () => setState(() => masks = const []),
              ),
            ),
          ),
        ),
      ),
    );

    final surface = find.byKey(const ValueKey('inpaint-mask-surface'));
    final origin = tester.getTopLeft(surface);
    await tester.dragFrom(origin + const Offset(40, 40), const Offset(80, 70));
    await tester.pump();
    expect(find.text('Add another area'), findsNothing);
    expect(find.textContaining('Drag another box'), findsOneWidget);
    await tester.dragFrom(
      origin + const Offset(260, 220),
      const Offset(70, 80),
    );
    await tester.pump();

    expect(masks, hasLength(2));

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(masks, hasLength(1));

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(masks, hasLength(2));

    await tester.tap(find.text('Clear'));
    await tester.pump();
    expect(masks, isEmpty);
  });

  testWidgets('brush refines selection and erase can be undone and redone', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var masks = <Rect>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => SizedBox(
              width: 500,
              child: InpaintRegionSelector(
                imageBytes: null,
                imageUrl: null,
                aspectRatio: 1,
                masks: masks,
                allowMultiple: true,
                enabled: true,
                onChanged: (value) => setState(() => masks = value),
                onClear: () => setState(() => masks = const []),
              ),
            ),
          ),
        ),
      ),
    );

    expect(
      tester
          .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Select area'))
          .selected,
      isTrue,
    );
    await tester.tap(find.text('Brush'));
    await tester.pump();
    final surface = find.byKey(const ValueKey('inpaint-mask-surface'));
    final origin = tester.getTopLeft(surface);
    await tester.dragFrom(
      origin + const Offset(120, 120),
      const Offset(80, 10),
    );
    await tester.pump();
    expect(masks, isNotEmpty);
    expect(masks.length, lessThanOrEqualTo(32));
    final brushed = List<Rect>.of(masks);
    final brushedArea = brushed.fold<double>(
      0,
      (total, rect) => total + rect.width * rect.height,
    );

    await tester.tap(find.text('Erase'));
    await tester.pump();
    await tester.dragFrom(origin + const Offset(120, 120), const Offset(2, 2));
    await tester.pump();
    final erased = List<Rect>.of(masks);
    final erasedArea = erased.fold<double>(
      0,
      (total, rect) => total + rect.width * rect.height,
    );
    expect(erasedArea, lessThan(brushedArea));

    await tester.tap(find.text('Undo'));
    await tester.pump();
    expect(masks, brushed);
    await tester.tap(find.text('Redo'));
    await tester.pump();
    expect(masks, erased);
  });
}
