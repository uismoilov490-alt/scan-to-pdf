import 'dart:convert';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

import 'api/api_client.dart';

/// AI limiti. Bepul rejada — butun umrga N ta fayl ([perFile]),
/// Pro'da — tarif davri (hafta/oy) ichida N ta sahifa.
class AiQuota {
  final String plan; // free | weekly | monthly
  final String unit; // file | page
  final int used;
  final int limit;
  final int remaining;
  final int? maxPagesPerFile;
  final DateTime? resetsAt;

  const AiQuota({
    this.plan = 'free',
    this.unit = 'page',
    required this.used,
    required this.limit,
    required this.remaining,
    this.maxPagesPerFile,
    this.resetsAt,
  });

  bool get perFile => unit == 'file';

  factory AiQuota.fromJson(Map<String, dynamic> j) => AiQuota(
    plan: j['plan'] as String? ?? 'free',
    unit: j['unit'] as String? ?? 'page',
    used: (j['used'] as num?)?.toInt() ?? 0,
    limit: (j['limit'] as num?)?.toInt() ?? 0,
    remaining: (j['remaining'] as num?)?.toInt() ?? 0,
    maxPagesPerFile: (j['maxPagesPerFile'] as num?)?.toInt(),
    resetsAt: j['resetsAt'] is num
        ? DateTime.fromMillisecondsSinceEpoch((j['resetsAt'] as num).toInt())
        : null,
  );

  /// [pages] sahifali yangi faylni boshlashdan oldin tekshiradi: yetmasa —
  /// server qaytaradigan xato kodi bilan [AiException], yetsa — null.
  AiException? check(int pages) {
    if (perFile) {
      if (remaining < 1) return AiException('QUOTA_EXCEEDED', '', quota: this);
      if (maxPagesPerFile != null && pages > maxPagesPerFile!) {
        return AiException('FILE_TOO_BIG', '', quota: this, needed: pages);
      }
      return null;
    }
    return remaining < pages
        ? AiException('QUOTA_EXCEEDED', '', quota: this, needed: pages)
        : null;
  }
}

class AiAccount {
  final bool pro;
  final String plan;
  final DateTime? proUntil;
  final AiQuota quota;

  const AiAccount({
    required this.pro,
    required this.plan,
    required this.proUntil,
    required this.quota,
  });

  factory AiAccount.fromJson(Map<String, dynamic> j) => AiAccount(
    pro: j['pro'] == true,
    plan: j['plan'] as String? ?? 'free',
    proUntil: j['proUntil'] is num
        ? DateTime.fromMillisecondsSinceEpoch((j['proUntil'] as num).toInt())
        : null,
    quota: AiQuota.fromJson(j['quota'] as Map<String, dynamic>? ?? const {}),
  );
}

/// Server qaytargan xato kodlari: AUTH_REQUIRED, AUTH_INVALID, QUOTA_EXCEEDED,
/// FILE_TOO_BIG, AI_UNAVAILABLE, AI_BUSY, AI_REFUSED, IMAGE_TOO_LARGE, NETWORK ...
class AiException implements Exception {
  final String code;
  final String message;
  final AiQuota? quota;

  /// Oldindan tekshiruvda: fayl uchun kerak bo'lgan sahifalar soni
  final int? needed;

  const AiException(this.code, this.message, {this.quota, this.needed});

  bool get needsLogin => code == 'AUTH_REQUIRED' || code == 'AUTH_INVALID';
  bool get quotaExceeded => code == 'QUOTA_EXCEEDED' || code == 'FILE_TOO_BIG';

  @override
  String toString() => message;
}

enum OcrHint { auto, cyrillic, latin, handwriting }

enum AiVisionTask { table, solve, formula, explain, deadlines }

class AiService {
  AiService._();

  static Dio get _dio => ApiClient.instance.dio;

  /// Bitta faylning barcha sahifalari shu ID bilan yuboriladi — bepul rejada
  /// ko'p sahifali fayl bitta fayl hisoblanadi.
  static String newFileId() {
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    final r = Random.secure();
    return List.generate(20, (_) => chars[r.nextInt(chars.length)]).join();
  }

  static Future<AiAccount> me() async {
    final res = await _guard(() => _dio.get<Map<String, dynamic>>('/me'));
    return AiAccount.fromJson(res.data!);
  }

  /// Bitta sahifa/rasmdagi matnni AI orqali o'qiydi (1 birlik limit sarflanadi).
  static Future<({String text, AiQuota? quota})> ocr(
    Uint8List imageBytes, {
    OcrHint hint = OcrHint.auto,
    String? fileId,
  }) async {
    final jpeg = await compute(_prepareJpeg, (imageBytes, 2000, 85));
    final res = await _guard(
      () => _dio.post<Map<String, dynamic>>(
        '/ai/ocr',
        data: {
          'image': base64Encode(jpeg),
          'mediaType': 'image/jpeg',
          'hint': hint.name,
          if (fileId != null) 'fileId': fileId,
        },
      ),
    );
    final data = res.data!;
    final q = data['quota'];
    return (
      text: (data['text'] as String?) ?? '',
      quota: q is Map<String, dynamic> ? AiQuota.fromJson(q) : null,
    );
  }

