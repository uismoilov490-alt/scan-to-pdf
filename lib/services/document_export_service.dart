import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pdfx/pdfx.dart' as pdfx;
import 'package:printing/printing.dart';
import 'package:xml/xml.dart';
import 'ad_service.dart';

enum ExportFormat { docx, pdf, jpg, png }

extension ExportFormatExt on ExportFormat {
  String get ext => switch (this) {
    ExportFormat.docx => 'docx',
    ExportFormat.pdf => 'pdf',
    ExportFormat.jpg => 'jpg',
    ExportFormat.png => 'png',
  };

  String get label => switch (this) {
    ExportFormat.docx => 'Word',
    ExportFormat.pdf => 'PDF',
    ExportFormat.jpg => 'JPG',
    ExportFormat.png => 'PNG',
  };

  bool get isImage => this == ExportFormat.jpg || this == ExportFormat.png;
}

/// Matnni Word/PDF/rasm ko'rinishiga chiqarish va Word'dan matn o'qish.
class DocumentExportService {
  static const _rtlLanguages = {'ar', 'fa', 'ur', 'he'};

  /// .docx ichidagi matnni xatboshilar bo'yicha (har biri yangi qatordan) qaytaradi.
  static String docxText(List<int> bytes) {
    final archive = ZipDecoder().decodeBytes(bytes);
    final entry = archive.findFile('word/document.xml');
    if (entry == null) return '';
    final doc = XmlDocument.parse(utf8.decode(entry.content as List<int>));
    final paragraphs = <String>[];
    for (final para in doc.findAllElements('w:p')) {
      final buf = StringBuffer();
      for (final node in para.descendants.whereType<XmlElement>()) {
        switch (node.name.qualified) {
          case 'w:t':
            buf.write(node.innerText);
          case 'w:tab':
            buf.write('\t');
          case 'w:br':
            buf.write('\n');
        }
      }
      paragraphs.add(buf.toString());
    }
    return paragraphs.join('\n').trim();
  }

  /// Oddiy matndan .docx (har qator — alohida xatboshi).
  static Uint8List buildDocx(String text, {bool rtl = false}) {
    final archive = Archive();
    const contentTypes =
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
        '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
        '<Default Extension="xml" ContentType="application/xml"/>'
        '<Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>'
        '</Types>';
    const rels =
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>'
        '</Relationships>';
    const docRels =
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '</Relationships>';

    final pPr = rtl ? '<w:pPr><w:bidi/></w:pPr>' : '';
    final rPr = rtl ? '<w:rPr><w:rtl/></w:rPr>' : '';
    final paras = text.split('\n').map((line) {
      final escaped = line
          .replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F]'), '')
          .replaceAll('&', '&amp;')
          .replaceAll('<', '&lt;')
          .replaceAll('>', '&gt;');
      return '<w:p>$pPr<w:r>$rPr<w:t xml:space="preserve">$escaped</w:t></w:r></w:p>';
    }).join();

    final docXml =
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">'
        '<w:body>$paras'
        '<w:sectPr><w:pgSz w:w="11906" w:h="16838"/>'
        '<w:pgMar w:top="1134" w:right="850" w:bottom="1134" w:left="1701"/>'
        '</w:sectPr></w:body></w:document>';

    void add(String name, String content) {
      final bytes = utf8.encode(content);
      archive.addFile(ArchiveFile(name, bytes.length, bytes));
    }

