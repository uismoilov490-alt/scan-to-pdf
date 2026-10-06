import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:gal/gal.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';

import '../../services/image_convert_service.dart';
import '../../services/pdf_service.dart';
import '../../widgets/pdf_source_sheet.dart';

/// Natija formati. Kirish turiga qarab mavjudlari: rasm → PDF/JPG/PNG,
/// PDF → JPG/PNG/uzun rasm.
enum ConvertTarget { pdf, jpg, png, long }

extension on ConvertTarget {
  String get label => switch (this) {
    ConvertTarget.pdf => 'PDF',
    ConvertTarget.jpg => 'JPG',
    ConvertTarget.png => 'PNG',
    ConvertTarget.long => 'conv_out_long'.tr(),
  };

  String get hintKey => 'conv_target_${name}_hint';
}

const _imageExtensions = ['jpg', 'jpeg', 'png', 'webp'];
const _imageTargets = [ConvertTarget.pdf, ConvertTarget.jpg, ConvertTarget.png];
const _pdfTargets = [ConvertTarget.jpg, ConvertTarget.png, ConvertTarget.long];

/// Rasm konvertori: istalgan rasm (JPG/PNG/WebP) yoki PDF → tanlangan format.
class ImageConvertScreen extends StatefulWidget {
  const ImageConvertScreen({super.key});

  @override
  State<ImageConvertScreen> createState() => _ImageConvertScreenState();
}

class _ImageConvertScreenState extends State<ImageConvertScreen> {
  List<File> _inputs = [];
  bool _pdfInput = false;
  ConvertTarget _target = ConvertTarget.pdf;
  List<File> _results = [];
  File? _pdfResult;
  bool _converting = false;
  int _done = 0;
  int _total = 0;

  List<ConvertTarget> get _targets => _pdfInput ? _pdfTargets : _imageTargets;

