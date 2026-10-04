import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:xml/xml.dart';
import '../../services/ad_service.dart';

class WordToPdfScreen extends StatefulWidget {
  const WordToPdfScreen({super.key});

  @override
  State<WordToPdfScreen> createState() => _WordToPdfScreenState();
}

class _WordToPdfScreenState extends State<WordToPdfScreen> {
  File? _wordFile;
  List<String> _paragraphs = [];
  bool _converting = false;
  String? _outputPath;

  Future<void> _pickWordFile() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.any);
    if (result == null || result.files.single.path == null) return;

    final path = result.files.single.path!;
    final ext = path.split('.').last.toLowerCase();
    if (ext != 'docx') {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('word_to_pdf_invalid_format'.tr()),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }

    final file = File(path);
    setState(() {
      _wordFile = file;
      _paragraphs = [];
      _outputPath = null;
    });

    await _extractText(file);
  }

  Future<void> _extractText(File file) async {
    try {
      final bytes = await file.readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);

      for (final entry in archive) {
        if (entry.name == 'word/document.xml') {
          final content = utf8.decode(entry.content as List<int>);
          final xmlDoc = XmlDocument.parse(content);
          final paras = <String>[];

          for (final para in xmlDoc.findAllElements('w:p')) {
            final sb = StringBuffer();
            for (final run in para.findAllElements('w:r')) {
              for (final t in run.findAllElements('w:t')) {
                sb.write(t.innerText);
              }
            }
            if (sb.isNotEmpty) paras.add(sb.toString());
          }

          setState(() => _paragraphs = paras);
          return;
        }
      }
      setState(() => _paragraphs = ['ocr_no_text'.tr()]);
    } catch (e) {
      setState(
        () => _paragraphs = [
          'error_prefix'.tr(namedArgs: {'message': '$e'}),
        ],
      );
    }
  }

  Future<void> _convert() async {
    if (_wordFile == null || _paragraphs.isEmpty) return;
    setState(() => _converting = true);

    try {
      // Noto Sans — lotin, kirill va o'zbek harflarini to'liq qo'llab-quvvatlaydi
      final fontRegular = await PdfGoogleFonts.notoSansRegular();
      final fontBold = await PdfGoogleFonts.notoSansBold();

      final pdf = pw.Document(
        theme: pw.ThemeData.withFont(base: fontRegular, bold: fontBold),
      );
      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(40),
          build: (ctx) => _paragraphs
              .map(
                (line) => pw.Padding(
                  padding: const pw.EdgeInsets.only(bottom: 6),
                  child: pw.Text(
                    line,
                    style: pw.TextStyle(font: fontRegular, fontSize: 11),
                  ),
                ),
              )
              .toList(),
        ),
      );

      final docsDir = await getApplicationDocumentsDirectory();
      final saveDir = Directory('${docsDir.path}/scan_to_pdf');
      if (!await saveDir.exists()) await saveDir.create(recursive: true);

      final baseName = _wordFile!.path
          .split('/')
          .last
          .replaceAll(RegExp(r'\.[^.]+$'), '');
      final now = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      final outFile = File('${saveDir.path}/${baseName}_$now.pdf');
      await outFile.writeAsBytes(await pdf.save());
      AdService.recordSave();

      setState(() {
        _outputPath = outFile.path;
        _converting = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'pdf_saved'.tr(namedArgs: {'name': outFile.path.split('/').last}),
            ),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _converting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('error_prefix'.tr(namedArgs: {'message': '$e'})),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(title: Text('word_to_pdf_title'.tr())),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _PickCard(
              icon: Icons.article_rounded,
              iconBg: theme.colorScheme.primaryContainer,
              iconColor: theme.colorScheme.primary,
              title: 'word_to_pdf_pick_title'.tr(),
              subtitle: _wordFile != null
                  ? _wordFile!.path.split('/').last
                  : 'no_file_selected'.tr(),
              onTap: _pickWordFile,
            ),
            if (_paragraphs.isNotEmpty) ...[
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
                        'word_to_pdf_preview'.tr(
                          namedArgs: {'count': '${_paragraphs.length}'},
                        ),
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
                            _paragraphs.join('\n'),
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
                  text: 'pdf_saved'.tr(
                    namedArgs: {'name': _outputPath!.split('/').last},
                  ),
                ),
              ],
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
                    : const Icon(Icons.picture_as_pdf),
                label: Text(
                  _converting
                      ? 'word_to_pdf_converting'.tr()
                      : 'word_to_pdf_btn'.tr(),
                ),
                style: FilledButton.styleFrom(
                  minimumSize: const Size(double.infinity, 52),
                ),
              ),
            ] else ...[
              const SizedBox(height: 40),
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.article_outlined,
                      size: 80,
                      color: theme.colorScheme.primary.withValues(alpha: 0.35),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'word_to_pdf_empty_hint1'.tr(),
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                    Text(
                      'word_to_pdf_empty_hint2'.tr(),
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
  final VoidCallback onTap;

  const _PickCard({
    required this.icon,
    required this.iconBg,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
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
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.green.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.green.shade200),
      ),
      child: Row(
        children: [
          const Icon(Icons.check_circle_rounded, color: Colors.green),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: Colors.green,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
