import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The viewer's light/dark preference, remembered across sessions.
///
/// Defaults to [ThemeMode.system] so the app matches the machine until someone
/// says otherwise. A stored value only ever appears here after an explicit
/// choice, which is why "follow the system" stays a real, selectable state
/// rather than merely the absence of a preference.
class AppearanceController extends ChangeNotifier {


  static const _storageKey = 'ii_os.appearance.mode';


  SharedPreferences? _preferences;
  ThemeMode _mode = ThemeMode.system;

  ThemeMode get mode => _mode;

  /// Reads the stored preference. Safe to call before the first frame; a
  /// storage failure leaves the system default in place rather than blocking
  /// startup on a cosmetic setting.
  Future<void> load() async {
    try {
      final preferences = _preferences ??= await SharedPreferences.getInstance();
      final stored = preferences.getString(_storageKey);
      final resolved = _parse(stored);
      if (resolved == _mode) return;
      _mode = resolved;
      notifyListeners();
    } on Object {
      // Keep ThemeMode.system.
    }
  }

  Future<void> setMode(ThemeMode mode) async {
    if (mode == _mode) return;
    _mode = mode;
    notifyListeners();
    try {
      final preferences = _preferences ??= await SharedPreferences.getInstance();
      await preferences.setString(_storageKey, mode.name);
    } on Object {
      // The mode is already applied; only persistence failed.
    }
  }

  /// Flips between light and dark, resolving `system` against what is
  /// currently on screen so the first press always visibly changes something.
  Future<void> toggle(Brightness current) => setMode(
    current == Brightness.dark ? ThemeMode.light : ThemeMode.dark,
  );

  static ThemeMode _parse(String? value) => switch (value) {
    'light' => ThemeMode.light,
    'dark' => ThemeMode.dark,
    _ => ThemeMode.system,
  };
}

/// Makes the [AppearanceController] reachable without threading it through
/// every constructor between the app root and the top bar.
class AppearanceScope extends InheritedNotifier<AppearanceController> {
  const AppearanceScope({
    required AppearanceController super.notifier,
    required super.child,
    super.key,
  });

  static AppearanceController? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<AppearanceScope>()
      ?.notifier;
}
