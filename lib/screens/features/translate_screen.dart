import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gal/gal.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:pdfx/pdfx.dart' as pdfx;
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/translate_language.dart';
import '../../providers/subscription_provider.dart';
import '../../services/ai_service.dart';
import '../../services/document_export_service.dart';
import '../../widgets/ai_error.dart';
import '../../widgets/language_picker_sheet.dart';

enum _InputKind { docx, pdf, image }

/// Hujjat tarjimasi: Word / PDF / JPG / PNG fayl → istalgan tilga →
/// natija tanlangan formatda (Word, PDF, JPG yoki PNG).
class TranslateScreen extends StatefulWidget {
  const TranslateScreen({super.key});

  @override
  State<TranslateScreen> createState() => _TranslateScreenState();
}

class _TranslateScreenState extends State<TranslateScreen> {
  static const _kSource = 'translate_source';
  static const _kTarget = 'translate_target';
  static const _inputExtensions = ['docx', 'pdf', 'jpg', 'jpeg', 'png', 'webp'];
  // Server bir so'rovda 4000 belgini 1 birlik hisoblaydi — Word matni shu bo'laklarga bo'linadi
  static const _chunkChars = 3800;

  String _source = TranslateLanguage.auto;
  String _target = 'uz';
  File? _file;
  _InputKind? _kind;
  ExportFormat _format = ExportFormat.docx;
  bool _busy = false;
  int _step = 0;
  int _steps = 0;
  String? _text; // tarjima qilingan matn
  String? _detected;
  List<File> _outputs = [];

  @override
  void initState() {
    super.initState();
    _loadLanguages();
  }

  Future<void> _loadLanguages() async {
    final prefs = await SharedPreferences.getInstance();
    final locale = mounted ? context.locale.languageCode : 'uz';
    final fallbackTarget = locale == 'ru' ? 'ru' : locale == 'en' ? 'en' : 'uz';
    if (!mounted) return;
    setState(() {
      _source = prefs.getString(_kSource) ?? TranslateLanguage.auto;
      _target = prefs.getString(_kTarget) ?? fallbackTarget;
    });
  }

