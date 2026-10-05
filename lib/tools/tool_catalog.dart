import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_document_scanner/google_mlkit_document_scanner.dart';
import 'package:printing/printing.dart';

import '../screens/features/cyrillic_latin_screen.dart';
import '../screens/features/document_clean_screen.dart';
import '../screens/features/image_convert_screen.dart';
import '../screens/features/ocr_screen.dart';
import '../screens/features/overlay_camera_screen.dart';
import '../screens/features/pdf_compress_screen.dart';
import '../screens/features/pdf_edit_screen.dart';
import '../screens/features/pdf_to_word_screen.dart';
import '../screens/features/translate_screen.dart';
import '../screens/features/word_to_pdf_screen.dart';
import '../screens/preview_screen.dart';
import '../screens/scanner_screen.dart';
import '../screens/tools/ai_vision_screen.dart';
import '../screens/tools/book_scan_screen.dart';
import '../screens/tools/pdf_merge_screen.dart';
import '../screens/tools/pdf_page_numbers_screen.dart';
import '../screens/tools/pdf_security_screen.dart';
import '../screens/tools/pdf_sign_screen.dart';
import '../screens/tools/pdf_split_screen.dart';
import '../screens/tools/pdf_to_ppt_screen.dart';
import '../screens/tools/pdf_watermark_screen.dart';
import '../screens/tools/photo_timestamp_screen.dart';
import '../screens/tools/qr_scanner_screen.dart';
import '../services/ai_service.dart';
import '../widgets/pdf_source_sheet.dart';

enum ToolCategory { scan, pdf, ai, convert, image }

extension ToolCategoryX on ToolCategory {
  String get titleKey => 'cat_$name';
}

/// Ilovadagi bitta vosita. Hamma vositalar shu yerda bir marta tavsiflanadi —
/// bosh sahifa ham, "Vositalar" menyusi ham shu ro'yxatdan quriladi.
class Tool {
  final String id;
  final String titleKey;
  final IconData? icon;

  /// Belgi o'rniga qisqa matn (masalan "Я⇄A")
  final String? label;
  final Color color;
  final Color iconColor;
  final ToolCategory category;

  /// AI (server) ishlatadi — ikonkada yulduzcha
  final bool ai;
  final Future<void> Function(BuildContext context) open;

  const Tool({
    required this.id,
    required this.titleKey,
    required this.color,
    required this.category,
    required this.open,
    this.icon,
    this.label,
    this.iconColor = Colors.white,
    this.ai = false,
  });
}

Future<void> _push(BuildContext context, Widget screen) =>
    Navigator.push(context, MaterialPageRoute<void>(builder: (_) => screen));

abstract final class ToolCatalog {
  /// Hujjat skaneri: Google ML Kit (varaq chetini topadi, qiyshiqni to'g'rilaydi).
  /// Qurilmada ishlamasa — oddiy kamera skaneri.
  static Future<void> scanDocument(BuildContext context) async {
    final scanner = DocumentScanner(
      options: DocumentScannerOptions(
        pageLimit: 50,
        mode: ScannerMode.full,
        isGalleryImport: true,
      ),
    );
    try {
      final result = await scanner.scanDocument();
      final pages = (result.images ?? []).map(File.new).toList();
      if (pages.isEmpty || !context.mounted) return;
      await _push(
        context,
        PreviewScreen(pages: pages, enhance: false, autoClean: true),
      );
    } on PlatformException catch (e) {
      if ((e.message ?? '').contains('cancelled') || !context.mounted) return;
      await _push(context, const ScannerScreen());
    } finally {
      scanner.close();
    }
  }

  /// PDF'ni telefonning chop etish oynasiga yuboradi (alohida ekransiz).
  static Future<void> _print(BuildContext context) async {
    final pdf = await pickPdfBytes(context);
    if (pdf == null) return;
    await Printing.layoutPdf(name: pdf.name, onLayout: (_) async => pdf.bytes);
  }

  static Tool _convert(
    String id,
    ConvertMode mode,
    IconData icon,
    Color color,
  ) => Tool(
    id: id,
    titleKey: mode.titleKey,
    icon: icon,
    color: color,
    category: ToolCategory.convert,
    open: (c) => _push(c, ImageConvertScreen(mode: mode)),
  );

