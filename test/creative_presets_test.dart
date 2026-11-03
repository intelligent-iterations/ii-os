import 'package:flutter_test/flutter_test.dart';
import 'package:ii_os/models/creative_presets.dart';

void main() {
  group('sourceAdherencePresets', () {
    test('reads in one direction, from most change to least', () {
      final values = sourceAdherencePresets.map((p) => p.value).toList();
      expect(values, orderedEquals([...values]..sort()));
    });

    test('stays inside the range the edit workflows accept', () {
      for (final preset in sourceAdherencePresets) {
        expect(preset.value, greaterThanOrEqualTo(sourceAdherenceMinimum));
        expect(preset.value, lessThanOrEqualTo(sourceAdherenceMaximum));
      }
    });

    test('the workflow default is one of the named settings', () {
      // Otherwise a page that has changed nothing opens reading `Custom`, and
      // the person is told they have made a decision they have not made.
      expect(
        sourceAdherencePresets.map((p) => p.value),
        contains(sourceAdherenceDefault),
      );
    });

    test('every setting says what choosing it does', () {
      for (final preset in sourceAdherencePresets) {
        expect(preset.label, isNotEmpty);
        expect(preset.description, isNotEmpty);
        expect(preset.description.endsWith('.'), isTrue);
      }
    });
  });
}