  Future<void> _saveLanguages() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kSource, _source);
    await prefs.setString(_kTarget, _target);
  }

  String _langName(String code) {
    if (code == TranslateLanguage.auto) return 'translate_auto_detect'.tr();
    return TranslateLanguage.byCode(code)?.nativeName ?? code;
  }

  Future<void> _chooseSource() async {
    final code = await pickTranslateLanguage(context, selected: _source, allowAuto: true);
    if (code == null) return;
    setState(() => _source = code);
    _saveLanguages();
  }

  Future<void> _chooseTarget() async {
    final code = await pickTranslateLanguage(context, selected: _target);
    if (code == null) return;
    setState(() => _target = code);
    _saveLanguages();
  }

  void _swap() {
    final newTarget = _source == TranslateLanguage.auto ? (_detected ?? 'en') : _source;
    setState(() {
      _source = _target;
      _target = newTarget;
    });
    _saveLanguages();
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: _inputExtensions,
    );
    final path = result?.files.single.path;
    if (path == null) return;
    final ext = p.extension(path).toLowerCase().replaceFirst('.', '');
    final kind = switch (ext) {
      'docx' => _InputKind.docx,
      'pdf' => _InputKind.pdf,
      _ => _InputKind.image,
    };
    setState(() {
      _file = File(path);
      _kind = kind;
      // Natija formati odatda asl fayl turiga mos keladi — foydalanuvchi o'zgartira oladi
      _format = switch (ext) {
        'docx' => ExportFormat.docx,
        'pdf' => ExportFormat.pdf,
        'png' => ExportFormat.png,
        _ => ExportFormat.jpg,
      };
      _text = null;
      _outputs = [];
    });
  }

  bool get _canTranslate => !_busy && _file != null && _source != _target;

  Future<void> _translate() async {
    final subs = context.read<SubscriptionProvider>();
    setState(() {
      _busy = true;
      _text = null;
      _detected = null;
      _outputs = [];
      _step = 0;
      _steps = 0;
    });
    try {
      final text = switch (_kind!) {
        _InputKind.docx => await _translateDocx(subs),
        _InputKind.pdf => await _translatePdf(subs),
        _InputKind.image => await _translateImage(await _file!.readAsBytes(), subs),
      };
      if (text.trim().isEmpty) {
        _snack('translate_nothing'.tr());
        return;
      }
      final base = '${p.basenameWithoutExtension(_file!.path)}_$_target';
      final outputs = await DocumentExportService.export(
        text,
        format: _format,
        baseName: base,
        langCode: _target,
      );
      if (!mounted) return;
      setState(() {
        _text = text;
        _outputs = outputs;
      });
    } on AiException catch (e) {
      if (mounted) await showAiError(context, e);
    } catch (e) {
      _snack('error_prefix'.tr(namedArgs: {'message': '$e'}));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _ensureQuota(SubscriptionProvider subs, int units) {
    final quota = subs.quota;
    if (quota != null && quota.remaining < units) {
      throw AiException('QUOTA_EXCEEDED', '', quota: quota);
    }
  }

  Future<String> _translateImage(Uint8List bytes, SubscriptionProvider subs) async {
    final r = await AiService.translate(imageBytes: bytes, source: _source, target: _target);
    subs.updateQuota(r.quota);
    _detected ??= r.detected;
    return r.translation;
  }

  /// Word matni xatboshilar chegarasida bo'laklarga bo'linib tarjima qilinadi.
  Future<String> _translateDocx(SubscriptionProvider subs) async {
    final source = DocumentExportService.docxText(await _file!.readAsBytes());
    if (source.isEmpty) return '';
    final chunks = <String>[];
    var current = StringBuffer();
    for (final para in source.split('\n')) {
      if (current.length + para.length + 1 > _chunkChars && current.isNotEmpty) {
        chunks.add(current.toString());
        current = StringBuffer();
      }
      if (current.isNotEmpty) current.write('\n');
      current.write(para);
    }
    if (current.isNotEmpty) chunks.add(current.toString());

    _ensureQuota(subs, chunks.length);
    setState(() => _steps = chunks.length);
    final out = <String>[];
    for (var i = 0; i < chunks.length; i++) {
      if (!mounted) break;
      setState(() => _step = i + 1);
      final r = await AiService.translate(text: chunks[i], source: _source, target: _target);
      subs.updateQuota(r.quota);
      _detected ??= r.detected;
      out.add(r.translation);
    }
    return out.join('\n');
  }

  /// PDF sahifama-sahifa rasmga aylantirilib tarjima qilinadi (har sahifa — 1 birlik).
  Future<String> _translatePdf(SubscriptionProvider subs) async {
    final doc = await pdfx.PdfDocument.openFile(_file!.path);
    final parts = <String>[];
    try {
      final total = doc.pagesCount;
      _ensureQuota(subs, total);
      setState(() => _steps = total);
      for (var i = 1; i <= total; i++) {
        if (!mounted) break;
        setState(() => _step = i);
        final page = await doc.getPage(i);
        final rendered = await page.render(
          width: page.width * 2,
          height: page.height * 2,
          format: pdfx.PdfPageImageFormat.jpeg,
          backgroundColor: '#ffffff',
        );
        await page.close();
        if (rendered == null) continue;
        final t = await _translateImage(rendered.bytes, subs);
        if (t.isNotEmpty) parts.add(t);
      }
    } finally {
      await doc.close();
    }
    return parts.join('\n\n');
  }

  Future<void> _saveToGallery() async {
    try {
      if (!await Gal.hasAccess()) await Gal.requestAccess();
      for (final f in _outputs) {
        await Gal.putImage(f.path, album: 'Scan to PDF');
      }
      _snack('conv_saved_gallery'.tr());
    } on GalException {
      _snack('conv_gallery_error'.tr());
    }
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), behavior: SnackBarBehavior.floating),
    );
  }

  IconData get _fileIcon => switch (_kind) {
        _InputKind.docx => Icons.description_rounded,
        _InputKind.pdf => Icons.picture_as_pdf_rounded,
        _InputKind.image => Icons.image_rounded,
        null => Icons.upload_file_rounded,
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final quota = context.watch<SubscriptionProvider>().quota;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: cs.primary,
        foregroundColor: cs.onPrimary,
        title: Text('feature_translate'.tr()),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          // ── Tillar ──────────────────────────────────────────────────
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                children: [
                  Expanded(child: _LangButton(label: 'translate_from'.tr(), value: _langName(_source), onTap: _busy ? null : _chooseSource)),
                  IconButton.filledTonal(
                    onPressed: _busy ? null : _swap,
                    icon: const Icon(Icons.swap_horiz_rounded),
                    tooltip: 'translate_swap'.tr(),
                  ),
                  Expanded(child: _LangButton(label: 'translate_to'.tr(), value: _langName(_target), onTap: _busy ? null : _chooseTarget)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          // ── Fayl ────────────────────────────────────────────────────
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              leading: CircleAvatar(
                radius: 26,
                backgroundColor: cs.primaryContainer,
                child: Icon(_fileIcon, color: cs.onPrimaryContainer),
              ),
              title: Text(
                _file == null ? 'translate_pick_file'.tr() : p.basename(_file!.path),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: Text(_file == null ? 'translate_pick_file_hint'.tr() : 'translate_change_file'.tr()),
              trailing: const Icon(Icons.chevron_right),
              onTap: _busy ? null : _pickFile,
            ),
          ),
          const SizedBox(height: 16),

          // ── Natija formati ──────────────────────────────────────────
          Text('translate_output_format'.tr(), style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          SegmentedButton<ExportFormat>(
            segments: [
              for (final f in ExportFormat.values) ButtonSegment(value: f, label: Text(f.label)),
            ],
            selected: {_format},
            showSelectedIcon: false,
            onSelectionChanged: _busy ? null : (s) => setState(() => _format = s.first),
          ),
          const SizedBox(height: 16),

          // ── Tarjima tugmasi ─────────────────────────────────────────
          FilledButton.icon(
            onPressed: _canTranslate ? _translate : null,
            icon: _busy
                ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: cs.onPrimary))
                : const Icon(Icons.translate_rounded),
            label: Text(_busy
                ? (_steps > 1
                    ? 'translate_progress_pages'.tr(namedArgs: {'current': '$_step', 'total': '$_steps'})
                    : 'translate_progress'.tr())
                : 'translate_btn'.tr()),
            style: FilledButton.styleFrom(minimumSize: const Size(double.infinity, 52)),
          ),
          if (_source == _target)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('translate_same_language'.tr(), textAlign: TextAlign.center, style: TextStyle(color: cs.error, fontSize: 12.5)),
            )
          else if (quota != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'ai_quota_left'.tr(namedArgs: {'remaining': '${quota.remaining}', 'limit': '${quota.limit}'}),
                textAlign: TextAlign.center,
                style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12.5),
              ),
            ),

          // ── Natija ──────────────────────────────────────────────────
          if (_outputs.isNotEmpty) ...[
            const SizedBox(height: 20),
            Card(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.check_circle_rounded, color: cs.primary),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'translate_done'.tr(namedArgs: {'lang': _langName(_target), 'format': _format.label}),
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                      ],
                    ),
                    if (_source == TranslateLanguage.auto && _detected != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 4, left: 32),
                        child: Text(
                          'translate_detected'.tr(namedArgs: {'lang': _langName(_detected!)}),
                          style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12.5),
                        ),
                      ),
                    const SizedBox(height: 8),
                    for (final f in _outputs)
                      ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(_format.isImage ? Icons.image_outlined : Icons.insert_drive_file_outlined),
                        title: Text(p.basename(f.path)),
                        trailing: const Icon(Icons.open_in_new, size: 20),
                        onTap: () => OpenFilex.open(f.path),
                      ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: _format.isImage
                              ? OutlinedButton.icon(
                                  onPressed: _saveToGallery,
                                  icon: const Icon(Icons.photo_library_outlined),
                                  label: Text('conv_save_gallery'.tr()),
                                )
                              : OutlinedButton.icon(
                                  onPressed: () => OpenFilex.open(_outputs.first.path),
                                  icon: const Icon(Icons.open_in_new),
                                  label: Text('open_file'.tr()),
                                ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: FilledButton.tonalIcon(
                            onPressed: () => Share.shareXFiles(_outputs.map((f) => XFile(f.path)).toList()),
                            icon: const Icon(Icons.share),
                            label: Text('share'.tr()),
                          ),
                        ),
                      ],
                    ),
                    Theme(
                      data: theme.copyWith(dividerColor: Colors.transparent),
                      child: ExpansionTile(
                        tilePadding: EdgeInsets.zero,
                        title: Text('translate_show_text'.tr()),
                        trailing: IconButton(
                          icon: const Icon(Icons.copy_rounded),
                          tooltip: 'ocr_copy'.tr(),
                          onPressed: () async {
                            await Clipboard.setData(ClipboardData(text: _text ?? ''));
                            _snack('translit_copied'.tr());
                          },
                        ),
                        children: [
                          SelectableText(_text ?? '', style: const TextStyle(fontSize: 15, height: 1.6)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _LangButton extends StatelessWidget {
  final String label;
  final String value;
  final VoidCallback? onTap;

  const _LangButton({required this.label, required this.value, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Column(
          children: [
            Text(label, style: TextStyle(fontSize: 11.5, color: cs.onSurfaceVariant)),
            const SizedBox(height: 2),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Flexible(
                  child: Text(
                    value,
                    maxLines: 2,
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontWeight: FontWeight.w700, color: cs.primary, fontSize: 14.5, height: 1.25),
                  ),
                ),
                Icon(Icons.arrow_drop_down, color: cs.primary),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