    add('[Content_Types].xml', contentTypes);
    add('_rels/.rels', rels);
    add('word/document.xml', docXml);
    add('word/_rels/document.xml.rels', docRels);
    return Uint8List.fromList(ZipEncoder().encode(archive)!);
  }

  /// Til yozuviga mos shrift (Google Fonts'dan, birinchi marta internet kerak).
  static Future<List<pw.Font>> _fallbackFonts(String langCode) async {
    return switch (langCode) {
      'ar' || 'fa' || 'ur' => [await PdfGoogleFonts.notoSansArabicRegular()],
      'he' => [await PdfGoogleFonts.notoSansHebrewRegular()],
      'ko' => [await PdfGoogleFonts.notoSansKRRegular()],
      'ja' => [await PdfGoogleFonts.notoSansJPRegular()],
      'zh' => [await PdfGoogleFonts.notoSansSCRegular()],
      'th' => [await PdfGoogleFonts.notoSansThaiRegular()],
      'ka' => [await PdfGoogleFonts.notoSansGeorgianRegular()],
      'hy' => [await PdfGoogleFonts.notoSansArmenianRegular()],
      'hi' => [await PdfGoogleFonts.notoSansDevanagariRegular()],
      _ => const [],
    };
  }

  /// Matndan A4 PDF (sahifalarga avtomatik bo'linadi).
  static Future<Uint8List> buildPdf(
    String text, {
    required String langCode,
  }) async {
    final base = await PdfGoogleFonts.notoSansRegular();
    final fallback = await _fallbackFonts(langCode);
    final rtl = _rtlLanguages.contains(langCode);
    final style = pw.TextStyle(
      font: base,
      fontFallback: fallback,
      fontSize: 12,
      lineSpacing: 3,
    );

    final doc = pw.Document();
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(56, 48, 48, 48),
        textDirection: rtl ? pw.TextDirection.rtl : pw.TextDirection.ltr,
        build: (_) => text
            .split('\n')
            .map(
              (line) => pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 4),
                child: pw.Text(line.isEmpty ? ' ' : line, style: style),
              ),
            )
            .toList(),
      ),
    );
    return doc.save();
  }

  /// PDF sahifalarini rasmga (har sahifa — alohida fayl).
  static Future<List<Uint8List>> pdfToImages(
    Uint8List pdfBytes,
    ExportFormat format,
  ) async {
    final document = await pdfx.PdfDocument.openData(pdfBytes);
    final images = <Uint8List>[];
    try {
      for (var i = 1; i <= document.pagesCount; i++) {
        final page = await document.getPage(i);
        try {
          final rendered = await page.render(
            width: page.width * 2,
            height: page.height * 2,
            format: format == ExportFormat.png
                ? pdfx.PdfPageImageFormat.png
                : pdfx.PdfPageImageFormat.jpeg,
            backgroundColor: '#ffffff',
            quality: 92,
          );
          if (rendered != null) images.add(rendered.bytes);
        } finally {
          await page.close();
        }
      }
    } finally {
      await document.close();
    }
    return images;
  }

  /// Tarjima natijasini kerakli formatda saqlaydi. Rasm formatida bir nechta fayl bo'lishi mumkin.
  static Future<List<File>> export(
    String text, {
    required ExportFormat format,
    required String baseName,
    required String langCode,
  }) async {
    AdService.recordSave();
    final dir = await _outputDir();
    final rtl = _rtlLanguages.contains(langCode);
    if (format == ExportFormat.docx) {
      return [await _write(dir, baseName, 'docx', buildDocx(text, rtl: rtl))];
    }
    final pdf = await buildPdf(text, langCode: langCode);
    if (format == ExportFormat.pdf) {
      return [await _write(dir, baseName, 'pdf', pdf)];
    }
    final pages = await pdfToImages(pdf, format);
    final files = <File>[];
    for (var i = 0; i < pages.length; i++) {
      final name = pages.length == 1 ? baseName : '${baseName}_${i + 1}';
      files.add(await _write(dir, name, format.ext, pages[i]));
    }
    return files;
  }

  static Future<Directory> _outputDir() async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(base.path, 'scan_to_pdf', 'tarjimalar'));
    await dir.create(recursive: true);
    return dir;
  }

  static Future<File> _write(
    Directory dir,
    String baseName,
    String ext,
    List<int> bytes,
  ) async {
    final safe = baseName.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
    var counter = 0;
    while (true) {
      final suffix = counter == 0 ? '' : '_$counter';
      final file = File(
        p.join(dir.path, '${safe.isEmpty ? 'tarjima' : safe}$suffix.$ext'),
      );
      if (!await file.exists()) {
        await file.writeAsBytes(bytes);
        return file;
      }
      counter++;
    }
  }
}
