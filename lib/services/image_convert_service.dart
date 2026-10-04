import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdfx/pdfx.dart';
import 'ad_service.dart';

enum ImageFormat { jpg, png }

/// Rasm formatlari orasida o'girish va PDF sahifalarini rasmga chiqarish.
/// Natijalar ilova papkasidagi `scan_to_pdf/rasmlar` ga yoziladi.
class ImageConvertService {
  static Future<Directory> _outputDir() async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(base.path, 'scan_to_pdf', 'rasmlar'));
    await dir.create(recursive: true);
    return dir;
  }

  static Future<File> _uniqueFile(
    Directory dir,
    String baseName,
    String ext,
  ) async {
    final safe = baseName.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
    final name = safe.isEmpty ? 'rasm' : safe;
    var counter = 0;
    while (true) {
      final suffix = counter == 0 ? '' : '_$counter';
      final file = File(p.join(dir.path, '$name$suffix.$ext'));
      if (!await file.exists()) return file;
      counter++;
    }
  }

  /// Har bir rasmni [to] formatiga o'giradi (JPG, PNG, WebP kirishi mumkin).
  static Future<List<File>> convertImages(
    List<File> inputs, {
    required ImageFormat to,
    void Function(int done, int total)? onProgress,
  }) async {
    final dir = await _outputDir();
    final ext = to == ImageFormat.jpg ? 'jpg' : 'png';
    final results = <File>[];
    for (var i = 0; i < inputs.length; i++) {
      final bytes = await inputs[i].readAsBytes();
      final encoded = await compute(_encode, (bytes, to));
      if (encoded != null) {
        final base = p.basenameWithoutExtension(inputs[i].path);
        final out = await _uniqueFile(dir, base, ext);
        await out.writeAsBytes(encoded);
        results.add(out);
      }
      onProgress?.call(i + 1, inputs.length);
    }
    if (results.isNotEmpty) AdService.recordSave();
    return results;
  }

  /// PDF'ning har bir sahifasini JPG rasmga aylantiradi.
  static Future<List<File>> pdfToJpg(
    File pdf, {
    void Function(int done, int total)? onProgress,
  }) async {
    final dir = await _outputDir();
    final base = p.basenameWithoutExtension(pdf.path);
    final document = await PdfDocument.openFile(pdf.path);
    final results = <File>[];
    try {
      final total = document.pagesCount;
      for (var i = 1; i <= total; i++) {
        final page = await document.getPage(i);
        try {
          final rendered = await page.render(
            width: page.width * 2,
            height: page.height * 2,
            format: PdfPageImageFormat.jpeg,
            backgroundColor: '#ffffff',
            quality: 92,
          );
          if (rendered != null) {
            final out = await _uniqueFile(
              dir,
              total == 1 ? base : '${base}_$i',
              'jpg',
            );
            await out.writeAsBytes(rendered.bytes);
            results.add(out);
          }
        } finally {
          await page.close();
        }
        onProgress?.call(i, total);
      }
    } finally {
      await document.close();
    }
    if (results.isNotEmpty) AdService.recordSave();
    return results;
  }
}

/// Alohida isolate'da: dekodlash + kerakli formatga kodlash.
/// JPG'da shaffoflik yo'q — shaffof joylar oq fon bilan to'ldiriladi.
Uint8List? _encode((Uint8List, ImageFormat) args) {
  final (bytes, to) = args;
  var image = img.decodeImage(bytes);
  if (image == null) return null;
  image = img.bakeOrientation(image);
  if (to == ImageFormat.jpg) {
    if (image.hasAlpha) {
      final background = img.Image(width: image.width, height: image.height);
      img.fill(background, color: img.ColorRgb8(255, 255, 255));
      img.compositeImage(background, image);
      image = background;
    }
    return Uint8List.fromList(img.encodeJpg(image, quality: 92));
  }
  return Uint8List.fromList(img.encodePng(image));
}
