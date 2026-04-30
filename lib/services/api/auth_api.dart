import 'package:dio/dio.dart';
import 'api_client.dart';

class AuthUser {
  final String id;
  final String? phone;
  final String? email;
  final String? displayName;
  final String? avatarUrl;
  final String plan;

  const AuthUser({
    required this.id,
    this.phone,
    this.email,
    this.displayName,
    this.avatarUrl,
    required this.plan,
  });

  factory AuthUser.fromJson(Map<String, dynamic> j) => AuthUser(
    id:          j['id'] as String,
    phone:       j['phone'] as String?,
    email:       j['email'] as String?,
    displayName: j['display_name'] as String?,
    avatarUrl:   j['avatar_url'] as String?,
    plan:        j['plan'] as String? ?? 'free',
  );
}

class AuthApi {
  final Dio _dio = ApiClient.instance.dio;

  /// Step 1: Send OTP to phone
  Future<void> sendOtp(String phone) async {
    await _dio.post('/auth/phone/send-otp', data: {'phone': phone});
  }

  /// Step 2: Verify OTP and get tokens
  Future<AuthUser> verifyOtp(String phone, String code) async {
    final res = await _dio.post('/auth/phone/verify-otp', data: {
      'phone': phone,
      'code':  code,
    });
    final data = res.data['data'] as Map<String, dynamic>;

    await ApiClient.saveTokens(
      access:  data['access_token'] as String,
      refresh: data['refresh_token'] as String,
    );
    return AuthUser.fromJson(data['user'] as Map<String, dynamic>);
  }

  /// Google Sign-In with ID token from Firebase/Google Sign-In plugin
  Future<AuthUser> signInWithGoogle(String idToken) async {
    final res = await _dio.post('/auth/google', data: {'id_token': idToken});
    final data = res.data['data'] as Map<String, dynamic>;

    await ApiClient.saveTokens(
      access:  data['access_token'] as String,
      refresh: data['refresh_token'] as String,
    );
    return AuthUser.fromJson(data['user'] as Map<String, dynamic>);
  }

  /// Logout — revoke refresh token on server
  Future<void> logout() async {
    try {
      final refreshToken = await ApiClient.getRefreshToken();
      await _dio.post('/auth/logout', data: {'refresh_token': refreshToken});
    } finally {
      await ApiClient.clearTokens();
    }
  }
}
