import 'dart:io';

import 'package:flutter/material.dart';

import '../services/settings_service.dart';

/// Tema va PDF saqlash papkasi holatini boshqaradi; diskka `SettingsService` orqali yoziladi.
class AppSettingsController extends ChangeNotifier {
  ThemeMode _themeMode = ThemeMode.system;
  String? _customPdfDirectory;

  ThemeMode get themeMode => _themeMode;
  String? get customPdfDirectory => _customPdfDirectory;

  bool get usesDefaultPdfDirectory =>
      _customPdfDirectory == null || _customPdfDirectory!.isEmpty;

  Future<void> load() async {
    _themeMode = await SettingsService.loadThemeMode();

    var custom = await SettingsService.loadCustomPdfDirectory();
    if (custom != null && custom.isNotEmpty) {
      if (!await Directory(custom).exists()) {
        await SettingsService.clearCustomPdfDirectory();
        custom = null;
      }
    }
    _customPdfDirectory = custom;

    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    if (_themeMode == mode) return;
    _themeMode = mode;
    await SettingsService.saveThemeMode(mode);
    notifyListeners();
  }

  /// `null` — ilova ichidagi standart papka (`Documents/scan_to_pdf`).
  Future<void> setCustomPdfDirectory(String? absolutePath) async {
    if (absolutePath == null || absolutePath.trim().isEmpty) {
      _customPdfDirectory = null;
      await SettingsService.clearCustomPdfDirectory();
      notifyListeners();
      return;
    }

    final normalized = absolutePath.trim();
    final dir = Directory(normalized);
    if (!await dir.exists()) {
      throw StateError('path_not_found');
    }

    _customPdfDirectory = normalized;
    await SettingsService.saveCustomPdfDirectory(normalized);
    notifyListeners();
  }
}
