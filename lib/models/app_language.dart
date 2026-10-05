import 'package:flutter/material.dart';

/// Ilova interfeysi tillari. Har biriga assets/translations/<kod>.json mos keladi.
enum AppLanguage {
  uzbek('UZ', 'Oʻzbek tili', 'Uzbek', '🇺🇿', Locale('uz')),
  russian('RU', 'Русский', 'Russian', '🇷🇺', Locale('ru')),
  english('EN', 'English', 'English', '🇬🇧', Locale('en')),
  // Yevropa
  german('DE', 'Deutsch', 'German', '🇩🇪', Locale('de')),
  french('FR', 'Français', 'French', '🇫🇷', Locale('fr')),
  spanish('ES', 'Español', 'Spanish', '🇪🇸', Locale('es')),
  italian('IT', 'Italiano', 'Italian', '🇮🇹', Locale('it')),
  portuguese('PT', 'Português', 'Portuguese', '🇵🇹', Locale('pt')),
  turkish('TR', 'Türkçe', 'Turkish', '🇹🇷', Locale('tr')),
  polish('PL', 'Polski', 'Polish', '🇵🇱', Locale('pl')),
  romanian('RO', 'Română', 'Romanian', '🇷🇴', Locale('ro')),
  czech('CS', 'Čeština', 'Czech', '🇨🇿', Locale('cs'));

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

  static List<Locale> get locales => values.map((l) => l.locale).toList();

  static AppLanguage fromLocale(Locale locale) {
    return AppLanguage.values.firstWhere(
      (lang) => lang.locale.languageCode == locale.languageCode,
      orElse: () => AppLanguage.english,
    );
  }
}
