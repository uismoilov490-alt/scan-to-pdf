import 'dart:io';
import 'dart:typed_data';
import 'package:easy_localization/easy_localization.dart';
import 'package:open_filex/open_filex.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart' hide PdfDocument;
import 'package:pdf/widgets.dart' as pw;
import 'package:pdfx/pdfx.dart';
import '../../services/pdf_service.dart';
import '../../widgets/pdf_source_sheet.dart';

class PdfCompressScreen extends StatefulWidget {
  const PdfCompressScreen({super.key});

  @override
  State<PdfCompressScreen> createState() => _PdfCompressScreenState();
}

class _PdfCompressScreenState extends State<PdfCompressScreen> {
  List<File> _savedPdfs = [];
  bool _loadingPdfs = true;
  File? _selectedPdf;
  int _qualityIndex = 1;
  bool _compressing = false;
  int? _originalSize;
  int? _compressedSize;
  String? _outPath;
  // Siqilgan nusxa kichraymadi (masalan, matnli PDF) — fayl saqlanmadi
  bool _notSmaller = false;

  List<String> get _qualityLabels => [
    'compress_quality_low'.tr(),
    'compress_quality_medium'.tr(),
    'compress_quality_high'.tr(),
  ];
  static const _jpegQuality = [40, 65, 82];
  static const _scaleFactors = [0.65, 0.85, 1.0];

  @override
  void initState() {
    super.initState();
    _loadSavedPdfs();
  }

  Future<void> _loadSavedPdfs() async {
    final pdfs = await PdfService.listSavedPdfs();
    if (mounted) {
      setState(() {
        _savedPdfs = pdfs;
        _loadingPdfs = false;
      });
    }
  }

  Future<void> _pickPdf() async {
    final selected = await pickPdf(context, _savedPdfs);

    if (selected == null) return;
    setState(() {
      _selectedPdf = selected;
      _originalSize = selected.statSync().size;
      _compressedSize = null;
      _outPath = null;
      _notSmaller = false;
    });
  }

