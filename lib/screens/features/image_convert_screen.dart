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

enum ConvertMode { jpgToPdf, pdfToJpg, webpToJpg, pngToJpg, jpgToPng }

extension ConvertModeInfo on ConvertMode {
  String get titleKey => switch (this) {
    ConvertMode.jpgToPdf => 'feature_jpg_to_pdf',
    ConvertMode.pdfToJpg => 'feature_pdf_to_jpg',
    ConvertMode.webpToJpg => 'feature_webp_to_jpg',
    ConvertMode.pngToJpg => 'feature_png_to_jpg',
    ConvertMode.jpgToPng => 'feature_jpg_to_png',
  };

  /// Fayl tanlashda ruxsat etilgan kengaytmalar (PDF rejimida ishlatilmaydi).
  List<String> get inputExtensions => switch (this) {
    ConvertMode.jpgToPdf => const ['jpg', 'jpeg', 'png', 'webp'],
    ConvertMode.pdfToJpg => const ['pdf'],
    ConvertMode.webpToJpg => const ['webp'],
    ConvertMode.pngToJpg => const ['png'],
    ConvertMode.jpgToPng => const ['jpg', 'jpeg'],
  };

  bool get producesImages => this != ConvertMode.jpgToPdf;
}

class ImageConvertScreen extends StatefulWidget {
  final ConvertMode mode;

  const ImageConvertScreen({super.key, required this.mode});

  @override
  State<ImageConvertScreen> createState() => _ImageConvertScreenState();
}

class _ImageConvertScreenState extends State<ImageConvertScreen> {
  List<File> _inputs = [];
  List<File> _results = [];
  File? _pdfResult;
  bool _converting = false;
  int _done = 0;
  int _total = 0;

  ConvertMode get _mode => widget.mode;

  Future<void> _pick() async {
    List<File> picked;
    if (_mode == ConvertMode.pdfToJpg) {
      final saved = await PdfService.listSavedPdfs();
      if (!mounted) return;
      final pdf = await pickPdf(context, saved);
      picked = pdf == null ? [] : [pdf];
    } else {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: _mode.inputExtensions,
        allowMultiple: true,
      );
      picked = (result?.files ?? [])
          .where((f) => f.path != null)
          .map((f) => File(f.path!))
          .toList();
    }
    if (picked.isEmpty || !mounted) return;
    setState(() {
      _inputs = picked;
      _results = [];
      _pdfResult = null;
    });
  }

  Future<void> _convert() async {
    if (_inputs.isEmpty) return;
    setState(() {
      _converting = true;
      _done = 0;
      _total = _mode == ConvertMode.pdfToJpg ? 0 : _inputs.length;
      _results = [];
      _pdfResult = null;
    });

    void progress(int done, int total) {
      if (mounted)
        setState(() {
          _done = done;
          _total = total;
        });
    }

    try {
      switch (_mode) {
        case ConvertMode.jpgToPdf:
          final name = _inputs.length == 1
              ? p.basenameWithoutExtension(_inputs.first.path)
              : 'Rasmlar_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}';
          _pdfResult = await PdfService.generatePdf(
            imageFiles: _inputs,
            fileName: name,
            enhance: false,
          );
        case ConvertMode.pdfToJpg:
          _results = await ImageConvertService.pdfToJpg(
            _inputs.first,
            onProgress: progress,
          );
        case ConvertMode.webpToJpg:
        case ConvertMode.pngToJpg:
          _results = await ImageConvertService.convertImages(
            _inputs,
            to: ImageFormat.jpg,
            onProgress: progress,
          );
        case ConvertMode.jpgToPng:
          _results = await ImageConvertService.convertImages(
            _inputs,
            to: ImageFormat.png,
            onProgress: progress,
          );
      }
      if (!mounted) return;
      final nothing = _mode.producesImages
          ? _results.isEmpty
          : _pdfResult == null;
      if (nothing) _snack('conv_failed'.tr());
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
    final files = _mode.producesImages ? _results : [_pdfResult!];
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
    final isPdfInput = _mode == ConvertMode.pdfToJpg;
    final hasResult = _results.isNotEmpty || _pdfResult != null;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(title: Text(_mode.titleKey.tr())),
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
                  isPdfInput
                      ? Icons.picture_as_pdf
                      : Icons.add_photo_alternate_outlined,
                  color: cs.onPrimaryContainer,
                ),
              ),
              title: Text(
                isPdfInput ? 'pick_pdf'.tr() : 'conv_pick_images'.tr(),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: Text(
                _inputs.isEmpty
                    ? 'conv_formats'.tr(
                        namedArgs: {
                          'formats': _mode.inputExtensions
                              .map((e) => e.toUpperCase())
                              .toSet()
                              .join(', '),
                        },
                      )
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
          if (_inputs.isNotEmpty && !isPdfInput) ...[
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