  /// Rasm bo'yicha AI vazifasi ([AiVisionTask]); javob [lang] tilida.
  /// Natija — vazifa sxemasidagi JSON (1 birlik limit sarflanadi).
  static Future<({Map<String, dynamic> result, AiQuota? quota})> vision(
    Uint8List imageBytes, {
    required AiVisionTask task,
    required String lang,
  }) async {
    final jpeg = await compute(_prepareJpeg, (imageBytes, 2000, 85));
    final res = await _guard(
      () => _dio.post<Map<String, dynamic>>(
        '/ai/vision',
        data: {
          'task': task.name,
          'image': base64Encode(jpeg),
          'mediaType': 'image/jpeg',
          'lang': lang,
        },
      ),
    );
    final data = res.data!;
    final q = data['quota'];
    return (
      result: (data['result'] as Map<String, dynamic>?) ?? const {},
      quota: q is Map<String, dynamic> ? AiQuota.fromJson(q) : null,
    );
  }

  /// Birinchi sahifaga qarab hujjatga nom taklif qiladi (limitga kirmaydi).
  static Future<String> suggestName(
    Uint8List imageBytes, {
    required String lang,
  }) async {
    final jpeg = await compute(_prepareJpeg, (imageBytes, 1024, 80));
    final res = await _guard(
      () => _dio.post<Map<String, dynamic>>(
        '/ai/suggest-name',
        data: {
          'image': base64Encode(jpeg),
          'mediaType': 'image/jpeg',
          'lang': lang,
        },
      ),
    );
    return (res.data!['title'] as String?)?.trim() ?? '';
  }

  /// Matnni yoki rasmni tarjima qiladi. [source] 'auto' bo'lsa til avtomatik aniqlanadi.
  static Future<({String translation, String? detected, AiQuota? quota})>
  translate({
    String? text,
    Uint8List? imageBytes,
    required String source,
    required String target,
    String? fileId,
  }) async {
    final body = <String, dynamic>{
      'source': source,
      'target': target,
      if (fileId != null) 'fileId': fileId,
    };
    if (imageBytes != null) {
      final jpeg = await compute(_prepareJpeg, (imageBytes, 2000, 85));
      body['image'] = base64Encode(jpeg);
      body['mediaType'] = 'image/jpeg';
    } else {
      body['text'] = text ?? '';
    }
    final res = await _guard(
      () => _dio.post<Map<String, dynamic>>('/ai/translate', data: body),
    );
    final data = res.data!;
    final q = data['quota'];
    return (
      translation: (data['translation'] as String?) ?? '',
      detected: data['detected'] as String?,
      quota: q is Map<String, dynamic> ? AiQuota.fromJson(q) : null,
    );
  }

  /// Google Play xaridini server orqali tasdiqlaydi.
  static Future<AiAccount> verifyPurchase({
    required String productId,
    required String purchaseToken,
  }) async {
    final res = await _guard(
      () => _dio.post<Map<String, dynamic>>(
        '/billing/verify',
        data: {'productId': productId, 'purchaseToken': purchaseToken},
      ),
    );
    return AiAccount.fromJson(res.data!);
  }

  static Future<void> deleteAccountData() async {
    await _guard(() => _dio.delete<Map<String, dynamic>>('/me'));
  }

  static Future<Response<T>> _guard<T>(
    Future<Response<T>> Function() request,
  ) async {
    if (!ApiClient.isSignedIn) {
      throw const AiException('AUTH_REQUIRED', 'Avval tizimga kiring');
    }
    try {
      return await request();
    } on DioException catch (e) {
      final body = e.response?.data;
      if (body is Map && body['error'] is Map) {
        final err = body['error'] as Map;
        final q = err['quota'];
        throw AiException(
          err['code'] as String? ?? 'UNKNOWN',
          err['message'] as String? ?? 'Xatolik',
          quota: q is Map<String, dynamic> ? AiQuota.fromJson(q) : null,
        );
      }
      throw const AiException('NETWORK', 'Internet aloqasini tekshiring');
    }
  }
}

/// Rasmni kichraytirib JPEG qiladi — trafik va AI xarajatini kamaytiradi.
/// (compute() orqali alohida isolate'da ishlaydi.)
Uint8List _prepareJpeg((Uint8List, int, int) args) {
  final (bytes, maxSide, quality) = args;
  var decoded = img.decodeImage(bytes);
  if (decoded == null) return bytes;
  decoded = img.bakeOrientation(decoded);
  final longest = decoded.width > decoded.height
      ? decoded.width
      : decoded.height;
  if (longest > maxSide) {
    decoded = decoded.width >= decoded.height
        ? img.copyResize(decoded, width: maxSide)
        : img.copyResize(decoded, height: maxSide);
  }
  return Uint8List.fromList(img.encodeJpg(decoded, quality: quality));
}
