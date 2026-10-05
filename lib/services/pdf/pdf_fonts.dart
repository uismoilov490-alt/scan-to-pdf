import 'dart:typed_data';

import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

/// PDF'ga yoziladigan matn uchun shrift: lotin-1'dan tashqari matnga Noto Sans
/// (Google Fonts, birinchi marta internet kerak, keyin keshdan).
abstract final class PdfFonts {
  static final _latin1 = RegExp(r'^[\u0000-ÿ]*$');

  /// [text]ni chiza oladigan TTF baytlari; oddiy lotin matni uchun null
  /// (PDF'ning ichki Helvetica shrifti yetadi, internet kerak emas).
  static Future<Uint8List?> forText(String text) async {
    if (_latin1.hasMatch(text)) return null;
    // Kirill, lotin kengaytmalari (o'zbek ʻ, turk, chex, rumin), yunon
    final font = await PdfGoogleFonts.notoSansRegular();
    final data = (font as pw.TtfFont).data;
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  }
}
