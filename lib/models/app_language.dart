import 'package:flutter/material.dart';

enum AppLanguage {
  uzbek('UZ', 'Oʻzbek tili', 'Uzbek (Latin)', '🇺🇿', Locale('uz')),
  russian('RU', 'Русский', 'Russian', '🇷🇺', Locale('ru')),
  english('EN', 'English', 'Global', '🇬🇧', Locale('en'));

  final String shortCode;
  final String title;
  final String subtitle;
  final String flag;
  final Locale locale;

  const AppLanguage(
    this.shortCode,
    this.title,
    this.subtitle,
    this.flag,
    this.locale,
  );

  static AppLanguage fromLocale(Locale locale) {
    return AppLanguage.values.firstWhere(
      (lang) => lang.locale.languageCode == locale.languageCode,
      orElse: () => AppLanguage.uzbek,
    );
  }
}
