import 'package:dio/dio.dart';
import 'package:firebase_auth/firebase_auth.dart';

// Server manzili bitta joyda. Boshqa serverga ko'chganda:
//   flutter build apk --dart-define=API_BASE_URL=https://yangi-domen/v1
// Emulyatorda lokal server: --dart-define=API_BASE_URL=http://10.0.2.2:4100/v1
const apiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'https://scanapi.argosacademy.uz/v1',
);

class ApiClient {
  ApiClient._();
  static final ApiClient instance = ApiClient._();

  late final Dio dio = _buildDio();

  Dio _buildDio() {
    final dio = Dio(
      BaseOptions(
        baseUrl: apiBaseUrl,
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 120),
        sendTimeout: const Duration(seconds: 60),
        headers: {'Accept': 'application/json'},
      ),
    );
    dio.interceptors.add(_FirebaseAuthInterceptor());
    return dio;
  }

  static bool get isSignedIn => FirebaseAuth.instance.currentUser != null;
}

/// Har bir so'rovga Firebase ID token qo'shadi. Server 401 qaytarsa,
/// token majburan yangilanib so'rov bir marta qayta yuboriladi.
class _FirebaseAuthInterceptor extends QueuedInterceptor {
  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    final token = await FirebaseAuth.instance.currentUser?.getIdToken();
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
    final user = FirebaseAuth.instance.currentUser;
    final opts = err.requestOptions;
    if (err.response?.statusCode == 401 &&
        user != null &&
        opts.extra['retried'] != true) {
      try {
        final fresh = await user.getIdToken(true);
        opts.headers['Authorization'] = 'Bearer $fresh';
        opts.extra['retried'] = true;
        final res = await Dio(BaseOptions(baseUrl: opts.baseUrl)).fetch(opts);
        return handler.resolve(res);
      } catch (_) {
        // Pastdagi asl xato qaytadi
      }
    }
    handler.next(err);
  }
}
