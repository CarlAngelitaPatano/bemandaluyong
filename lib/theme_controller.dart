import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// App-wide light/dark/system theme choice.
///
/// The root [MaterialApp] listens to [mode] and rebuilds when it changes, and
/// the choice is saved on-device so it survives restarts.
class ThemeController {
  ThemeController._();
  static final ThemeController instance = ThemeController._();

  static const String _key = 'theme_mode';

  final ValueNotifier<ThemeMode> mode = ValueNotifier<ThemeMode>(
    ThemeMode.system,
  );

  /// Loads the saved choice. Call once at startup before runApp.
  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    mode.value = switch (prefs.getString(_key)) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
  }

  /// Changes and saves the theme mode (applies instantly).
  Future<void> set(ThemeMode value) async {
    mode.value = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, value.name); // 'light' / 'dark' / 'system'
  }

  /// Human-readable label for a mode.
  static String label(ThemeMode m) => switch (m) {
        ThemeMode.light => 'Light',
        ThemeMode.dark => 'Dark',
        ThemeMode.system => 'Follow system',
      };
}
