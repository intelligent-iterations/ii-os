import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ii_os/models/workshop_room.dart';
import 'package:ii_os/screens/software_workshop_rooms.dart';
import 'package:ii_os/widgets/voice_clone_reference_field.dart';
import 'package:ii_os_design_system/ii_os_design_system.dart';

/// Every surface a viewer sees in dark mode comes from the dark palette.
///
/// `IiOsColors.surface` and its neighbours are `static const` light values, so
/// a widget that names one paints a light card in dark mode. The analyzer stays
/// silent, review looks correct, and only the running app disagrees -- so these
/// read the colour that actually reached the element rather than the source.
void main() {
  Widget inDark(Widget child) => MaterialApp(
    theme: IiOsTheme.dark(),
    home: Scaffold(body: child),
  );

  List<Color?> materialColorsUnder(WidgetTester tester, Finder root) => tester
      .widgetList<Material>(
        find.descendant(of: root, matching: find.byType(Material)),
      )
      .map((material) => material.color)
      .toList();

  testWidgets('the voice clone panel sits on the dark canvas', (tester) async {
    await tester.pumpWidget(
      inDark(
        VoiceCloneReferenceField(
          enabled: true,
          useVoiceClone: false,
          consent: false,
          file: null,
          contentType: null,
          onUseVoiceCloneChanged: (_) {},
          onSelect: () {},
          onClear: () {},
        ),
      ),
    );

    final colors = materialColorsUnder(
      tester,
      find.byType(VoiceCloneReferenceField),
    );
    expect(colors, contains(IiOsPalette.dark.canvas));
    expect(colors, isNot(contains(IiOsColors.canvas)));
    expect(colors, isNot(contains(IiOsColors.surface)));
  });

  testWidgets('an unselected room tab sits on the dark surface', (
    tester,
  ) async {
    await tester.pumpWidget(
      inDark(
        WorkshopRoomRail(
          rooms: _rooms,
          selected: _rooms.first,
          onSelected: (_) {},
          onAdd: () {},
          canManage: true,
        ),
      ),
    );

    final colors = materialColorsUnder(tester, find.byType(WorkshopRoomRail));
    expect(colors, contains(IiOsPalette.dark.surface));
    expect(colors, isNot(contains(IiOsColors.surface)));
  });

  testWidgets('a room accent is the dark identity hue', (tester) async {
    late Color accent;
    await tester.pumpWidget(
      inDark(
        Builder(
          builder: (context) {
            accent = workshopRoomColor(context, 'violet');
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    expect(accent, IiOsPalette.dark.identity['violet']);
    expect(accent, isNot(IiOsColors.identityViolet));
  });
}

const _rooms = [
  WorkshopRoomModel(
    id: 'mobile',
    name: 'Mobile app',
    color: 'violet',
    repositories: ['acme/mobile'],
    projectId: 'project-1',
    permissionProfile: 'repository-maintainer',
  ),
  WorkshopRoomModel(
    id: 'platform',
    name: 'Platform',
    color: 'cyan',
    repositories: ['acme/api'],
    projectId: 'project-1',
    permissionProfile: 'repository-maintainer',
  ),
];