  static final List<Tool> all = [
    // ── Skanerlash
    const Tool(
      id: 'document',
      titleKey: 'feature_document',
      icon: Icons.document_scanner_outlined,
      color: Color(0xFF0A84FF),
      category: ToolCategory.scan,
      open: scanDocument,
    ),
    Tool(
      id: 'passport',
      titleKey: 'feature_passport',
      icon: Icons.badge_outlined,
      color: const Color(0xFF0066CC),
      category: ToolCategory.scan,
      open: (c) =>
          _push(c, const OverlayCameraScreen(mode: ScanOverlayMode.passport)),
    ),
    Tool(
      id: 'id_card',
      titleKey: 'feature_id_card',
      icon: Icons.credit_card_outlined,
      color: const Color(0xFF5856D6),
      category: ToolCategory.scan,
      open: (c) =>
          _push(c, const OverlayCameraScreen(mode: ScanOverlayMode.idCard)),
    ),
    Tool(
      id: 'qr',
      titleKey: 'feature_qr',
      icon: Icons.qr_code_scanner_rounded,
      color: const Color(0xFF1C1C1E),
      category: ToolCategory.scan,
      open: (c) => _push(c, const QrScannerScreen()),
    ),
    Tool(
      id: 'book',
      titleKey: 'feature_book',
      icon: Icons.menu_book_outlined,
      color: const Color(0xFFA2845E),
      category: ToolCategory.scan,
      open: (c) => _push(c, const BookScanScreen()),
    ),
    // ── AI
    Tool(
      id: 'extract_text',
      titleKey: 'feature_extract_text',
      icon: Icons.text_snippet_outlined,
      color: const Color(0xFFFF9500),
      category: ToolCategory.ai,
      ai: true,
      open: (c) => _push(c, const OcrScreen()),
    ),
    Tool(
      id: 'translit',
      titleKey: 'translit_feature_both',
      label: 'Я⇄A',
      color: const Color(0xFFAF52DE),
      category: ToolCategory.ai,
      ai: true,
      open: (c) => _push(c, const CyrillicLatinScreen()),
    ),
    Tool(
      id: 'translate',
      titleKey: 'feature_translate',
      icon: Icons.language_rounded,
      color: const Color(0xFFBF5AF2),
      category: ToolCategory.ai,
      ai: true,
      open: (c) => _push(c, const TranslateScreen()),
    ),
    Tool(
      id: 'explain',
      titleKey: 'feature_explain',
      icon: Icons.psychology_alt_outlined,
      color: const Color(0xFF0A84FF),
      category: ToolCategory.ai,
      ai: true,
      open: (c) => _push(c, const AiVisionScreen(task: AiVisionTask.explain)),
    ),
    Tool(
      id: 'deadlines',
      titleKey: 'feature_deadlines',
      icon: Icons.event_note_rounded,
      color: const Color(0xFFFF453A),
      category: ToolCategory.ai,
      ai: true,
      open: (c) => _push(c, const AiVisionScreen(task: AiVisionTask.deadlines)),
    ),
    Tool(
      id: 'solver',
      titleKey: 'feature_solver',
      icon: Icons.calculate_outlined,
      color: const Color(0xFF7C3AED),
      category: ToolCategory.ai,
      ai: true,
      open: (c) => _push(c, const AiVisionScreen(task: AiVisionTask.solve)),
    ),
    Tool(
      id: 'formula',
      titleKey: 'feature_formula',
      icon: Icons.functions_rounded,
      color: const Color(0xFF0EA5E9),
      category: ToolCategory.ai,
      ai: true,
      open: (c) => _push(c, const AiVisionScreen(task: AiVisionTask.formula)),
    ),
    Tool(
      id: 'excel',
      titleKey: 'feature_excel',
      icon: Icons.table_view_rounded,
      color: const Color(0xFF1D6F42),
      category: ToolCategory.convert,
      ai: true,
      open: (c) => _push(c, const AiVisionScreen(task: AiVisionTask.table)),
    ),
    // ── PDF
    Tool(
      id: 'pdf_edit',
      titleKey: 'feature_pdf_edit',
      icon: Icons.edit_document,
      color: const Color(0xFFFF3B30),
      category: ToolCategory.pdf,
      open: (c) => _push(c, const PdfEditScreen()),
    ),
    Tool(
      id: 'pdf_merge',
      titleKey: 'feature_pdf_merge',
      icon: Icons.call_merge_rounded,
      color: const Color(0xFFFF6B35),
      category: ToolCategory.pdf,
      open: (c) => _push(c, const PdfMergeScreen()),
    ),
    Tool(
      id: 'pdf_split',
      titleKey: 'feature_pdf_split',
      icon: Icons.call_split_rounded,
      color: const Color(0xFFE0457B),
      category: ToolCategory.pdf,
      open: (c) => _push(c, const PdfSplitScreen()),
    ),
    Tool(
      id: 'pdf_compress',
      titleKey: 'feature_pdf_compress',
      icon: Icons.compress_rounded,
      color: const Color(0xFF30B0C7),
      category: ToolCategory.pdf,
      open: (c) => _push(c, const PdfCompressScreen()),
    ),
    Tool(
      id: 'pdf_lock',
      titleKey: 'feature_pdf_lock',
      icon: Icons.lock_outline_rounded,
      color: const Color(0xFF3A3A3C),
      category: ToolCategory.pdf,
      open: (c) => _push(c, const PdfSecurityScreen(lock: true)),
    ),
    Tool(
      id: 'pdf_unlock',
      titleKey: 'feature_pdf_unlock',
      icon: Icons.lock_open_rounded,
      color: const Color(0xFF8E8E93),
      category: ToolCategory.pdf,
      open: (c) => _push(c, const PdfSecurityScreen(lock: false)),
    ),
    Tool(
      id: 'pdf_sign',
      titleKey: 'feature_pdf_sign',
      icon: Icons.draw_outlined,
      color: const Color(0xFF0B2A6F),
      category: ToolCategory.pdf,
      open: (c) => _push(c, const PdfSignScreen()),
    ),
    Tool(
      id: 'pdf_watermark',
      titleKey: 'feature_pdf_watermark',
      icon: Icons.branding_watermark_outlined,
      color: const Color(0xFF5E5CE6),
      category: ToolCategory.pdf,
      open: (c) => _push(c, const PdfWatermarkScreen()),
    ),
    Tool(
      id: 'page_numbers',
      titleKey: 'feature_page_numbers',
      icon: Icons.format_list_numbered_rounded,
      color: const Color(0xFF64D2FF),
      category: ToolCategory.pdf,
      open: (c) => _push(c, const PdfPageNumbersScreen()),
    ),
    Tool(
      id: 'print',
      titleKey: 'feature_print',
      icon: Icons.print_outlined,
      color: const Color(0xFF636366),
      category: ToolCategory.pdf,
      open: _print,
    ),
    // ── Konvertatsiya
    Tool(
      id: 'word_to_pdf',
      titleKey: 'feature_word_to_pdf',
      icon: Icons.description_outlined,
      color: const Color(0xFF34C759),
      category: ToolCategory.convert,
      open: (c) => _push(c, const WordToPdfScreen()),
    ),
    Tool(
      id: 'pdf_to_word',
      titleKey: 'feature_pdf_to_word',
      icon: Icons.swap_horiz_rounded,
      color: const Color(0xFF248A3D),
      category: ToolCategory.convert,
      open: (c) => _push(c, const PdfToWordScreen()),
    ),
    _convert(
      'jpg_to_pdf',
      ConvertMode.jpgToPdf,
      Icons.picture_as_pdf_outlined,
      const Color(0xFFDB2777),
    ),
    _convert(
      'pdf_to_jpg',
      ConvertMode.pdfToJpg,
      Icons.image_outlined,
      const Color(0xFFEA580C),
    ),
    Tool(
      id: 'pdf_to_ppt',
      titleKey: 'feature_pdf_to_ppt',
      icon: Icons.slideshow_rounded,
      color: const Color(0xFFD24726),
      category: ToolCategory.convert,
      open: (c) => _push(c, const PdfToPptScreen()),
    ),
    _convert(
      'pdf_to_long',
      ConvertMode.pdfToLongImage,
      Icons.view_day_outlined,
      const Color(0xFFF59E0B),
    ),
    _convert(
      'webp_to_jpg',
      ConvertMode.webpToJpg,
      Icons.public_rounded,
      const Color(0xFF0EA5E9),
    ),
    _convert(
      'png_to_jpg',
      ConvertMode.pngToJpg,
      Icons.transform_rounded,
      const Color(0xFF65A30D),
    ),
    _convert(
      'jpg_to_png',
      ConvertMode.jpgToPng,
      Icons.wallpaper_rounded,
      const Color(0xFF8B5CF6),
    ),
    // ── Rasm
    Tool(
      id: 'clean',
      titleKey: 'feature_clean',
      icon: Icons.auto_fix_high_outlined,
      color: const Color(0xFF32ADE6),
      category: ToolCategory.image,
      open: (c) => _push(c, const DocumentCleanScreen()),
    ),
    Tool(
      id: 'timestamp',
      titleKey: 'feature_timestamp',
      icon: Icons.schedule_rounded,
      color: const Color(0xFFFF9F0A),
      category: ToolCategory.image,
      open: (c) => _push(c, const PhotoTimestampScreen()),
    ),
  ];

  /// Bosh sahifadagi eng kerakli vositalar (10-o'rinda "Barcha vositalar").
  /// 1-qator skanerlash, 2-qator AI, 3-qator PDF.
  static const _homeIds = [
    'document',
    'passport',
    'id_card',
    'extract_text',
    'translit',
    'translate',
    'pdf_edit',
    'pdf_merge',
    'pdf_compress',
  ];

  static List<Tool> get home => [
    for (final id in _homeIds) all.firstWhere((t) => t.id == id),
  ];

  static Map<ToolCategory, List<Tool>> get byCategory => {
    for (final c in ToolCategory.values)
      c: [
        for (final t in all)
          if (t.category == c) t,
      ],
  };
}
