import 'dart:io';
import 'dart:typed_data';

import 'package:easy_localization/easy_localization.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:gal/gal.dart';
import 'package:image_picker/image_picker.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdfx/pdfx.dart' as pdfx;
import 'package:share_plus/share_plus.dart';

import '../../services/document_cleaner.dart';
import '../../services/pdf_service.dart';
import '../../widgets/pdf_source_sheet.dart';

/// Mavjud PDF, rasm yoki kamera surati — qiyshiqni to'g'rilash, fonni kesish,
/// soya/dog'ni tozalash va skaner sifatiga keltirish (telefonning o'zida).
class DocumentCleanScreen extends StatefulWidget {
  const DocumentCleanScreen({super.key});

  @override
  State<DocumentCleanScreen> createState() => _DocumentCleanScreenState();
}

class _DocumentCleanScreenState extends State<DocumentCleanScreen> {
  final List<Uint8List> _originals = [];
  final Map<int, Uint8List> _previewCache = {}; // tanlangan sahifaning tozalangan ko'rinishi
  String _baseName = 'Hujjat';
  CleanMode _mode = CleanMode.color;
  bool _crop = true;
  int _selected = 0;
  bool _showOriginal = false;
  bool _loading = false;
  bool _previewing = false;
  bool _saving = false;
  int _done = 0;
  File? _savedPdf;

  // ── Kirish ─────────────────────────────────────────────────────────────

