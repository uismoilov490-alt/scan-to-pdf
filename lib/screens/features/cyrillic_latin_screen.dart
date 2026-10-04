import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:open_filex/open_filex.dart';
import 'package:share_plus/share_plus.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pdfx/pdfx.dart' as pdfx;
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';

import '../../providers/subscription_provider.dart';
import '../../services/ai_service.dart';
import '../../services/api/api_client.dart';
import '../../services/transliteration_service.dart';
import '../../widgets/ai_error.dart';
import '../../services/ad_service.dart';
import '../../widgets/ai_badge.dart';

/// Krill ↔ Lotin: Word (.docx) va PDF fayllarni ikki yo'nalishda o'giradi.
class CyrillicLatinScreen extends StatefulWidget {
  /// Boshlang'ich yo'nalish: [Script.cyrillic] — lotinga, [Script.latin] — kirillga.
  final Script source;

  const CyrillicLatinScreen({super.key, this.source = Script.cyrillic});

  @override
  State<CyrillicLatinScreen> createState() => _CyrillicLatinScreenState();
}

class _CyrillicLatinScreenState extends State<CyrillicLatinScreen> {
  File? _file;
  String _fileExt = ''; // 'pdf' | 'docx'
  late Script _sourceScript = widget.source;
  // Fayldan aniqlangan yozuv — tanlangan yo'nalishga mos kelmasa ogohlantiramiz
  Script _detected = Script.unknown;
  bool get _scriptMismatch =>
      _detected != Script.unknown && _detected != _sourceScript;
  bool _analyzing = false;
  bool _converting = false;
  String _previewText = '';
  String? _outPath;
  int _curPage = 0;
  int _totPages = 0;
  // Ko'rib chiqishda AI o'qigan 1-sahifa matni — konvertatsiyada qayta pul sarflamaslik uchun.
  String? _aiFirstPageText;
  // Shu faylning barcha AI so'rovlari bitta fayl sifatida sanaladi
  String? _fileId;

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf', 'docx'],
    );
    if (result == null || result.files.single.path == null) return;

    final path = result.files.single.path!;
    final ext = path.split('.').last.toLowerCase();

    if (ext != 'pdf' && ext != 'docx') {
      if (mounted) {
        _showError('translit_unsupported'.tr());
      }
      return;
    }

    setState(() {
      _file = File(path);
      _fileExt = ext;
      _detected = Script.unknown;
      _previewText = '';
      _outPath = null;
      _aiFirstPageText = null;
      _fileId = null;
      _analyzing = true;
    });

    await _analyzeFile();
  }

  Future<void> _analyzeFile() async {
    try {
      final bytes = await _file!.readAsBytes();
      String preview = '';

      if (_fileExt == 'docx') {
        preview = TransliterationService.extractDocxPreview(bytes);
      } else {
        preview = await _extractPdfFirstPageText();
      }

      final detected = TransliterationService.detectScript(preview);
      if (mounted) {
        setState(() {
          _previewText = preview.trim();
          _detected = detected;
          _analyzing = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _analyzing = false);
        _showError('translit_file_error'.tr());
      }
    }
  }

  Future<String> _extractPdfFirstPageText() async {
    final document = await pdfx.PdfDocument.openData(
      await _file!.readAsBytes(),
    );
    try {
      if (document.pagesCount == 0) return '';
      final bytes = await _renderPage(document, 1);
      if (bytes == null) return '';

      // ML Kit kirillni o'qiy olmaydi, shuning uchun yozuvni AI aniqlaydi
      // (1 birlik). Kirilmagan yoki limit tugagan bo'lsa — telefondagi OCR.
      final quota = context.read<SubscriptionProvider>().quota;
      if (_sourceScript == Script.cyrillic &&
          ApiClient.isSignedIn &&
          quota?.perFile == false) {
        try {
          _fileId = AiService.newFileId();
          final result = await AiService.ocr(bytes, fileId: _fileId);
          if (mounted)
            context.read<SubscriptionProvider>().updateQuota(result.quota);
          _aiFirstPageText = result.text;
          return result.text;
        } on AiException {
          // pastdagi ML Kit'ga o'tamiz
        }
      }
      return await _mlKitRead(bytes);
    } finally {
      await document.close();
    }
  }

  Future<Uint8List?> _renderPage(pdfx.PdfDocument document, int number) async {
    final page = await document.getPage(number);
    try {
      final rendered = await page.render(
        width: page.width * 2,
        height: page.height * 2,
        format: pdfx.PdfPageImageFormat.jpeg,
        backgroundColor: '#ffffff',
      );
      return rendered?.bytes;
    } finally {
      await page.close();
    }
  }

  Future<String> _mlKitRead(Uint8List bytes) async {
    final tempDir = await getTemporaryDirectory();
    final imgFile = File(
      '${tempDir.path}/tl_${DateTime.now().microsecondsSinceEpoch}.jpg',
    );
    await imgFile.writeAsBytes(bytes);
    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final result = await recognizer.processImage(
        InputImage.fromFile(imgFile),
      );
      return result.text;
    } finally {
      await recognizer.close();
      try {
        await imgFile.delete();
      } catch (_) {}
    }
  }

  Future<void> _convertFile() async {
    if (_file == null || _sourceScript == Script.unknown) return;
    setState(() {
      _converting = true;
      _outPath = null;
      _curPage = 0;
      _totPages = 0;
    });

    try {
      final outFile = _fileExt == 'docx'
          ? await _convertDocx()
          : await _convertPdf();

      if (mounted) {
        setState(() {
          _outPath = outFile.path;
          _converting = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'translit_saved'.tr(
                namedArgs: {'name': outFile.path.split('/').last},
              ),
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } on AiException catch (e) {
      if (!mounted) return;
      setState(() => _converting = false);
      await showAiError(context, e);
    } catch (e) {
      if (mounted) {
        setState(() => _converting = false);
        _showError('error_prefix'.tr(namedArgs: {'message': '$e'}));
      }
    }
  }

  Future<File> _convertDocx() async {
    final bytes = await _file!.readAsBytes();
    final converted = TransliterationService.convertDocxBytes(
      bytes,
      _sourceScript,
    );
    return _saveOutput(converted, _outSuffix('docx'));
  }

  Future<File> _convertPdf() async {
    final document = await pdfx.PdfDocument.openData(
      await _file!.readAsBytes(),
    );
    final pageCount = document.pagesCount;
    // Kirill matnni faqat AI to'g'ri o'qiydi; lotinni telefondagi ML Kit bepul o'qiydi.
    final useAi = _sourceScript == Script.cyrillic;

    if (mounted) setState(() => _totPages = pageCount);

    final paragraphs = <String>[];

    try {
      if (useAi) {
        _fileId ??= AiService.newFileId();
        _ensureAiQuotaFor(pageCount - (_aiFirstPageText != null ? 1 : 0));
      }

      for (int i = 1; i <= pageCount; i++) {
        if (!mounted) break;
        setState(() => _curPage = i);

        final String text;
        if (useAi && i == 1 && _aiFirstPageText != null) {
          text = _aiFirstPageText!;
        } else {
          final bytes = await _renderPage(document, i);
          if (bytes == null) continue;
          if (useAi) {
            final result = await AiService.ocr(
              bytes,
              hint: OcrHint.cyrillic,
              fileId: _fileId,
            );
            if (mounted)
              context.read<SubscriptionProvider>().updateQuota(result.quota);
            text = result.text;
          } else {
            text = await _mlKitRead(bytes);
          }
        }

        if (text.isNotEmpty) {
          paragraphs.add(
            useAi
                ? TransliterationService.toLatin(text)
                : TransliterationService.toCyrillic(text),
          );
        }
      }
    } finally {
      await document.close();
    }

    return _buildAndSavePdf(paragraphs);
  }

  /// Fayl yarmida limit tugab qolmasligi uchun oldindan tekshiramiz.
  void _ensureAiQuotaFor(int pages) {
    if (!ApiClient.isSignedIn) {
      throw const AiException('AUTH_REQUIRED', '');
    }
    final error = context.read<SubscriptionProvider>().quota?.check(pages);
    if (error != null) throw error;
  }

  Future<File> _buildAndSavePdf(List<String> paragraphs) async {
    final fontRegular = await PdfGoogleFonts.notoSansRegular();
    final fontBold = await PdfGoogleFonts.notoSansBold();

    final doc = pw.Document(
      theme: pw.ThemeData.withFont(base: fontRegular, bold: fontBold),
    );

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(40),
        build: (ctx) => paragraphs.isEmpty
            ? [pw.Text('ocr_no_text'.tr())]
            : paragraphs
                  .expand(
                    (block) => block
                        .split('\n')
                        .where((l) => l.trim().isNotEmpty)
                        .map(
                          (line) => pw.Padding(
                            padding: const pw.EdgeInsets.only(bottom: 5),
                            child: pw.Text(
                              line,
                              style: pw.TextStyle(
                                font: fontRegular,
                                fontSize: 11,
                              ),
                            ),
                          ),
                        ),
                  )
                  .toList(),
      ),
    );

    final pdfBytes = await doc.save();
    return _saveOutput(pdfBytes, _outSuffix('pdf'));
  }

  Future<File> _saveOutput(List<int> bytes, String suffix) async {
    final docsDir = await getApplicationDocumentsDirectory();
    final saveDir = Directory('${docsDir.path}/scan_to_pdf');
    if (!await saveDir.exists()) await saveDir.create(recursive: true);
    final outFile = File('${saveDir.path}/$suffix');
    await outFile.writeAsBytes(bytes);
    AdService.recordSave();
    return outFile;
  }

  String _outSuffix(String ext) {
    final base = _file!.path
        .split('/')
        .last
        .replaceAll(RegExp(r'\.[^.]+$'), '');
    final tag = _sourceScript == Script.cyrillic ? 'lat' : 'cyr';
    final ts = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    return '${base}_${tag}_$ts.$ext';
  }

  void _showError(String msg) {
    final cs = Theme.of(context).colorScheme;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: TextStyle(color: cs.onErrorContainer)),
        backgroundColor: cs.errorContainer,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(title: AiTitle('translit_feature_both'.tr())),
      body: _buildFileTab(theme, cs),
    );
  }

  void _setDirection(Script source) {
    if (source == _sourceScript) return;
    setState(() {
      _sourceScript = source;
      _outPath = null;
    });
  }

  Widget _buildFileTab(ThemeData theme, ColorScheme cs) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        // Yo'nalish
        SegmentedButton<Script>(
          segments: [
            ButtonSegment(
              value: Script.cyrillic,
              label: Text('translit_cyr_to_lat'.tr()),
            ),
            ButtonSegment(
              value: Script.latin,
              label: Text('translit_lat_to_cyr'.tr()),
            ),
          ],
          selected: {_sourceScript},
          showSelectedIcon: false,
          onSelectionChanged: (_converting || _analyzing)
              ? null
              : (sel) => _setDirection(sel.first),
        ),
        const SizedBox(height: 12),

        // Fayl tanlash kartasi
        _FilePickCard(
          file: _file,
          onTap: (_converting || _analyzing) ? null : _pickFile,
        ),

        // Tahlil qilinmoqda
        if (_analyzing) ...[
          const SizedBox(height: 20),
          const Center(child: CircularProgressIndicator()),
          const SizedBox(height: 10),
          Center(
            child: Text(
              'translit_analyzing'.tr(),
              style: TextStyle(color: cs.onSurfaceVariant),
            ),
          ),
        ],

        // Alifbo aniqlandi → yo'nalish tanlash
        if (_file != null && !_analyzing) ...[
          const SizedBox(height: 16),
          if (_scriptMismatch) ...[
            _InfoBanner(
              icon: Icons.warning_amber_rounded,
              color: cs.error,
              text: _sourceScript == Script.cyrillic
                  ? 'translit_mismatch_latin'.tr()
                  : 'translit_mismatch_cyrillic'.tr(),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () => _setDirection(_detected),
                icon: const Icon(Icons.swap_horiz_rounded),
                label: Text('translit_switch_direction'.tr()),
              ),
            ),
          ],

          // PDF ogohlantirishi
          if (_fileExt == 'pdf') ...[
            const SizedBox(height: 10),
            _InfoBanner(
              icon: Icons.info_outline_rounded,
              color: cs.tertiary,
              text: 'translit_pdf_warn'.tr(),
            ),
          ],

          // Oldindan ko'rish
          if (_previewText.isNotEmpty) ...[
            const SizedBox(height: 14),
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'translit_preview'.tr(),
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        color: cs.primary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      constraints: const BoxConstraints(maxHeight: 140),
                      decoration: BoxDecoration(
                        color: cs.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: cs.outlineVariant),
                      ),
                      padding: const EdgeInsets.all(10),
                      child: SingleChildScrollView(
                        child: Text(
                          _previewText.length > 300
                              ? '${_previewText.substring(0, 300)}…'
                              : _previewText,
                          style: TextStyle(
                            fontSize: 12.5,
                            height: 1.5,
                            color: cs.onSurface,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],

          // Konvertatsiya progressi
          if (_converting) ...[
            const SizedBox(height: 16),
            _ProgressCard(
              curPage: _curPage,
              totPages: _totPages,
              fileExt: _fileExt,
            ),
          ],

          // Muvaffaqiyat banneri
          if (_outPath != null && !_converting) ...[
            const SizedBox(height: 14),
            _SuccessBanner(
              text: 'translit_saved'.tr(
                namedArgs: {'name': _outPath!.split('/').last},
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => OpenFilex.open(_outPath!),
                    icon: const Icon(Icons.open_in_new),
                    label: Text('open_file'.tr()),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: () => Share.shareXFiles([XFile(_outPath!)]),
                    icon: const Icon(Icons.share),
                    label: Text('share'.tr()),
                  ),
                ),
              ],
            ),
          ],

          const SizedBox(height: 16),

          // Konvertatsiya tugmasi
          FilledButton.icon(
            onPressed:
                (_converting || _analyzing || _sourceScript == Script.unknown)
                ? null
                : _convertFile,
            icon: _converting
                ? SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: theme.colorScheme.onPrimary,
                    ),
                  )
                : const Icon(Icons.translate_rounded),
            label: Text(
              _converting
                  ? 'translit_converting'.tr()
                  : _sourceScript == Script.cyrillic
                  ? 'translit_to_latin'.tr()
                  : 'translit_to_cyrillic'.tr(),
            ),
            style: FilledButton.styleFrom(
              minimumSize: const Size(double.infinity, 52),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
        ],

        // Bo'sh holat
        if (_file == null && !_analyzing) ...[
          const SizedBox(height: 48),
          _EmptyFileHint(cs: cs),
        ],
      ],
    );
  }
}

