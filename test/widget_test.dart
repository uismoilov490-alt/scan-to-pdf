import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:scan_to_pdf/main.dart';
import 'package:scan_to_pdf/providers/app_settings_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('App launches and shows home title', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();

    final settings = AppSettingsController();
    await settings.load();

    await tester.pumpWidget(
      EasyLocalization(
        supportedLocales: const [Locale('uz'), Locale('ru'), Locale('en')],
        path: 'assets/translations',
        fallbackLocale: const Locale('uz'),
        child: ChangeNotifierProvider.value(
          value: settings,
          child: const ScanToPdfApp(isFirstLaunch: false),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));

    expect(find.text('Scan to PDF'), findsWidgets);
  });
}