  Future<void> _pick() async {
    final pdf = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: Text('conv_src_images'.tr()),
              subtitle: Text('conv_src_images_hint'.tr()),
              onTap: () => Navigator.pop(ctx, false),
            ),
            ListTile(
              leading: const Icon(Icons.picture_as_pdf_outlined),
              title: Text('conv_src_pdf'.tr()),
              subtitle: Text('conv_src_pdf_hint'.tr()),
              onTap: () => Navigator.pop(ctx, true),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (pdf == null || !mounted) return;

    List<File> picked;
    if (pdf) {
      final saved = await PdfService.listSavedPdfs();
      if (!mounted) return;
      final file = await pickPdf(context, saved);
      picked = file == null ? [] : [file];
    } else {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: _imageExtensions,
        allowMultiple: true,
      );
      picked = [
        for (final f in result?.files ?? <PlatformFile>[])
          if (f.path != null) File(f.path!),
      ];
    }
    if (picked.isEmpty || !mounted) return;
    setState(() {
      _inputs = picked;
      _pdfInput = pdf;
      if (!_targets.contains(_target)) _target = _targets.first;
      _results = [];
      _pdfResult = null;
    });
  }

  Future<void> _convert() async {
    if (_inputs.isEmpty) return;
    setState(() {
      _converting = true;
      _done = 0;
      _total = _pdfInput ? 0 : _inputs.length;
      _results = [];
      _pdfResult = null;
    });

    void progress(int done, int total) {
      if (mounted) {
        setState(() {
          _done = done;
          _total = total;
        });
      }
    }

    try {
      final input = _inputs.first;
      switch ((_pdfInput, _target)) {
        case (false, ConvertTarget.pdf):
          final name = _inputs.length == 1
              ? p.basenameWithoutExtension(input.path)
              : 'Rasmlar_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}';
          _pdfResult = await PdfService.generatePdf(
            imageFiles: _inputs,
            fileName: name,
            enhance: false,
          );
        case (false, _):
          _results = await ImageConvertService.convertImages(
            _inputs,
            to: _target == ConvertTarget.png ? ImageFormat.png : ImageFormat.jpg,
            onProgress: progress,
          );
        case (true, ConvertTarget.long):
          _results = await ImageConvertService.pdfToLongImage(
            input,
            onProgress: progress,
          );
        case (true, _):
          _results = await ImageConvertService.pdfToImages(
            input,
            format: _target == ConvertTarget.png
                ? ImageFormat.png
                : ImageFormat.jpg,
            onProgress: progress,
          );
      }
      if (!mounted) return;
      if (_results.isEmpty && _pdfResult == null) _snack('conv_failed'.tr());
    } catch (e) {
      if (mounted) _snack('error_prefix'.tr(namedArgs: {'message': '$e'}));
    } finally {
      if (mounted) setState(() => _converting = false);
    }
  }

  Future<void> _saveToGallery() async {
    try {
      if (!await Gal.hasAccess()) await Gal.requestAccess();
      for (final f in _results) {
        await Gal.putImage(f.path, album: 'Scan to PDF');
      }
      _snack('conv_saved_gallery'.tr());
    } on GalException {
      _snack('conv_gallery_error'.tr());
    }
  }

  Future<void> _shareAll() async {
    final files = _pdfResult != null ? [_pdfResult!] : _results;
    await Share.shareXFiles(files.map((f) => XFile(f.path)).toList());
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), behavior: SnackBarBehavior.floating),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final hasResult = _results.isNotEmpty || _pdfResult != null;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(title: Text('feature_image_convert'.tr())),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 10,
              ),
              leading: CircleAvatar(
                radius: 26,
                backgroundColor: cs.primaryContainer,
                child: Icon(
                  _pdfInput
                      ? Icons.picture_as_pdf
                      : Icons.add_photo_alternate_outlined,
                  color: cs.onPrimaryContainer,
                ),
              ),
              title: Text(
                'conv_pick_files'.tr(),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: Text(
                _inputs.isEmpty
                    ? 'conv_pick_hint'.tr()
                    : _inputs.length == 1
                    ? p.basename(_inputs.first.path)
                    : 'conv_selected'.tr(
                        namedArgs: {'count': '${_inputs.length}'},
                      ),
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: _converting ? null : _pick,
            ),
          ),
          if (_inputs.isNotEmpty && !_pdfInput) ...[
            const SizedBox(height: 12),
            SizedBox(
              height: 84,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _inputs.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (_, i) => ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.file(
                    _inputs[i],
                    width: 84,
                    height: 84,
                    fit: BoxFit.cover,
                    cacheWidth: 200,
                    errorBuilder: (_, _, _) => Container(
                      width: 84,
                      color: cs.surfaceContainerHigh,
                      child: const Icon(Icons.broken_image_outlined),
                    ),
                  ),
                ),
              ),
            ),
          ],
          if (_inputs.isNotEmpty) ...[
            const SizedBox(height: 20),
            Text(
              'conv_output'.tr(),
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            SegmentedButton<ConvertTarget>(
              segments: [
                for (final t in _targets)
                  ButtonSegment(value: t, label: Text(t.label)),
              ],
              selected: {_target},
              showSelectedIcon: false,
              onSelectionChanged: _converting
                  ? null
                  : (s) => setState(() {
                      _target = s.first;
                      _results = [];
                      _pdfResult = null;
                    }),
            ),
            const SizedBox(height: 6),
            Text(
              _target.hintKey.tr(),
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: (_inputs.isEmpty || _converting) ? null : _convert,
            icon: _converting
                ? SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: cs.onPrimary,
                    ),
                  )
                : const Icon(Icons.autorenew_rounded),
            label: Text(
              _converting
                  ? (_total > 0
                        ? 'conv_converting'.tr(
                            namedArgs: {'done': '$_done', 'total': '$_total'},
                          )
                        : 'conv_converting_simple'.tr())
                  : 'conv_convert'.tr(),
            ),
            style: FilledButton.styleFrom(
              minimumSize: const Size(double.infinity, 52),
            ),
          ),
          if (hasResult) ...[
            const SizedBox(height: 20),
            Row(
              children: [
                Icon(Icons.check_circle_rounded, color: cs.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _pdfResult != null
                        ? 'conv_pdf_ready'.tr(
                            namedArgs: {'name': p.basename(_pdfResult!.path)},
                          )
                        : 'conv_done'.tr(
                            namedArgs: {'count': '${_results.length}'},
                          ),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (_results.isNotEmpty)
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  // Hujjat sahifasi nisbati (A4) — sahifa tepasidan ko'rinadi
                  childAspectRatio: 0.75,
                ),
                itemCount: _results.length,
                itemBuilder: (_, i) => InkWell(
                  onTap: () => OpenFilex.open(_results[i].path),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image.file(
                      _results[i],
                      fit: BoxFit.cover,
                      alignment: Alignment.topCenter,
                      cacheWidth: 300,
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _results.isNotEmpty
                      ? OutlinedButton.icon(
                          onPressed: _saveToGallery,
                          icon: const Icon(Icons.photo_library_outlined),
                          label: Text('conv_save_gallery'.tr()),
                        )
                      : OutlinedButton.icon(
                          onPressed: () => OpenFilex.open(_pdfResult!.path),
                          icon: const Icon(Icons.open_in_new),
                          label: Text('open_file'.tr()),
                        ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: _shareAll,
                    icon: const Icon(Icons.share),
                    label: Text('share'.tr()),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