// ── Yordamchi widgetlar ──────────────────────────────────────────────────────

class _FilePickCard extends StatelessWidget {
  final File? file;
  final VoidCallback? onTap;

  const _FilePickCard({required this.file, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final hasFile = file != null;
    final name = hasFile ? file!.path.split('/').last : null;
    final ext = name?.split('.').last.toLowerCase();
    final isPdf = ext == 'pdf';

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: hasFile
                      ? (isPdf
                            ? cs.errorContainer.withValues(alpha: 0.85)
                            : cs.primaryContainer.withValues(alpha: 0.85))
                      : cs.primaryContainer.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  hasFile
                      ? (isPdf
                            ? Icons.picture_as_pdf_rounded
                            : Icons.article_rounded)
                      : Icons.upload_file_rounded,
                  color: hasFile ? (isPdf ? cs.error : cs.primary) : cs.primary,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'translit_pick_file'.tr(),
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        color: cs.onSurface,
                      ),
                    ),
                    Text(
                      name ?? 'translit_file_none'.tr(),
                      style: TextStyle(
                        color: hasFile
                            ? cs.onSurfaceVariant
                            : cs.onSurfaceVariant.withValues(alpha: 0.75),
                        fontSize: 13,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: onTap != null
                    ? cs.onSurfaceVariant
                    : cs.outline.withValues(alpha: 0.55),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProgressCard extends StatelessWidget {
  final int curPage;
  final int totPages;
  final String fileExt;

  const _ProgressCard({
    required this.curPage,
    required this.totPages,
    required this.fileExt,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isPdf = fileExt == 'pdf';
    final progress = (totPages > 0 && isPdf) ? (curPage - 1) / totPages : null;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(value: progress, minHeight: 7),
            ),
            const SizedBox(height: 10),
            Text(
              isPdf && totPages > 0
                  ? 'translit_progress'.tr(
                      namedArgs: {'current': '$curPage', 'total': '$totPages'},
                    )
                  : 'translit_converting'.tr(),
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoBanner extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String text;

  const _InfoBanner({
    required this.icon,
    required this.color,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 12.5,
                color: color.withValues(alpha: 0.85),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SuccessBanner extends StatelessWidget {
  final String text;

  const _SuccessBanner({required this.text});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.primaryContainer.withValues(alpha: isDark ? 0.55 : 1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: cs.primary.withValues(alpha: isDark ? 0.45 : 0.35),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.check_circle_rounded, color: cs.primary, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: cs.onPrimaryContainer,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyFileHint extends StatelessWidget {
  final ColorScheme cs;

  const _EmptyFileHint({required this.cs});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 88,
          height: 88,
          decoration: BoxDecoration(
            color: cs.primaryContainer.withValues(alpha: 0.5),
            shape: BoxShape.circle,
          ),
          child: Icon(
            Icons.translate_rounded,
            size: 44,
            color: cs.primary.withValues(alpha: 0.6),
          ),
        ),
        const SizedBox(height: 18),
        Text(
          'translit_file_empty_hint1'.tr(),
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: cs.onSurface,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'translit_file_empty_hint2'.tr(),
          textAlign: TextAlign.center,
          style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
        ),
      ],
    );
  }
}