  Future<void> _pickSource() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.image_outlined),
              title: Text('clean_src_images'.tr()),
              subtitle: Text('clean_src_images_hint'.tr()),
              onTap: () => Navigator.pop(ctx, 'images'),
            ),
            ListTile(
              leading: const Icon(Icons.picture_as_pdf_outlined),
              title: Text('clean_src_pdf'.tr()),
              onTap: () => Navigator.pop(ctx, 'pdf'),
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined),
              title: Text('edit_add_camera'.tr()),
              onTap: () => Navigator.pop(ctx, 'camera'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (choice == null || !mounted) return;

    setState(() => _loading = true);
    try {
      final pages = <Uint8List>[];
      switch (choice) {
        case 'images':
          final r = await FilePicker.platform.pickFiles(
            type: FileType.custom,
            allowedExtensions: const ['jpg', 'jpeg', 'png', 'webp'],
            allowMultiple: true,
          );
          for (final f in r?.files ?? <PlatformFile>[]) {
            if (f.path != null) pages.add(await File(f.path!).readAsBytes());
          }
          if (pages.isNotEmpty) _baseName = p.basenameWithoutExtension(r!.files.first.path!);
        case 'pdf':
          final saved = await PdfService.listSavedPdfs();
          if (!mounted) return;
          final pdf = await pickPdf(context, saved);
          if (pdf != null) {
            pages.addAll(await _renderPdf(pdf));
            _baseName = p.basenameWithoutExtension(pdf.path);
          }
        case 'camera':
          final shot = await ImagePicker().pickImage(source: ImageSource.camera, imageQuality: 95);
          if (shot != null) {
            pages.add(await File(shot.path).readAsBytes());
            _baseName = 'Hujjat';
          }
      }
      if (pages.isEmpty || !mounted) return;
      setState(() {
        _originals
          ..clear()
          ..addAll(pages);
        _previewCache.clear();
        _selected = 0;
        _savedPdf = null;
      });
      _refreshPreview();
    } catch (e) {
      _snack('error_prefix'.tr(namedArgs: {'message': '$e'}));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<List<Uint8List>> _renderPdf(File pdf) async {
    final doc = await pdfx.PdfDocument.openFile(pdf.path);
    final pages = <Uint8List>[];
    try {
      for (var i = 1; i <= doc.pagesCount; i++) {
        final page = await doc.getPage(i);
        final img = await page.render(
          width: page.width * 2,
          height: page.height * 2,
          format: pdfx.PdfPageImageFormat.jpeg,
          backgroundColor: '#ffffff',
          quality: 95,
        );
        await page.close();
        if (img != null) pages.add(img.bytes);
      }
    } finally {
      await doc.close();
    }
    return pages;
  }

  // ── Ko'rinish ──────────────────────────────────────────────────────────

  /// Tanlangan sahifaning tozalangan ko'rinishini (joriy rejim bilan) tayyorlaydi.
  Future<void> _refreshPreview() async {
    if (_originals.isEmpty) return;
    final index = _selected;
    setState(() => _previewing = true);
    final out = await DocumentCleaner.clean(_originals[index], mode: _mode, crop: _crop);
    if (!mounted) return;
    setState(() {
      if (out != null) _previewCache[index] = out;
      _previewing = false;
    });
  }

  void _setOptions({CleanMode? mode, bool? crop}) {
    setState(() {
      if (mode != null) _mode = mode;
      if (crop != null) _crop = crop;
      _previewCache.clear();
      _savedPdf = null;
    });
    _refreshPreview();
  }

  // ── Saqlash ────────────────────────────────────────────────────────────

  Future<List<File>> _cleanAll() async {
    final tmp = await getTemporaryDirectory();
    final files = <File>[];
    for (var i = 0; i < _originals.length; i++) {
      if (!mounted) break;
      setState(() => _done = i + 1);
      final out = _previewCache[i] ?? await DocumentCleaner.clean(_originals[i], mode: _mode, crop: _crop);
      final f = File('${tmp.path}/clean_${DateTime.now().microsecondsSinceEpoch}_$i.jpg');
      await f.writeAsBytes(out ?? _originals[i]);
      files.add(f);
    }
    return files;
  }

  Future<void> _savePdf() async {
    setState(() {
      _saving = true;
      _done = 0;
    });
    try {
      final files = await _cleanAll();
      final pdf = await PdfService.generatePdf(
        imageFiles: files,
        fileName: '${_baseName}_tozalangan',
        enhance: false,
      );
      if (!mounted) return;
      setState(() => _savedPdf = pdf);
      _snack('saved_as'.tr(namedArgs: {'name': p.basename(pdf.path)}));
    } catch (e) {
      _snack('error_prefix'.tr(namedArgs: {'message': '$e'}));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _saveToGallery() async {
    setState(() {
      _saving = true;
      _done = 0;
    });
    try {
      final files = await _cleanAll();
      if (!await Gal.hasAccess()) await Gal.requestAccess();
      for (final f in files) {
        await Gal.putImage(f.path, album: 'Scan to PDF');
      }
      _snack('conv_saved_gallery'.tr());
    } on GalException {
      _snack('conv_gallery_error'.tr());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), behavior: SnackBarBehavior.floating),
    );
  }

  // ── UI ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final busy = _loading || _saving;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: cs.primary,
        foregroundColor: cs.onPrimary,
        title: Text('feature_clean'.tr()),
        actions: [
          if (_originals.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.folder_open),
              tooltip: 'clean_pick'.tr(),
              onPressed: busy ? null : _pickSource,
            ),
        ],
      ),
      body: _originals.isEmpty ? _buildEmpty(cs) : _buildEditor(theme, cs, busy),
    );
  }

  Widget _buildEmpty(ColorScheme cs) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.auto_fix_high_rounded, size: 84, color: cs.primary.withValues(alpha: 0.4)),
            const SizedBox(height: 16),
            Text('clean_empty_title'.tr(),
                textAlign: TextAlign.center, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text('clean_empty_hint'.tr(), textAlign: TextAlign.center, style: TextStyle(color: cs.onSurfaceVariant)),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _loading ? null : _pickSource,
              icon: _loading
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.add_photo_alternate_outlined),
              label: Text('clean_pick'.tr()),
              style: FilledButton.styleFrom(minimumSize: const Size(220, 52)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEditor(ThemeData theme, ColorScheme cs, bool busy) {
    final cleaned = _previewCache[_selected];
    final shown = _showOriginal || cleaned == null ? _originals[_selected] : cleaned;

    return Column(
      children: [
        // Oldin / keyin
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Stack(
              children: [
                Positioned.fill(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: ColoredBox(
                      color: cs.surfaceContainerHighest,
                      child: InteractiveViewer(
                        maxScale: 5,
                        child: Image.memory(shown, fit: BoxFit.contain, gaplessPlayback: true),
                      ),
                    ),
                  ),
                ),
                if (_previewing)
                  const Positioned.fill(child: Center(child: CircularProgressIndicator())),
                Positioned(
                  top: 10,
                  left: 10,
                  child: SegmentedButton<bool>(
                    style: SegmentedButton.styleFrom(
                      backgroundColor: cs.surface.withValues(alpha: 0.9),
                      visualDensity: VisualDensity.compact,
                    ),
                    segments: [
                      ButtonSegment(value: true, label: Text('clean_before'.tr())),
                      ButtonSegment(value: false, label: Text('clean_after'.tr())),
                    ],
                    selected: {_showOriginal},
                    showSelectedIcon: false,
                    onSelectionChanged: (s) => setState(() => _showOriginal = s.first),
                  ),
                ),
              ],
            ),
          ),
        ),

        // Sahifalar
        if (_originals.length > 1)
          SizedBox(
            height: 74,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              scrollDirection: Axis.horizontal,
              itemCount: _originals.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (_, i) => GestureDetector(
                onTap: () {
                  setState(() => _selected = i);
                  if (!_previewCache.containsKey(i)) _refreshPreview();
                },
                child: Container(
                  width: 54,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: i == _selected ? cs.primary : cs.outlineVariant, width: i == _selected ? 3 : 1),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Image.memory(_originals[i], fit: BoxFit.cover, cacheWidth: 120),
                ),
              ),
            ),
          ),

        // Sozlamalar va saqlash
        Container(
          color: cs.surfaceContainerLow,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: SafeArea(
            top: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SegmentedButton<CleanMode>(
                  segments: [
                    ButtonSegment(value: CleanMode.color, label: Text('clean_mode_color'.tr())),
                    ButtonSegment(value: CleanMode.gray, label: Text('clean_mode_gray'.tr())),
                    ButtonSegment(value: CleanMode.bw, label: Text('clean_mode_bw'.tr())),
                  ],
                  selected: {_mode},
                  showSelectedIcon: false,
                  onSelectionChanged: busy || _previewing ? null : (s) => _setOptions(mode: s.first),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: Text('clean_crop'.tr()),
                  subtitle: Text('clean_crop_hint'.tr()),
                  value: _crop,
                  onChanged: busy || _previewing ? null : (v) => _setOptions(crop: v),
                ),
                if (_savedPdf != null) ...[
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => OpenFilex.open(_savedPdf!.path),
                          icon: const Icon(Icons.open_in_new),
                          label: Text('open_file'.tr()),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: FilledButton.tonalIcon(
                          onPressed: () => Share.shareXFiles([XFile(_savedPdf!.path)]),
                          icon: const Icon(Icons.share),
                          label: Text('share'.tr()),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                ],
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: busy ? null : _saveToGallery,
                        icon: const Icon(Icons.photo_library_outlined),
                        label: Text('conv_save_gallery'.tr()),
                        style: OutlinedButton.styleFrom(minimumSize: const Size(0, 50)),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: busy ? null : _savePdf,
                        icon: _saving
                            ? SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: cs.onPrimary))
                            : const Icon(Icons.picture_as_pdf_rounded),
                        label: Text(_saving
                            ? '$_done / ${_originals.length}'
                            : 'clean_save_pdf'.tr()),
                        style: FilledButton.styleFrom(minimumSize: const Size(0, 50)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
