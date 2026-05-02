import 'package:easy_localization/easy_localization.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'firebase_options.dart';

import 'providers/app_settings_controller.dart';
import 'providers/subscription_provider.dart';
import 'screens/home_screen.dart';
import 'screens/language_screen.dart';
import 'services/language_service.dart';
import 'theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await EasyLocalization.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  final isFirstLaunch = await LanguageService.isFirstLaunch();
  final appSettings = AppSettingsController();
  await appSettings.load();

  runApp(
    EasyLocalization(
      supportedLocales: const [Locale('uz'), Locale('ru'), Locale('en')],
      path: 'assets/translations',
      fallbackLocale: const Locale('uz'),
      saveLocale: true,
      child: MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: appSettings),
          ChangeNotifierProvider(
            create: (_) => SubscriptionProvider()..initialize(),
          ),
        ],
        child: ScanToPdfApp(isFirstLaunch: isFirstLaunch),
      ),
    ),
  );
}

class ScanToPdfApp extends StatelessWidget {
  final bool isFirstLaunch;

  const ScanToPdfApp({super.key, required this.isFirstLaunch});

  static final ThemeData _lightTheme = AppTheme.light();
  static final ThemeData _darkTheme = AppTheme.dark();

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<AppSettingsController>();

    return MaterialApp(
      title: 'Scan to PDF',
      debugShowCheckedModeBanner: false,
      themeMode: settings.themeMode,
      theme: _lightTheme,
      darkTheme: _darkTheme,
      localizationsDelegates: context.localizationDelegates,
      supportedLocales: context.supportedLocales,
      locale: context.locale,
      home: isFirstLaunch ? const LanguageScreen() : const HomeScreen(),
    );
  }
}
