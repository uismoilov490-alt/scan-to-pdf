import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Mahalliy sozlamalar (SharedPreferences). Remote backend yo‘q.
abstract final class SettingsService {
  static const _themeModeKey = 'settings_theme_mode';
  static const _pdfDirKey = 'settings_pdf_directory';

  static Future<ThemeMode> loadThemeMode() async {
    final prefs = await SharedPreferences.getInstance();
    return switch (prefs.getString(_themeModeKey) ?? 'system') {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
  }

  static Future<void> saveThemeMode(ThemeMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    final value = switch (mode) {
      ThemeMode.light => 'light',
      ThemeMode.dark => 'dark',
      ThemeMode.system => 'system',
    };
    await prefs.setString(_themeModeKey, value);
  }

  static Future<String?> loadCustomPdfDirectory() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_pdfDirKey);
    if (raw == null || raw.trim().isEmpty) return null;
    return raw.trim();
  }

  static Future<void> saveCustomPdfDirectory(String absolutePath) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_pdfDirKey, absolutePath.trim());
  }

  static Future<void> clearCustomPdfDirectory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_pdfDirKey);
  }
}
