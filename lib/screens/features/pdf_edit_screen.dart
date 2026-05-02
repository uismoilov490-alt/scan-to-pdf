import 'dart:io';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdfx/pdfx.dart';
import '../../services/pdf_service.dart';

class PdfEditScreen extends StatefulWidget {
  const PdfEditScreen({super.key});

  @override
  State<PdfEditScreen> createState() => _PdfEditScreenState();
}

class _EditPage {
  final File image;
  int rotation;
  _EditPage({required this.image}) : rotation = 0;
}

class _PdfEditScreenState extends State<PdfEditScreen> {
  List<File> _savedPdfs = [];
  bool _loadingPdfs = true;
  String? _selectedPdfName;
  List<_EditPage> _pages = [];
  bool _rendering = false;
  bool _saving = false;

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

  Future<void> _pickAndRenderPdf() async {
    if (_savedPdfs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('no_saved_pdf'.tr())),
      );
      return;
    }

    final selected = await showModalBottomSheet<File>(
      context: context,
      showDragHandle: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => ListView.builder(
        shrinkWrap: true,
        padding: const EdgeInsets.all(16),
        itemCount: _savedPdfs.length,
        itemBuilder: (_, i) {
          final name = _savedPdfs[i].path.split('/').last;
          return ListTile(
            leading: const Icon(Icons.picture_as_pdf, color: Colors.red),
            title: Text(name),
            onTap: () => Navigator.pop(context, _savedPdfs[i]),
          );
        },
      ),
    );

    if (selected == null || !mounted) return;

    setState(() {
      _selectedPdfName = selected.path.split('/').last.replaceAll('.pdf', '');
      _rendering = true;
      _pages.clear();
    });

    try {
      final tempDir = await getTemporaryDirectory();
      final document = await PdfDocument.openFile(selected.path);
      final pageCount = document.pagesCount;
      final pages = <_EditPage>[];

      for (int i = 1; i <= pageCount; i++) {
        final page = await document.getPage(i);
        final image = await page.render(
          width: page.width * 2,
          height: page.height * 2,
          format: PdfPageImageFormat.jpeg,
          backgroundColor: '#ffffff',
        );
        await page.close();

        if (image != null) {
          final imgFile = File(
            '${tempDir.path}/edit_p${i}_${DateTime.now().millisecondsSinceEpoch}.jpg',
          );
          await imgFile.writeAsBytes(image.bytes);
          pages.add(_EditPage(image: imgFile));
        }
      }
      await document.close();

      if (mounted) {
        setState(() {
          _pages = pages;
          _rendering = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _rendering = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('error_prefix'.tr(namedArgs: {'message': e.toString()})),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _savePdf() async {
    if (_pages.isEmpty) return;
    setState(() => _saving = true);

    try {
      final now = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      final name = '${_selectedPdfName ?? 'Tahrirlangan'}_$now';
      final file = await PdfService.generatePdf(
        imageFiles: _pages.map((p) => p.image).toList(),
        fileName: name,
        quarterTurns: _pages.map((p) => p.rotation).toList(),
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('saved_as'.tr(namedArgs: {'name': file.path.split('/').last})),
          backgroundColor: Colors.green,
        ),
      );
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('error_prefix'.tr(namedArgs: {'message': e.toString()})),
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
      appBar: AppBar(
        backgroundColor: theme.colorScheme.primary,
        foregroundColor: theme.colorScheme.onPrimary,
        title: Text('edit_title'.tr()),
        actions: [
          if (_pages.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.save_rounded),
              onPressed: _saving ? null : _savePdf,
              tooltip: 'save'.tr(),
            ),
        ],
      ),
      body: _loadingPdfs
          ? const Center(child: CircularProgressIndicator())
          : _buildBody(theme),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _rendering ? null : _pickAndRenderPdf,
        icon: const Icon(Icons.folder_open),
        label: Text('pick_pdf'.tr()),
        backgroundColor: theme.colorScheme.primary,
        foregroundColor: theme.colorScheme.onPrimary,
      ),
    );
  }

  Widget _buildBody(ThemeData theme) {
    if (_rendering) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text('edit_loading'.tr()),
          ],
        ),
      );
    }

    if (_pages.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.picture_as_pdf_outlined,
              size: 80,
              color: theme.colorScheme.primary.withValues(alpha: 0.35),
            ),
            const SizedBox(height: 16),
            Text(
              'edit_empty_hint1'.tr(),
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'edit_empty_hint2'.tr(),
              textAlign: TextAlign.center,
              style: TextStyle(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 80),
          ],
        ),
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(
            children: [
              Text(
                'pages_count'.tr(namedArgs: {'count': '${_pages.length}'}),
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                  color: theme.colorScheme.onSurface,
                ),
              ),
              const Spacer(),
              Text(
                'edit_reorder_hint'.tr(),
                style: TextStyle(
                  fontSize: 11,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ReorderableListView.builder(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
            itemCount: _pages.length,
            onReorder: (oldIdx, newIdx) {
              setState(() {
                if (newIdx > oldIdx) newIdx--;
                final item = _pages.removeAt(oldIdx);
                _pages.insert(newIdx, item);
              });
            },
            itemBuilder: (context, index) {
              final page = _pages[index];
              return Card(
                key: ValueKey('page_$index'),
                margin: const EdgeInsets.only(bottom: 10),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: RotatedBox(
                          quarterTurns: page.rotation,
                          child: Image.file(
                            page.image,
                            width: 65,
                            height: 85,
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Text(
                          'edit_page_label'.tr(namedArgs: {'number': '${index + 1}'}),
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                            color: theme.colorScheme.onSurface,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: Icon(
                          Icons.rotate_right,
                          color: theme.colorScheme.primary,
                        ),
                        onPressed: () =>
                            setState(() => page.rotation = (page.rotation + 1) % 4),
                        tooltip: 'edit_rotate'.tr(),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline, color: Colors.red),
                        onPressed: () => setState(() => _pages.removeAt(index)),
                        tooltip: 'delete'.tr(),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        Container(
          color: theme.colorScheme.surfaceContainerLow,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: SafeArea(
            top: false,
            child: FilledButton.icon(
              onPressed: _saving ? null : _savePdf,
              icon: _saving
                  ? SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: theme.colorScheme.onPrimary,
                      ),
                    )
                  : const Icon(Icons.save),
              label: Text(_saving ? 'edit_saving'.tr() : 'edit_save_btn'.tr()),
              style: FilledButton.styleFrom(
                minimumSize: const Size(double.infinity, 52),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
