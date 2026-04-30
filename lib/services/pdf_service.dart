import 'dart:io';
import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';

class PdfService {
  static Future<File> generatePdf({
    required List<File> imageFiles,
    required String fileName,
    List<int>? quarterTurns,
  }) async {
    final pdf = pw.Document();

    for (int i = 0; i < imageFiles.length; i++) {
      final bytes = await imageFiles[i].readAsBytes();
      var decoded = img.decodeImage(bytes);
      if (decoded == null) continue;

      final turns = quarterTurns != null ? quarterTurns[i] : 0;
      if (turns != 0) {
        decoded = img.copyRotate(decoded, angle: turns * 90.0);
      }

      final processedBytes = _enhanceImage(decoded);
      final pdfImage = pw.MemoryImage(processedBytes);

      final isLandscape = decoded.width > decoded.height;
      final pageFormat =
          isLandscape ? PdfPageFormat.a4.landscape : PdfPageFormat.a4;

      pdf.addPage(
        pw.Page(
          pageFormat: pageFormat,
          margin: const pw.EdgeInsets.all(0),
          build: (context) => pw.Center(
            child: pw.Image(pdfImage, fit: pw.BoxFit.contain),
          ),
        ),
      );
    }

    final dir = await getApplicationDocumentsDirectory();
    final pdfDir = Directory('${dir.path}/scan_to_pdf');
    await pdfDir.create(recursive: true);

    final safe = fileName.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
    final baseName = safe.isEmpty ? 'scan_document' : safe;
    final file = await _resolveUniquePdfFile(pdfDir.path, baseName);
    await file.writeAsBytes(await pdf.save());
    return file;
  }

  static Uint8List _enhanceImage(img.Image source) {
    var result = source;
    if (source.width > 2480) {
      result = img.copyResize(
        source,
        width: 2480,
        interpolation: img.Interpolation.linear,
      );
    }
    result = img.adjustColor(result, contrast: 1.15, brightness: 1.05);
    return Uint8List.fromList(img.encodeJpg(result, quality: 88));
  }

  static Future<List<File>> listSavedPdfs() async {
    final dir = await getApplicationDocumentsDirectory();
    final pdfDir = Directory('${dir.path}/scan_to_pdf');
    if (!await pdfDir.exists()) return [];

    final files = pdfDir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.pdf'))
        .toList();

    files.sort(
      (a, b) => b.statSync().modified.compareTo(a.statSync().modified),
    );
    return files;
  }

  static Future<void> deletePdf(String path) async {
    final file = File(path);
    if (await file.exists()) await file.delete();
  }

  static Future<File> _resolveUniquePdfFile(
    String dirPath,
    String baseName,
  ) async {
    var counter = 0;
    while (true) {
      final suffix = counter == 0 ? '' : '_$counter';
      final candidate = File('$dirPath/$baseName$suffix.pdf');
      if (!await candidate.exists()) return candidate;
      counter++;
    }
  }
}