  Future<void> _compress() async {
    if (_selectedPdf == null) return;
    setState(() {
      _compressing = true;
      _notSmaller = false;
      _outPath = null;
    });

    try {
      final document = await PdfDocument.openFile(_selectedPdf!.path);
      final pageCount = document.pagesCount;
      final quality = _jpegQuality[_qualityIndex];
      final scale = _scaleFactors[_qualityIndex];

      final pdf = pw.Document();

      for (int i = 1; i <= pageCount; i++) {
        final page = await document.getPage(i);
        final pageW = page.width;
        final pageH = page.height;

        final rendered = await page.render(
          width: pageW * scale * 2,
          height: pageH * scale * 2,
          format: PdfPageImageFormat.jpeg,
          backgroundColor: '#ffffff',
        );
        await page.close();

        if (rendered == null) continue;

        final decoded = img.decodeJpg(rendered.bytes);
        if (decoded == null) continue;
        final compressed = Uint8List.fromList(
          img.encodeJpg(decoded, quality: quality),
        );

        pdf.addPage(
          pw.Page(
            pageFormat: PdfPageFormat(pageW, pageH),
            build: (_) => pw.Image(
              pw.MemoryImage(compressed),
              fit: pw.BoxFit.fill,
            ),
          ),
        );
      }
      await document.close();

      final docsDir = await getApplicationDocumentsDirectory();
      final saveDir = Directory('${docsDir.path}/scan_to_pdf');
      if (!await saveDir.exists()) await saveDir.create(recursive: true);

      final baseName =
          _selectedPdf!.path.split('/').last.replaceAll('.pdf', '');
      final now = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      final bytes = await pdf.save();

      // Sahifalar rasmga aylantiriladi — matnli PDF bunda kattalashadi.
      // 5% dan kam yutuq bo'lsa saqlamaymiz, asl fayl qoladi.
      if (bytes.length >= _originalSize! * 0.95) {
        setState(() {
          _notSmaller = true;
          _compressing = false;
        });
        return;
      }

      final outFile = File('${saveDir.path}/${baseName}_siqilgan_$now.pdf');
      await outFile.writeAsBytes(bytes);

      setState(() {
        _compressedSize = bytes.length;
        _outPath = outFile.path;
        _notSmaller = false;
        _compressing = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('saved_as'.tr(namedArgs: {'name': outFile.path.split('/').last})),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _compressing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('error_prefix'.tr(namedArgs: {'message': e.toString()})),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: theme.colorScheme.primary,
        foregroundColor: theme.colorScheme.onPrimary,
        title: Text('compress_title'.tr()),
      ),
      body: _loadingPdfs
          ? const Center(child: CircularProgressIndicator())
          : _buildBody(theme),
    );
  }

  Widget _buildBody(ThemeData theme) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _PickerCard(
            icon: Icons.folder_zip_outlined,
            iconColor: theme.colorScheme.tertiary,
            iconBg: theme.colorScheme.tertiaryContainer.withValues(alpha: 0.75),
            title: 'pick_pdf'.tr(),
            subtitle: _selectedPdf != null
                ? _selectedPdf!.path.split('/').last
                : 'no_file_selected'.tr(),
            onTap: _pickPdf,
          ),
          if (_selectedPdf != null) ...[
            const SizedBox(height: 16),
            Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _SizeBadge(
                      label: 'compress_original_size'.tr(),
                      value: _formatSize(_originalSize ?? 0),
                      color: theme.colorScheme.tertiary,
                    ),
                    Icon(
                      Icons.arrow_forward_rounded,
                      color: theme.colorScheme.onSurfaceVariant,
                      size: 20,
                    ),
                    _SizeBadge(
                      label: 'compress_new_size'.tr(),
                      value: _compressedSize != null
                          ? _formatSize(_compressedSize!)
                          : '—',
                      color: theme.colorScheme.primary,
                    ),
                    if (_compressedSize != null && _originalSize != null && _compressedSize! < _originalSize!) ...[
                      Icon(
                        Icons.arrow_forward_rounded,
                        color: theme.colorScheme.onSurfaceVariant,
                        size: 20,
                      ),
                      _SizeBadge(
                        label: 'compress_reduction'.tr(),
                        value:
                            '-${((1 - _compressedSize! / _originalSize!) * 100).toStringAsFixed(0)}%',
                        color: theme.colorScheme.secondary,
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'compress_quality_level'.tr(),
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 4),
                    ...List.generate(3, (i) {
                      final selected = _qualityIndex == i;
                      return InkWell(
                        onTap: () => setState(() => _qualityIndex = i),
                        borderRadius: BorderRadius.circular(8),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 6,
                          ),
                          child: Row(
                            children: [
                              Icon(
                                selected
                                    ? Icons.radio_button_checked
                                    : Icons.radio_button_off,
                                size: 20,
                                color: selected
                                    ? theme.colorScheme.primary
                                    : theme.colorScheme.outlineVariant,
                              ),
                              const SizedBox(width: 10),
                              Text(
                                _qualityLabels[i],
                                style: TextStyle(
                                  color: theme.colorScheme.onSurface,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _compressing ? null : _compress,
              icon: _compressing
                  ? SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: theme.colorScheme.onPrimary,
                      ),
                    )
                  : const Icon(Icons.compress),
              label: Text(_compressing ? 'compress_compressing'.tr() : 'compress_btn'.tr()),
              style: FilledButton.styleFrom(
                minimumSize: const Size(double.infinity, 52),
              ),
            ),
            if (_notSmaller) ...[
              const SizedBox(height: 16),
              Card(
                color: theme.colorScheme.secondaryContainer,
                child: ListTile(
                  leading: Icon(Icons.info_outline, color: theme.colorScheme.onSecondaryContainer),
                  title: Text('compress_not_smaller_title'.tr()),
                  subtitle: Text('compress_not_smaller_body'.tr()),
                ),
              ),
            ],
            if (_outPath != null) ...[
              const SizedBox(height: 12),
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
          ] else ...[
            const SizedBox(height: 40),
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.folder_zip_outlined,
                    size: 80,
                    color:
                        theme.colorScheme.primary.withValues(alpha: 0.35),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'compress_empty_hint1'.tr(),
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                  Text(
                    'compress_empty_hint2'.tr(),
                    style: TextStyle(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SizeBadge extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _SizeBadge({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 16,
            color: color,
          ),
        ),
        Text(
          label,
          style: TextStyle(color: muted, fontSize: 11),
        ),
      ],
    );
  }
}

class _PickerCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final Color iconBg;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _PickerCard({
    required this.icon,
    required this.iconColor,
    required this.iconBg,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: iconBg,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: iconColor),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        color: cs.onSurface,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: cs.onSurfaceVariant,
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
                color: cs.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
