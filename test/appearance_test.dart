import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ii_os/state/appearance_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('AppearanceController', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('follows the system until someone chooses otherwise', () async {
      final controller = AppearanceController();
      await controller.load();
      expect(controller.mode, ThemeMode.system);
    });

    test('remembers an explicit choice across a restart', () async {
      final first = AppearanceController();
      await first.setMode(ThemeMode.dark);

      final second = AppearanceController();
      await second.load();
      expect(second.mode, ThemeMode.dark);
    });

    test('an unreadable stored value falls back to the system default',
        () async {
      SharedPreferences.setMockInitialValues({
        'ii_os.appearance.mode': 'chartreuse',
      });
      final controller = AppearanceController();
      await controller.load();
      expect(controller.mode, ThemeMode.system);
    });

    test('toggle resolves system against what is actually on screen',
        () async {
      final controller = AppearanceController();
      await controller.load();
      expect(controller.mode, ThemeMode.system);

      // Under ThemeMode.system the mode alone does not say which the viewer is
      // looking at, so the first press has to act on the resolved brightness
      // or it visibly does nothing.
      await controller.toggle(Brightness.dark);
      expect(controller.mode, ThemeMode.light);

      await controller.toggle(Brightness.light);
      expect(controller.mode, ThemeMode.dark);
    });

    test('notifies once per real change', () async {
      final controller = AppearanceController();
      var notifications = 0;
      controller.addListener(() => notifications++);

      await controller.setMode(ThemeMode.dark);
      await controller.setMode(ThemeMode.dark);
      expect(notifications, 1);
    });
  });
}
