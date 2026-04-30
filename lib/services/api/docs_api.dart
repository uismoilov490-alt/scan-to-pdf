import 'dart:io';
import 'package:dio/dio.dart';
import 'api_client.dart';

enum DocType { scan, ocr, compress, wordToPdf, pdfToWord, passportScan, idCardScan }
enum DocStatus { pending, processing, done, failed }

class DocRecord {
  final String id;
  final DocType type;
  final DocStatus status;
  final String name;
  final int? fileSize;
  final int? pageCount;
  final Map<String, dynamic>? metadata;
  final String? error;
  final DateTime createdAt;

  const DocRecord({
    required this.id,
    required this.type,
    required this.status,
    required this.name,
    this.fileSize,
    this.pageCount,
    this.metadata,
    this.error,
    required this.createdAt,
  });

  factory DocRecord.fromJson(Map<String, dynamic> j) => DocRecord(
    id:         j['id'] as String,
    type:       _parseType(j['type'] as String),
    status:     _parseStatus(j['status'] as String),
    name:       j['name'] as String,
    fileSize:   j['file_size'] as int?,
    pageCount:  j['page_count'] as int?,
    metadata:   j['metadata'] as Map<String, dynamic>?,
    error:      j['error'] as String?,
    createdAt:  DateTime.parse(j['created_at'] as String),
  );

  bool get isDone       => status == DocStatus.done;
  bool get isFailed     => status == DocStatus.failed;
  bool get isProcessing => status == DocStatus.pending || status == DocStatus.processing;
}

DocType _parseType(String s) => const {
  'scan':           DocType.scan,
  'ocr':            DocType.ocr,
  'compress':       DocType.compress,
  'word_to_pdf':    DocType.wordToPdf,
  'pdf_to_word':    DocType.pdfToWord,
  'passport_scan':  DocType.passportScan,
  'id_card_scan':   DocType.idCardScan,
}[s] ?? DocType.scan;

DocStatus _parseStatus(String s) => const {
  'pending':    DocStatus.pending,
  'processing': DocStatus.processing,
  'done':       DocStatus.done,
  'failed':     DocStatus.failed,
}[s] ?? DocStatus.pending;

class DocsApi {
  final Dio _dio = ApiClient.instance.dio;

  // ── List ─────────────────────────────────────────────────────
  Future<List<DocRecord>> list({int limit = 20, int offset = 0}) async {
    final res = await _dio.get('/docs', queryParameters: {
      'limit': limit, 'offset': offset,
    });
    return (res.data['data'] as List)
        .map((e) => DocRecord.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  // ── Get by ID ─────────────────────────────────────────────────
  Future<DocRecord> get(String id) async {
    final res = await _dio.get('/docs/$id');
    return DocRecord.fromJson(res.data['data'] as Map<String, dynamic>);
  }

  // ── Delete ────────────────────────────────────────────────────
  Future<void> delete(String id) => _dio.delete('/docs/$id');

  // ── Download (returns bytes) ──────────────────────────────────
  Future<List<int>> download(String id) async {
    final res = await _dio.get<List<int>>(
      '/docs/$id/download',
      options: Options(responseType: ResponseType.bytes),
    );
    return res.data!;
  }

  // ── Poll job until done (max 2 min) ────────────────────────────
  Future<DocRecord> pollJob(String jobId, {Duration interval = const Duration(seconds: 3)}) async {
    final deadline = DateTime.now().add(const Duration(minutes: 2));
    while (DateTime.now().isBefore(deadline)) {
      final doc = await get(jobId);
      if (!doc.isProcessing) return doc;
      await Future.delayed(interval);
    }
    throw Exception('Job timed out');
  }

  // ── Upload scanned PDF ────────────────────────────────────────
  Future<DocRecord> uploadScan(File pdfFile) async {
    final form = FormData.fromMap({
      'file': await MultipartFile.fromFile(
        pdfFile.path,
        filename: pdfFile.path.split('/').last,
        contentType: DioMediaType.parse('application/pdf'),
      ),
    });
    final res = await _dio.post('/docs/scan/upload', data: form);
    return DocRecord.fromJson(res.data['data'] as Map<String, dynamic>);
  }

  // ── OCR ──────────────────────────────────────────────────────
  Future<String> ocr(File imageFile, {String lang = 'uzb+rus+eng'}) async {
    final form = FormData.fromMap({
      'file': await MultipartFile.fromFile(imageFile.path,
          filename: imageFile.path.split('/').last),
      'lang': lang,
    });
    final res  = await _dio.post('/docs/ocr', data: form);
    final jobId = res.data['data']['job_id'] as String;
    final doc   = await pollJob(jobId);
    if (doc.isFailed) throw Exception(doc.error ?? 'OCR failed');
    // Download result JSON
    final bytes = await download(jobId);
    return String.fromCharCodes(bytes);
  }

  // ── Compress PDF ──────────────────────────────────────────────
  Future<String> compress(
    File pdfFile, {
    String quality = 'ebook',
  }) async {
    final form = FormData.fromMap({
      'file':    await MultipartFile.fromFile(pdfFile.path,
          filename: pdfFile.path.split('/').last),
      'quality': quality,
    });
    final res   = await _dio.post('/docs/compress', data: form);
    final jobId  = res.data['data']['job_id'] as String;
    final doc    = await pollJob(jobId);
    if (doc.isFailed) throw Exception(doc.error ?? 'Compress failed');
    return jobId;
  }

  // ── Word to PDF ───────────────────────────────────────────────
  Future<String> wordToPdf(File wordFile) async {
    final form = FormData.fromMap({
      'file': await MultipartFile.fromFile(wordFile.path,
          filename: wordFile.path.split('/').last),
    });
    final res  = await _dio.post('/docs/word-to-pdf', data: form);
    final jobId = res.data['data']['job_id'] as String;
    final doc   = await pollJob(jobId);
    if (doc.isFailed) throw Exception(doc.error ?? 'Conversion failed');
    return jobId;
  }

  // ── PDF to Word ───────────────────────────────────────────────
  Future<String> pdfToWord(File pdfFile) async {
    final form = FormData.fromMap({
      'file': await MultipartFile.fromFile(pdfFile.path,
          filename: pdfFile.path.split('/').last),
    });
    final res  = await _dio.post('/docs/pdf-to-word', data: form);
    final jobId = res.data['data']['job_id'] as String;
    final doc   = await pollJob(jobId);
    if (doc.isFailed) throw Exception(doc.error ?? 'Conversion failed');
    return jobId;
  }

  // ── Passport Scan ─────────────────────────────────────────────
  Future<Map<String, dynamic>> scanPassport(File imageFile) async {
    final form = FormData.fromMap({
      'file': await MultipartFile.fromFile(imageFile.path,
          filename: imageFile.path.split('/').last),
    });
    final res = await _dio.post('/docs/scan/passport', data: form);
    return res.data['data']['mrz'] as Map<String, dynamic>;
  }

  // ── ID Card Scan ──────────────────────────────────────────────
  Future<Map<String, dynamic>> scanIdCard(File imageFile) async {
    final form = FormData.fromMap({
      'file': await MultipartFile.fromFile(imageFile.path,
          filename: imageFile.path.split('/').last),
    });
    final res = await _dio.post('/docs/scan/id-card', data: form);
    return res.data['data']['card'] as Map<String, dynamic>;
  }
}
