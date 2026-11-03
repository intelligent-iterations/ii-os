import 'package:flutter_test/flutter_test.dart';
import 'package:ii_os/screens/image_edit_panel.dart';

import 'page_golden_harness.dart';

void main() {
  testWidgets('does not show controls no loaded workflow has declared', (
    tester,
  ) async {
    final controller = pageController();
    addTearDown(controller.dispose);

    await pumpPage(tester, ImageEditScreen(controller: controller));

    expect(find.text('How closely to follow the original'), findsNothing);
    expect(find.textContaining('Image B'), findsNothing);
  });

  testWidgets('uses operation names instead of model implementation terms', (
    tester,
  ) async {
    final controller = pageController();
    addTearDown(controller.dispose);

    await pumpPage(tester, ImageEditScreen(controller: controller));

    expect(find.text('Whole image'), findsOneWidget);
    expect(find.text('Selected area'), findsOneWidget);
    expect(find.text('Inpaint'), findsNothing);
  });

  testWidgets('the source picture offers the library as well as the disk', (
    tester,
  ) async {
    final controller = pageController();
    addTearDown(controller.dispose);

    await pumpPage(tester, ImageEditScreen(controller: controller));

    expect(find.text('Image A · the picture you are changing'), findsOneWidget);
    expect(find.text('Choose image A'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
