import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pdfx/pdfx.dart' as pdfx;
import 'package:printing/printing.dart';

import '../../services/transliteration_service.dart';

// ── Matn tab yo'nalishi ──────────────────────────────────────────────────────
enum _TxtDir { cyrToLat, latToCyr }

class CyrillicLatinScreen extends StatefulWidget {
  const CyrillicLatinScreen({super.key});

  @override
  State<CyrillicLatinScreen> createState() => _CyrillicLatinScreenState();
}

class _CyrillicLatinScreenState extends State<CyrillicLatinScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  // ── Matn tab holati ──────────────────────────────────────────────────────
  final _srcCtrl = TextEditingController();
  final _dstCtrl = TextEditingController();
  _TxtDir _txtDir = _TxtDir.cyrToLat;

  // ── Fayl tab holati ──────────────────────────────────────────────────────
  File? _file;
  String _fileExt = ''; // 'pdf' | 'docx'
  Script _sourceScript = Script.unknown;
  bool _analyzing = false;
  bool _converting = false;
  String _previewText = '';
  String? _outPath;
  int _curPage = 0;
  int _totPages = 0;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _srcCtrl.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    _tabs.dispose();
    _srcCtrl.removeListener(_onTextChanged);
    _srcCtrl.dispose();
    _dstCtrl.dispose();
    super.dispose();
  }

  // ── Matn tab metodlari ───────────────────────────────────────────────────

  void _onTextChanged() {
    final src = _srcCtrl.text;
    final out = _txtDir == _TxtDir.cyrToLat
        ? TransliterationService.toLatin(src)
        : TransliterationService.toCyrillic(src);
    _dstCtrl.text = out;
    setState(() {});
  }

  void _swapTxtDir() {
    final tmp = _srcCtrl.text;
    setState(() {
      _txtDir = _txtDir == _TxtDir.cyrToLat ? _TxtDir.latToCyr : _TxtDir.cyrToLat;
      _srcCtrl.text = _dstCtrl.text;
    });
    _dstCtrl.text = tmp;
    _onTextChanged();
  }

  Future<void> _copyResult() async {
    if (_dstCtrl.text.trim().isEmpty) return;
    await Clipboard.setData(ClipboardData(text: _dstCtrl.text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('translit_copied'.tr()),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _clearText() {
    _srcCtrl.clear();
    _dstCtrl.clear();
    setState(() {});
  }

  // ── Fayl tab metodlari ───────────────────────────────────────────────────

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.any);
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
      _sourceScript = Script.unknown;
      _previewText = '';
      _outPath = null;
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
          _sourceScript = detected == Script.unknown ? Script.cyrillic : detected;
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
    final tempDir = await getTemporaryDirectory();
    final document = await pdfx.PdfDocument.openData(await _file!.readAsBytes());
    try {
      if (document.pagesCount == 0) return '';
      final page = await document.getPage(1);
      final rendered = await page.render(
        width: page.width * 2,
        height: page.height * 2,
        format: pdfx.PdfPageImageFormat.jpeg,
        backgroundColor: '#ffffff',
      );
      await page.close();
      if (rendered == null) return '';

      final imgFile = File(
        '${tempDir.path}/tl_preview_${DateTime.now().millisecondsSinceEpoch}.jpg',
      );
      await imgFile.writeAsBytes(rendered.bytes);

      final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
      try {
        final result = await recognizer.processImage(
          InputImage.fromFile(imgFile),
        );
        return result.text;
      } finally {
        await recognizer.close();
        try { await imgFile.delete(); } catch (_) {}
      }
    } finally {
      await document.close();
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
              'translit_saved'.tr(namedArgs: {'name': outFile.path.split('/').last}),
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _converting = false);
        _showError('error_prefix'.tr(namedArgs: {'message': '$e'}));
      }
    }
  }

  Future<File> _convertDocx() async {
    final bytes = await _file!.readAsBytes();
    final converted = TransliterationService.convertDocxBytes(bytes, _sourceScript);
    return _saveOutput(converted, _outSuffix('docx'));
  }

  Future<File> _convertPdf() async {
    final tempDir = await getTemporaryDirectory();
    final document = await pdfx.PdfDocument.openData(await _file!.readAsBytes());
    final pageCount = document.pagesCount;

    if (mounted) setState(() => _totPages = pageCount);

    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    final paragraphs = <String>[];

    try {
      for (int i = 1; i <= pageCount; i++) {
        if (!mounted) break;
        setState(() => _curPage = i);

        final page = await document.getPage(i);
        final rendered = await page.render(
          width: page.width * 2,
          height: page.height * 2,
          format: pdfx.PdfPageImageFormat.jpeg,
          backgroundColor: '#ffffff',
        );
        await page.close();

        if (rendered == null) continue;

        final imgFile = File(
          '${tempDir.path}/tl_p${i}_${DateTime.now().millisecondsSinceEpoch}.jpg',
        );
        await imgFile.writeAsBytes(rendered.bytes);

        try {
          final result = await recognizer.processImage(
            InputImage.fromFile(imgFile),
          );
          if (result.text.isNotEmpty) {
            final converted = _sourceScript == Script.cyrillic
                ? TransliterationService.toLatin(result.text)
                : TransliterationService.toCyrillic(result.text);
            paragraphs.add(converted);
          }
        } finally {
          try { await imgFile.delete(); } catch (_) {}
        }
      }
    } finally {
      await recognizer.close();
      await document.close();
    }

    return _buildAndSavePdf(paragraphs);
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
                .expand((block) => block
                    .split('\n')
                    .where((l) => l.trim().isNotEmpty)
                    .map(
                      (line) => pw.Padding(
                        padding: const pw.EdgeInsets.only(bottom: 5),
                        child: pw.Text(
                          line,
                          style: pw.TextStyle(font: fontRegular, fontSize: 11),
                        ),
                      ),
                    ))
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
    return outFile;
  }

  String _outSuffix(String ext) {
    final base = _file!.path.split('/').last.replaceAll(RegExp(r'\.[^.]+$'), '');
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

    final hasText = _srcCtrl.text.isNotEmpty || _dstCtrl.text.isNotEmpty;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: cs.primary,
        foregroundColor: cs.onPrimary,
        title: Text('translit_title'.tr()),
        actions: [
          // Matn tabida tozalash tugmasi
          ListenableBuilder(
            listenable: _tabs,
            builder: (_, child) => _tabs.index == 0
                ? IconButton(
                    tooltip: 'translit_clear'.tr(),
                    onPressed: hasText ? _clearText : null,
                    icon: const Icon(Icons.delete_sweep_rounded),
                  )
                : const SizedBox.shrink(),
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          labelColor: cs.onPrimary,
          unselectedLabelColor: cs.onPrimary.withValues(alpha: 0.72),
          indicatorColor: cs.onPrimary,
          indicatorWeight: 3,
          tabs: [
            Tab(text: 'translit_tab_text'.tr()),
            Tab(text: 'translit_tab_file'.tr()),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          _buildTextTab(cs),
          _buildFileTab(theme, cs),
        ],
      ),
    );
  }

  // ── Matn tab ─────────────────────────────────────────────────────────────

  Widget _buildTextTab(ColorScheme cs) {
    final srcLabel = _txtDir == _TxtDir.cyrToLat
        ? 'translit_source_cyr'.tr()
        : 'translit_source_lat'.tr();
    final dstLabel = _txtDir == _TxtDir.cyrToLat
        ? 'translit_result_lat'.tr()
        : 'translit_result_cyr'.tr();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        // Yo'nalish tanlash kartasi
        Card(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          elevation: 0,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: _dirChip(
                    cs: cs,
                    selected: _txtDir == _TxtDir.cyrToLat,
                    icon: Icons.language_rounded,
                    label: 'translit_mode_cyr_lat'.tr(),
                    onTap: () {
                      setState(() => _txtDir = _TxtDir.cyrToLat);
                      _onTextChanged();
                    },
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filledTonal(
                  tooltip: 'translit_swap'.tr(),
                  onPressed: _swapTxtDir,
                  icon: const Icon(Icons.swap_horiz_rounded),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _dirChip(
                    cs: cs,
                    selected: _txtDir == _TxtDir.latToCyr,
                    icon: Icons.g_translate_rounded,
                    label: 'translit_mode_lat_cyr'.tr(),
                    onTap: () {
                      setState(() => _txtDir = _TxtDir.latToCyr);
                      _onTextChanged();
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        _textCard(
          cs: cs,
          title: srcLabel,
          controller: _srcCtrl,
          readOnly: false,
        ),
        const SizedBox(height: 12),
        _textCard(
          cs: cs,
          title: dstLabel,
          controller: _dstCtrl,
          readOnly: true,
        ),
        const SizedBox(height: 14),
        FilledButton.icon(
          onPressed: _dstCtrl.text.trim().isEmpty ? null : _copyResult,
          icon: const Icon(Icons.copy_rounded),
          label: Text('translit_copy_result'.tr()),
          style: FilledButton.styleFrom(
            minimumSize: const Size(double.infinity, 52),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
        ),
      ],
    );
  }

  Widget _dirChip({
    required ColorScheme cs,
    required bool selected,
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? cs.primaryContainer : cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? cs.primary : cs.outlineVariant,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 17, color: selected ? cs.primary : cs.onSurfaceVariant),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 12.5,
                  color: selected ? cs.primary : cs.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _textCard({
    required ColorScheme cs,
    required String title,
    required TextEditingController controller,
    required bool readOnly,
  }) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 13,
                color: cs.primary,
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: controller,
              readOnly: readOnly,
              minLines: 6,
              maxLines: null,
              decoration: InputDecoration(
                hintText: readOnly
                    ? 'translit_result_hint'.tr()
                    : 'translit_input_hint'.tr(),
                filled: true,
                fillColor: readOnly
                    ? cs.surfaceContainerHighest.withValues(alpha: 0.45)
                    : cs.surfaceContainerHighest.withValues(alpha: 0.25),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: cs.outlineVariant),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: cs.outlineVariant),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Fayl tab ─────────────────────────────────────────────────────────────

  Widget _buildFileTab(ThemeData theme, ColorScheme cs) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
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
          _ScriptCard(
            cs: cs,
            sourceScript: _sourceScript,
            onChanged: (s) => setState(() {
              _sourceScript = s;
              _outPath = null;
            }),
          ),

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
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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
          ],

          const SizedBox(height: 16),

          // Konvertatsiya tugmasi
          FilledButton.icon(
            onPressed: (_converting || _analyzing || _sourceScript == Script.unknown)
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
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
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
                  color: hasFile
                      ? (isPdf ? cs.error : cs.primary)
                      : cs.primary,
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

class _ScriptCard extends StatelessWidget {
  final ColorScheme cs;
  final Script sourceScript;
  final ValueChanged<Script> onChanged;

  const _ScriptCard({
    required this.cs,
    required this.sourceScript,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.find_in_page_rounded, size: 18, color: cs.primary),
                const SizedBox(width: 8),
                Text(
                  'translit_detected_label'.tr(),
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: cs.primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _ScriptChip(
                    cs: cs,
                    selected: sourceScript == Script.cyrillic,
                    label: 'translit_script_cyr'.tr(),
                    sublabel: 'translit_script_cyr_arrow'.tr(),
                    onTap: () => onChanged(Script.cyrillic),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _ScriptChip(
                    cs: cs,
                    selected: sourceScript == Script.latin,
                    label: 'translit_script_lat'.tr(),
                    sublabel: 'translit_script_lat_arrow'.tr(),
                    onTap: () => onChanged(Script.latin),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ScriptChip extends StatelessWidget {
  final ColorScheme cs;
  final bool selected;
  final String label;
  final String sublabel;
  final VoidCallback onTap;

  const _ScriptChip({
    required this.cs,
    required this.selected,
    required this.label,
    required this.sublabel,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? cs.primaryContainer : cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? cs.primary : cs.outlineVariant,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 13,
                color: selected ? cs.primary : cs.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              sublabel,
              style: TextStyle(
                fontSize: 11,
                color: selected
                    ? cs.primary.withValues(alpha: 0.7)
                    : cs.onSurfaceVariant.withValues(alpha: 0.7),
              ),
            ),
          ],
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
    final progress = (totPages > 0 && isPdf)
        ? (curPage - 1) / totPages
        : null;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 7,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              isPdf && totPages > 0
                  ? 'translit_progress'.tr(namedArgs: {
                      'current': '$curPage',
                      'total': '$totPages',
                    })
                  : 'translit_converting'.tr(),
              style: TextStyle(
                color: cs.onSurfaceVariant,
                fontSize: 13,
              ),
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
              style: TextStyle(fontSize: 12.5, color: color.withValues(alpha: 0.85)),
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
          style: TextStyle(
            color: cs.onSurfaceVariant,
            fontSize: 13,
          ),
        ),
      ],
    );
  }
}
