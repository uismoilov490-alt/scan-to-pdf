import 'dart:io';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:share_plus/share_plus.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdfx/pdfx.dart';
import '../../services/document_export_service.dart';
import '../../services/pdf_service.dart';
import '../../widgets/pdf_source_sheet.dart';
import '../../services/ad_service.dart';

class PdfToWordScreen extends StatefulWidget {
  const PdfToWordScreen({super.key});

  @override
  State<PdfToWordScreen> createState() => _PdfToWordScreenState();
}

class _PdfToWordScreenState extends State<PdfToWordScreen> {
  List<File> _savedPdfs = [];
  bool _loadingPdfs = true;
  File? _selectedPdf;
  bool _converting = false;
  String? _extractedText;
  String? _outputPath;
  double _progress = 0;
  int _currentPage = 0;
  int _totalPages = 0;

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

    if (selected == null || !mounted) return;
    setState(() {
      _selectedPdf = selected;
      _extractedText = null;
      _outputPath = null;
    });
  }

  Future<void> _openOutput() async {
    final result = await OpenFilex.open(_outputPath!);
    if (result.type != ResultType.done && mounted) {
      // Telefonda Word ochadigan ilova yo'q bo'lsa — ulashish orqali yuborish mumkin
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('no_app_to_open'.tr())));
    }
  }

  Future<void> _convert() async {
    if (_selectedPdf == null) return;
    setState(() {
      _converting = true;
      _progress = 0;
      _extractedText = null;
    });

    try {
      final tempDir = await getTemporaryDirectory();
      final document = await PdfDocument.openFile(_selectedPdf!.path);
      final pageCount = document.pagesCount;
      setState(() => _totalPages = pageCount);

      final textRecognizer = TextRecognizer(
        script: TextRecognitionScript.latin,
      );
      final pageTexts = <String>[];

      for (int i = 1; i <= pageCount; i++) {
        if (!mounted) break;
        setState(() {
          _currentPage = i;
          _progress = (i - 1) / pageCount;
        });

        final page = await document.getPage(i);
        final rendered = await page.render(
          width: page.width * 2,
          height: page.height * 2,
          format: PdfPageImageFormat.jpeg,
          backgroundColor: '#ffffff',
        );
        await page.close();

        if (rendered != null) {
          final imgFile = File(
            '${tempDir.path}/ocr_p${i}_${DateTime.now().millisecondsSinceEpoch}.jpg',
          );
          await imgFile.writeAsBytes(rendered.bytes);

          final recognized = await textRecognizer.processImage(
            InputImage.fromFile(imgFile),
          );
          if (recognized.text.isNotEmpty) {
            pageTexts.add(
              '--- ${'edit_page_label'.tr(namedArgs: {'number': '$i'})} ---\n${recognized.text}',
            );
          }

          await imgFile.delete();
        }
      }

      await textRecognizer.close();
      await document.close();

      final fullText = pageTexts.join('\n\n');
      final outFile = await _saveAsDocx(fullText);

      if (mounted) {
        setState(() {
          _extractedText = fullText.isEmpty ? 'ocr_no_text'.tr() : fullText;
          _outputPath = outFile.path;
          _progress = 1.0;
          _converting = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'word_saved'.tr(
                namedArgs: {'name': outFile.path.split('/').last},
              ),
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _converting = false);
        final cs = Theme.of(context).colorScheme;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'error_prefix'.tr(namedArgs: {'message': '$e'}),
              style: TextStyle(color: cs.onErrorContainer),
            ),
            behavior: SnackBarBehavior.floating,
            backgroundColor: cs.errorContainer,
          ),
        );
      }
    }
  }

  Future<File> _saveAsDocx(String text) async {
    final zipBytes = DocumentExportService.buildDocx(text);

    final docsDir = await getApplicationDocumentsDirectory();
    final saveDir = Directory('${docsDir.path}/scan_to_pdf');
    if (!await saveDir.exists()) await saveDir.create(recursive: true);

    final baseName = _selectedPdf!.path.split('/').last.replaceAll('.pdf', '');
    final now = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    final outFile = File('${saveDir.path}/${baseName}_$now.docx');
    await outFile.writeAsBytes(zipBytes);
    AdService.recordSave();

    return outFile;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(title: Text('pdf_to_word_title'.tr())),
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
          _PickCard(
            icon: Icons.picture_as_pdf,
            iconBg: theme.colorScheme.errorContainer,
            iconColor: theme.colorScheme.error,
            title: 'pick_pdf'.tr(),
            subtitle: _selectedPdf != null
                ? _selectedPdf!.path.split('/').last
                : 'no_file_selected'.tr(),
            onTap: _converting ? null : _pickPdf,
          ),
          if (_converting) ...[
            const SizedBox(height: 20),
            Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: _progress,
                        minHeight: 8,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'pdf_to_word_progress'.tr(
                        namedArgs: {
                          'current': '$_currentPage',
                          'total': '$_totalPages',
                        },
                      ),
                      style: TextStyle(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'pdf_to_word_ocr_label'.tr(),
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          if (_extractedText != null && !_converting) ...[
            const SizedBox(height: 16),
            Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'pdf_to_word_result_title'.tr(),
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Container(
                      constraints: const BoxConstraints(maxHeight: 260),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: theme.colorScheme.outlineVariant,
                        ),
                      ),
                      padding: const EdgeInsets.all(12),
                      child: SingleChildScrollView(
                        child: SelectableText(
                          _extractedText!,
                          style: TextStyle(
                            fontSize: 13,
                            height: 1.5,
                            color: theme.colorScheme.onSurface,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (_outputPath != null) ...[
              const SizedBox(height: 12),
              _SuccessBanner(
                text: 'word_saved'.tr(
                  namedArgs: {'name': _outputPath!.split('/').last},
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _openOutput,
                      icon: const Icon(Icons.open_in_new),
                      label: Text('open_file'.tr()),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.tonalIcon(
                      onPressed: () => Share.shareXFiles([XFile(_outputPath!)]),
                      icon: const Icon(Icons.share),
                      label: Text('share'.tr()),
                    ),
                  ),
                ],
              ),
            ],
          ],
          if (_selectedPdf != null &&
              !_converting &&
              _extractedText == null) ...[
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, color: theme.colorScheme.primary),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'pdf_to_word_info'.tr(),
                        style: TextStyle(
                          fontSize: 13,
                          color: theme.colorScheme.onSurfaceVariant,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          if (_selectedPdf != null) ...[
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _converting ? null : _convert,
              icon: _converting
                  ? SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: theme.colorScheme.onPrimary,
                      ),
                    )
                  : const Icon(Icons.article_rounded),
              label: Text(
                _converting
                    ? 'pdf_to_word_converting'.tr()
                    : 'pdf_to_word_btn'.tr(),
              ),
              style: FilledButton.styleFrom(
                minimumSize: const Size(double.infinity, 52),
              ),
            ),
          ] else if (!_converting) ...[
            const SizedBox(height: 40),
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.import_export_rounded,
                    size: 80,
                    color: theme.colorScheme.primary.withValues(alpha: 0.35),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'pdf_to_word_empty_hint1'.tr(),
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                  Text(
                    'pdf_to_word_empty_hint2'.tr(),
                    style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
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

class _PickCard extends StatelessWidget {
  final IconData icon;
  final Color iconBg;
  final Color iconColor;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  const _PickCard({
    required this.icon,
    required this.iconBg,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
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
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
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
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
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
          Icon(Icons.check_circle_rounded, color: cs.primary, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: cs.onPrimaryContainer,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
