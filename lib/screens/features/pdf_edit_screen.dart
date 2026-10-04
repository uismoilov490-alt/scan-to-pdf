import 'dart:io';
import 'package:easy_localization/easy_localization.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdfx/pdfx.dart';
import '../../services/pdf_service.dart';
import '../../widgets/pdf_source_sheet.dart';

class PdfEditScreen extends StatefulWidget {
  const PdfEditScreen({super.key});

  @override
  State<PdfEditScreen> createState() => _PdfEditScreenState();
}

class _EditPage {
  static int _nextId = 0;

  // Ro'yxatda barqaror kalit — tartib o'zgarsa yoki sahifa o'chirilsa adashmasin
  final int id = _nextId++;
  final File image;
  int rotation = 0;

  _EditPage({required this.image});
}

enum _AddSource { images, pdf, camera }

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

  /// PDF'ning har bir sahifasini rasmga aylantiradi (tahrirlash va saqlash shu rasmlar bilan).
  Future<List<_EditPage>> _renderPdf(File pdf) async {
    final tempDir = await getTemporaryDirectory();
    final document = await PdfDocument.openFile(pdf.path);
    final pages = <_EditPage>[];
    try {
      for (int i = 1; i <= document.pagesCount; i++) {
        final page = await document.getPage(i);
        final image = await page.render(
          width: page.width * 2,
          height: page.height * 2,
          format: PdfPageImageFormat.jpeg,
          backgroundColor: '#ffffff',
          quality: 92,
        );
        await page.close();
        if (image != null) {
          final imgFile = File(
            '${tempDir.path}/edit_p${i}_${DateTime.now().microsecondsSinceEpoch}.jpg',
          );
          await imgFile.writeAsBytes(image.bytes);
          pages.add(_EditPage(image: imgFile));
        }
      }
    } finally {
      await document.close();
    }
    return pages;
  }

  Future<void> _pickAndRenderPdf() async {
    final selected = await pickPdf(context, _savedPdfs);
    if (selected == null || !mounted) return;

    setState(() {
      _selectedPdfName = selected.path.split('/').last.replaceAll('.pdf', '');
      _rendering = true;
      _pages.clear();
    });

    try {
      final pages = await _renderPdf(selected);
      if (mounted) setState(() => _pages = pages);
    } catch (e) {
      _showError(e);
    } finally {
      if (mounted) setState(() => _rendering = false);
    }
  }

  Future<void> _addPages() async {
    final source = await showModalBottomSheet<_AddSource>(
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
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                'edit_add_title'.tr(),
                style: Theme.of(
                  ctx,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.image_outlined),
              title: Text('edit_add_images'.tr()),
              subtitle: Text('edit_add_images_hint'.tr()),
              onTap: () => Navigator.pop(ctx, _AddSource.images),
            ),
            ListTile(
              leading: const Icon(Icons.picture_as_pdf_outlined),
              title: Text('edit_add_pdf'.tr()),
              subtitle: Text('edit_add_pdf_hint'.tr()),
              onTap: () => Navigator.pop(ctx, _AddSource.pdf),
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined),
              title: Text('edit_add_camera'.tr()),
              onTap: () => Navigator.pop(ctx, _AddSource.camera),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (source == null || !mounted) return;

    try {
      List<_EditPage> added = [];
      switch (source) {
        case _AddSource.images:
          final result = await FilePicker.platform.pickFiles(
            type: FileType.custom,
            allowedExtensions: const ['jpg', 'jpeg', 'png', 'webp'],
            allowMultiple: true,
          );
          added = (result?.files ?? [])
              .where((f) => f.path != null)
              .map((f) => _EditPage(image: File(f.path!)))
              .toList();
        case _AddSource.pdf:
          final pdf = await pickPdf(context, _savedPdfs);
          if (pdf == null || !mounted) return;
          setState(() => _rendering = true);
          added = await _renderPdf(pdf);
        case _AddSource.camera:
          final shot = await ImagePicker().pickImage(
            source: ImageSource.camera,
            imageQuality: 92,
          );
          if (shot != null) added = [_EditPage(image: File(shot.path))];
      }
      if (added.isEmpty || !mounted) return;
      setState(() => _pages.addAll(added));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'edit_pages_added'.tr(namedArgs: {'count': '${added.length}'}),
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      _showError(e);
    } finally {
      if (mounted && _rendering) setState(() => _rendering = false);
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
        // Tahrirlashda sahifalar asl ko'rinishida qolishi kerak (skaner filtrisiz)
        enhance: false,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'saved_as'.tr(namedArgs: {'name': file.path.split('/').last}),
          ),
          backgroundColor: Colors.green,
        ),
      );
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => _saving = false);
      _showError(e);
    }
  }

  void _showError(Object e) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('error_prefix'.tr(namedArgs: {'message': e.toString()})),
        backgroundColor: Colors.red,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text('edit_title'.tr()),
        actions: [
          // Sahifalar ochilgach fayl almashtirish tepada — pastki tugmalarni to'smasin
          if (_pages.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.folder_open),
              onPressed: _rendering ? null : _pickAndRenderPdf,
              tooltip: 'pick_pdf'.tr(),
            ),
        ],
      ),
      body: _loadingPdfs
          ? const Center(child: CircularProgressIndicator())
          : _buildBody(theme),
      floatingActionButton: _pages.isNotEmpty || _rendering
          ? null
          : FloatingActionButton.extended(
              onPressed: _pickAndRenderPdf,
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
              style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
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
                key: ValueKey(page.id),
                margin: const EdgeInsets.only(bottom: 10),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 85,
                        height: 85,
                        child: Center(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: RotatedBox(
                              quarterTurns: page.rotation,
                              child: Image.file(
                                page.image,
                                width: 65,
                                height: 85,
                                fit: BoxFit.cover,
                                cacheWidth: 200,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'edit_page_label'.tr(
                            namedArgs: {'number': '${index + 1}'},
                          ),
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
                        onPressed: () => setState(
                          () => page.rotation = (page.rotation + 1) % 4,
                        ),
                        tooltip: 'edit_rotate'.tr(),
                      ),
                      IconButton(
                        icon: const Icon(
                          Icons.delete_outline,
                          color: Colors.red,
                        ),
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
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _saving ? null : _addPages,
                    icon: const Icon(Icons.add_rounded),
                    label: Text('edit_add_btn'.tr()),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 52),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
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
                    label: Text(_saving ? 'edit_saving'.tr() : 'save'.tr()),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 52),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
