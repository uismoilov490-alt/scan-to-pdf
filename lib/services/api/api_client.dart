import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

const _baseUrl = 'https://api.scantopdf.app/v1'; // production
// const _baseUrl = 'http://10.0.2.2:3000/v1';    // Android emulator local

const _storage = FlutterSecureStorage(
  aOptions: AndroidOptions(encryptedSharedPreferences: true),
  iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
);

const _kAccess  = 'access_token';
const _kRefresh = 'refresh_token';

class ApiClient {
  ApiClient._();
  static final ApiClient instance = ApiClient._();

  late final Dio _dio = _buildDio();

  Dio get dio => _dio;

  Dio _buildDio() {
    final dio = Dio(BaseOptions(
      baseUrl:        _baseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 30),
      sendTimeout:    const Duration(seconds: 60),
      headers: {
        'Accept':       'application/json',
        'Content-Type': 'application/json',
      },
    ));

    dio.interceptors.add(_AuthInterceptor(dio));
    return dio;
  }

  // ── Token management ────────────────────────────────────────

  static Future<void> saveTokens({
    required String access,
    required String refresh,
  }) async {
    await Future.wait([
      _storage.write(key: _kAccess,  value: access),
      _storage.write(key: _kRefresh, value: refresh),
    ]);
  }

  static Future<String?> getAccessToken()  => _storage.read(key: _kAccess);
  static Future<String?> getRefreshToken() => _storage.read(key: _kRefresh);

  static Future<void> clearTokens() async {
    await Future.wait([
      _storage.delete(key: _kAccess),
      _storage.delete(key: _kRefresh),
    ]);
  }

  static Future<bool> isLoggedIn() async =>
      (await getAccessToken()) != null;
}

class _AuthInterceptor extends Interceptor {
  final Dio _dio;
  bool _refreshing = false;

  _AuthInterceptor(this._dio);

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    final token = await ApiClient.getAccessToken();
    if (token != null) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    handler.next(options);
  }

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    if (err.response?.statusCode == 401 && !_refreshing) {
      final errorCode = err.response?.data?['error']?['code'];
      if (errorCode == 'AUTH_TOKEN_EXPIRED') {
        _refreshing = true;
        try {
          final newTokens = await _doRefresh();
          if (newTokens != null) {
            // Retry the original request with new access token
            final opts = err.requestOptions;
            opts.headers['Authorization'] = 'Bearer ${newTokens['access_token']}';
            final res = await _dio.fetch(opts);
            handler.resolve(res);
            return;
          }
        } catch (_) {
          await ApiClient.clearTokens();
        } finally {
          _refreshing = false;
        }
      }
    }
    handler.next(err);
  }

  Future<Map<String, dynamic>?> _doRefresh() async {
    final refreshToken = await ApiClient.getRefreshToken();
    if (refreshToken == null) return null;

    final res = await Dio().post(
      '$_baseUrl/auth/refresh',
      data: {'refresh_token': refreshToken},
    );

    final data = res.data['data'] as Map<String, dynamic>;
    await ApiClient.saveTokens(
      access:  data['access_token'] as String,
      refresh: data['refresh_token'] as String,
    );
    return data;
  }
}
