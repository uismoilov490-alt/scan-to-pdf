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

  /// Tayyor rasm baytlarini scan_to_pdf/rasmlar papkasiga noyob nom bilan yozadi.
  /// Tayyor rasm baytlarini  ga noyob nom bilan yozadi.
  static Future<File> saveImage(
    List<int> bytes,
    String baseName, {
    String ext = 'jpg',
  }) async {
    final out = await _uniqueFile(await _outputDir(), baseName, ext);
    await out.writeAsBytes(bytes, flush: true);
    AdService.recordSave();
    return out;
  }

  /// PDF sahifalarini ustma-ust bitta uzun JPG rasmga ulaydi (messenjer uchun
  /// qulay). Xotira chegarasi: balandlik [_longMaxHeight] dan oshsa, eni
  /// mutanosib kichraytiriladi.
  static const _longWidth = 1080;
  static const _longMaxHeight = 16000;

  static Future<List<File>> pdfToLongImage(
    File pdf, {
    void Function(int done, int total)? onProgress,
  }) async {
    final document = await PdfDocument.openFile(pdf.path);
    final pages = <Uint8List>[];
    try {
      final total = document.pagesCount;
      final ratios = <double>[];
      for (var i = 1; i <= total; i++) {
        final page = await document.getPage(i);
        ratios.add(page.height / page.width);
        await page.close();
      }
      final sum = ratios.fold<double>(0, (a, b) => a + b);
      final scale = (_longMaxHeight / (_longWidth * sum)).clamp(0.0, 1.0);
      final width = (_longWidth * scale).roundToDouble();
      for (var i = 1; i <= total; i++) {
        final page = await document.getPage(i);
        try {
          final r = await page.render(
            width: width,
            height: (width * ratios[i - 1]).roundToDouble(),
            format: PdfPageImageFormat.jpeg,
            backgroundColor: '#ffffff',
            quality: 92,
          );
          if (r != null) pages.add(r.bytes);
        } finally {
          await page.close();
        }
        onProgress?.call(i, total);
      }
    } finally {
      await document.close();
    }
    if (pages.isEmpty) return [];
    final jpg = await compute(_stitch, pages);
    final out = await _uniqueFile(
      await _outputDir(),
      '${p.basenameWithoutExtension(pdf.path)}_long',
      'jpg',
    );
    await out.writeAsBytes(jpg, flush: true);
    AdService.recordSave();
    return [out];
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

/// Rasmlarni ustma-ust bitta rasmga ulaydi (compute() orqali, alohida isolate'da).
Uint8List _stitch(List<Uint8List> parts) {
  final images = [for (final b in parts) img.decodeJpg(b)!];
  final width = images.first.width;
  final height = images.fold<int>(0, (h, i) => h + i.height);
  final canvas = img.Image(width: width, height: height)
    ..clear(img.ColorRgb8(255, 255, 255));
  var y = 0;
  for (final i in images) {
    img.compositeImage(canvas, i, dstX: 0, dstY: y);
    y += i.height;
  }
  return Uint8List.fromList(img.encodeJpg(canvas, quality: 88));
}
