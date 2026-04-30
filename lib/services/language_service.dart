import 'package:shared_preferences/shared_preferences.dart';

class LanguageService {
  static const _kFirstLaunchKey = 'first_launch_done';

  static Future<bool> isFirstLaunch() async {
    final prefs = await SharedPreferences.getInstance();
    return !(prefs.getBool(_kFirstLaunchKey) ?? false);
  }

  static Future<void> markFirstLaunchDone() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kFirstLaunchKey, true);
  }
}
