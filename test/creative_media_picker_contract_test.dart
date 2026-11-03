import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  const creativeMediaInputs = <String, String>{
    'lib/screens/image_edit_panel.dart': 'showMediaPicker(',
    'lib/screens/minimax_h3_reference_editor.dart': 'showMediaPicker(',
    'lib/screens/narration_generation_form.dart': 'showMediaPicker(',
    'lib/screens/video_editor_screen_import.dart': 'showMediaPickerMultiple(',
    'lib/screens/video_generation_screen.dart': 'showMediaPicker(',
    'lib/screens/character_media_picker.dart': 'showMediaPicker(',
  };

  test('every creative media input uses the shared workspace picker', () {
    for (final entry in creativeMediaInputs.entries) {
      final source = File(entry.key).readAsStringSync();
      expect(
        source,
        contains(entry.value),
        reason: '${entry.key} must offer the workspace library and upload',
      );
      expect(
        source,
        isNot(contains(RegExp(r'\bopenFiles?\s*\('))),
        reason: '${entry.key} must not bypass the shared media picker',
      );
    }
    expect(
      File('lib/screens/characters_grid.dart').readAsStringSync(),
      isNot(contains(RegExp(r'\bopenFiles?\s*\('))),
    );
  });
}
