import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'ai_service.dart';

class UserService {
  static const _keyName = 'user_name';
  static const _keyEmail = 'user_email';
  static const _keyPhoto = 'user_photo';
  static const _keyPhone = 'user_phone';
  static const _keyLoggedIn = 'user_logged_in';

  static Future<void> saveUser({
    required String name,
    required String email,
    String? photoUrl,
    String? phone,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyName, name);
    await prefs.setString(_keyEmail, email);
    if (photoUrl != null) await prefs.setString(_keyPhoto, photoUrl);
    if (phone != null) await prefs.setString(_keyPhone, phone);
    await prefs.setBool(_keyLoggedIn, true);
  }

  static Future<void> clearUser() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyName);
    await prefs.remove(_keyEmail);
    await prefs.remove(_keyPhoto);
    await prefs.remove(_keyPhone);
    await prefs.setBool(_keyLoggedIn, false);
  }

  /// Firebase, Google va lokal ma'lumotlardan to'liq chiqish.
  static Future<void> signOut() async {
    await FirebaseAuth.instance.signOut();
    try {
      await GoogleSignIn().signOut();
    } catch (_) {
      // Google orqali kirilmagan bo'lishi mumkin
    }
    await clearUser();
  }

  /// Hisobni butunlay o'chiradi: avval serverdagi ma'lumotlar, keyin Firebase hisobi.
  /// Firebase yaqinda kirishni talab qilsa `requires-recent-login` xatosi otiladi.
  static Future<void> deleteAccount() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      await AiService.deleteAccountData();
      await user.delete();
    }
    await signOut();
  }

  static Future<bool> isLoggedIn() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyLoggedIn) ?? false;
  }

  static Future<UserData?> getUser() async {
    final prefs = await SharedPreferences.getInstance();
    if (!(prefs.getBool(_keyLoggedIn) ?? false)) return null;
    return UserData(
      name: prefs.getString(_keyName) ?? '',
      email: prefs.getString(_keyEmail) ?? '',
      photoUrl: prefs.getString(_keyPhoto),
      phone: prefs.getString(_keyPhone),
    );
  }
}

class UserData {
  final String name;
  final String email;
  final String? photoUrl;
  final String? phone;

  const UserData({
    required this.name,
    required this.email,
    this.photoUrl,
    this.phone,
  });

  String get displayIdentifier =>
      email.isNotEmpty ? email : (phone ?? '');
}
