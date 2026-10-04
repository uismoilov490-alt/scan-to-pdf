import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../services/pdf_service.dart';

class SavedDocumentsScreen extends StatefulWidget {
  const SavedDocumentsScreen({super.key});

  @override
  State<SavedDocumentsScreen> createState() => _SavedDocumentsScreenState();
}

class _SavedDocumentsScreenState extends State<SavedDocumentsScreen> {
  List<File> _pdfs = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final files = await PdfService.listSavedPdfs();
    if (mounted) {
      setState(() {
        _pdfs = files;
        _loading = false;
      });
    }
  }

  String _formatDate(DateTime dt) => DateFormat('dd.MM.yyyy  HH:mm').format(dt);

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  Future<void> _viewPdf(File file) async {
    final bytes = await file.readAsBytes();
    if (!mounted) return;
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(
            title: Text(
              file.path
                  .split(Platform.pathSeparator)
                  .last
                  .replaceAll('.pdf', ''),
              style: const TextStyle(fontSize: 15),
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.share),
                onPressed: () => _sharePdf(file),
              ),
            ],
          ),
          body: PdfPreview(
            build: (_) => bytes,
            allowPrinting: true,
            allowSharing: true,
            canChangePageFormat: false,
          ),
        ),
      ),
    );
  }

  Future<void> _sharePdf(File file) async {
    await Share.shareXFiles([XFile(file.path)], text: 'pdf_document'.tr());
  }

  Future<void> _deletePdf(File file) async {
    final name = file.path
        .split(Platform.pathSeparator)
        .last
        .replaceAll('.pdf', '');
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('delete_title'.tr()),
        content: Text('delete_confirm'.tr(namedArgs: {'name': name})),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('cancel'.tr()),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: Text('delete'.tr()),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await PdfService.deletePdf(file.path);
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Scaffold(
      backgroundColor: cs.surfaceContainerLowest,
      appBar: AppBar(
        title: Text('profile_saved_title'.tr()),
        backgroundColor: cs.surfaceContainerLow,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _pdfs.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.picture_as_pdf_outlined,
                      size: 72,
                      color: cs.primary.withValues(alpha: 0.35),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'no_documents'.tr(),
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'no_documents_hint'.tr(),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            )
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: _pdfs.length,
                itemBuilder: (context, index) {
                  final file = _pdfs[index];
                  final stat = file.statSync();
                  final name = file.path
                      .split(Platform.pathSeparator)
                      .last
                      .replaceAll('.pdf', '');
                  return Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    elevation: 0,
                    color: cs.surface,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                      side: BorderSide(
                        color: cs.outlineVariant.withValues(alpha: 0.5),
                      ),
                    ),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () => _viewPdf(file),
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Row(
                          children: [
                            Container(
                              width: 50,
                              height: 58,
                              decoration: BoxDecoration(
                                color: cs.primaryContainer,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Icon(
                                Icons.picture_as_pdf,
                                color: cs.primary,
                                size: 28,
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    name,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 15,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    _formatDate(stat.modified),
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: cs.onSurfaceVariant,
                                    ),
                                  ),
                                  Text(
                                    _formatSize(stat.size),
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: cs.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            PopupMenuButton<String>(
                              icon: const Icon(Icons.more_vert),
                              onSelected: (val) {
                                if (val == 'view') _viewPdf(file);
                                if (val == 'share') _sharePdf(file);
                                if (val == 'delete') _deletePdf(file);
                              },
                              itemBuilder: (_) => [
                                PopupMenuItem(
                                  value: 'view',
                                  child: ListTile(
                                    leading: const Icon(Icons.visibility),
                                    title: Text('view'.tr()),
                                    contentPadding: EdgeInsets.zero,
                                  ),
                                ),
                                PopupMenuItem(
                                  value: 'share',
                                  child: ListTile(
                                    leading: const Icon(Icons.share),
                                    title: Text('share'.tr()),
                                    contentPadding: EdgeInsets.zero,
                                  ),
                                ),
                                PopupMenuItem(
                                  value: 'delete',
                                  child: ListTile(
                                    leading: const Icon(
                                      Icons.delete,
                                      color: Colors.red,
                                    ),
                                    title: Text(
                                      'delete'.tr(),
                                      style: const TextStyle(color: Colors.red),
                                    ),
                                    contentPadding: EdgeInsets.zero,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
    );
  }
}
