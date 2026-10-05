import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:image/image.dart' as img;

/// Fotoga sana-vaqt yozish ("vaqt tamg'asi").
abstract final class PhotoStampService {
  /// Burilishi to'g'rilangan JPEG va surat olingan vaqt (EXIF DateTimeOriginal;
  /// bo'lmasa fayl o'zgartirilgan vaqti).
  static Future<({Uint8List jpeg, DateTime takenAt})> prepare(File file) async {
    final bytes = await file.readAsBytes();
    final modified = await file.lastModified();
    final result = await Isolate.run(() {
      final image = img.decodeImage(bytes);
      if (image == null) return null;
      final exif = img.decodeJpgExif(bytes);
      final raw = exif?.exifIfd['DateTimeOriginal']?.toString().trim();
      return (
        jpeg: Uint8List.fromList(
          img.encodeJpg(img.bakeOrientation(image), quality: 95),
        ),
        taken: raw,
      );
    });
    if (result == null) throw const FormatException('image');
    return (jpeg: result.jpeg, takenAt: _parseExif(result.taken) ?? modified);
  }

  /// "2026:10:04 18:30:12" → DateTime
  static DateTime? _parseExif(String? s) {
    final m = RegExp(
      r'^(\d{4}):(\d{2}):(\d{2}) (\d{2}):(\d{2}):(\d{2})',
    ).firstMatch(s ?? '');
    if (m == null) return null;
    final v = [for (var i = 1; i <= 6; i++) int.parse(m[i]!)];
    return DateTime(v[0], v[1], v[2], v[3], v[4], v[5]);
  }

  /// [jpeg] ning pastki o'ng burchagiga [text] yozadi (o'lcham rasmga mos).
  static Future<Uint8List> stamp(Uint8List jpeg, String text) async {
    final codec = await ui.instantiateImageCodec(jpeg);
    final image = (await codec.getNextFrame()).image;
    final w = image.width.toDouble();
    final h = image.height.toDouble();
    final fontSize = (w < h ? w : h) * 0.045;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)..drawImage(image, Offset.zero, Paint());
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: const Color(0xFFFF9F0A),
          fontSize: fontSize,
          fontWeight: FontWeight.w600,
          letterSpacing: fontSize * 0.04,
          shadows: [
            Shadow(color: const Color(0xCC000000), blurRadius: fontSize * 0.25),
          ],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final margin = fontSize * 0.8;
    painter.paint(
      canvas,
      Offset(w - painter.width - margin, h - painter.height - margin),
    );

    final out = await recorder.endRecording().toImage(
      image.width,
      image.height,
    );
    final rgba = await out.toByteData(format: ui.ImageByteFormat.rawRgba);
    final width = image.width;
    final height = image.height;
    image.dispose();
    out.dispose();
    final pixels = rgba!.buffer.asUint8List();
    // JPEG kodlash og'ir — alohida isolate'da
    return Isolate.run(
      () => Uint8List.fromList(
        img.encodeJpg(
          img.Image.fromBytes(
            width: width,
            height: height,
            bytes: pixels.buffer,
            numChannels: 4,
          ),
          quality: 92,
        ),
      ),
    );
  }
}
