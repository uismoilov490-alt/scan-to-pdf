import 'dart:io';
import 'dart:typed_data';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../services/book_splitter.dart';
import '../../services/document_cleaner.dart';
import '../../services/pdf/pdf_toolkit.dart';
import '../../services/pdf_service.dart';
import '../../widgets/image_source_sheet.dart';
import '../../widgets/tool_widgets.dart';

/// Kitob rejimi: ochiq kitob suratlari ikki sahifaga ajratiladi va PDF bo'ladi.
class BookScanScreen extends StatefulWidget {
  const BookScanScreen({super.key});

  @override
  State<BookScanScreen> createState() => _BookScanScreenState();
}

class _BookScanScreenState extends State<BookScanScreen> {
  final List<File> _photos = [];
  bool _clean = true;
  bool _busy = false;
  int _done = 0;

  Future<void> _add() async {
    final photos = await pickImages(context);
    if (photos.isNotEmpty && mounted) setState(() => _photos.addAll(photos));
  }

  Future<void> _build() async {
    setState(() {
      _busy = true;
      _done = 0;
    });
    try {
      final pages = <PageSource>[];
      for (final photo in _photos) {
        for (var page in await BookSplitter.split(await photo.readAsBytes())) {
          if (_clean) {
            page = await DocumentCleaner.clean(page, crop: false) ?? page;
          }
          pages.add(ImagePage(page));
        }
        if (mounted) setState(() => _done++);
      }
      final pdf = await PdfToolkit.assemble(const <Uint8List>[], pages);
      final name = 'book_${DateFormat('yyyyMMdd_HHmm').format(DateTime.now())}';
      final file = await PdfService.savePdfBytes(pdf, name);
      if (!mounted) return;
      showToolMessage(
        context,
        'saved_as'.tr(namedArgs: {'name': file.uri.pathSegments.last}),
      );
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      showToolMessage(
        context,
        'error_prefix'.tr(namedArgs: {'message': '$e'}),
        error: true,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('feature_book'.tr())),
      body: _photos.isEmpty
          ? ToolEmptyState(
              icon: Icons.menu_book_outlined,
              title: 'feature_book'.tr(),
              hint: 'book_hint'.tr(),
              buttonText: 'conv_pick_images'.tr(),
              onPressed: _add,
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                GridView.count(
                  crossAxisCount: 3,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  children: [
                    for (final (i, photo) in _photos.indexed)
                      Stack(
                        fit: StackFit.expand,
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Image.file(
                              photo,
                              fit: BoxFit.cover,
                              cacheWidth: 300,
                            ),
                          ),
                          Positioned(
                            top: 2,
                            right: 2,
                            child: IconButton.filledTonal(
                              iconSize: 18,
                              icon: const Icon(Icons.close_rounded),
                              onPressed: _busy
                                  ? null
                                  : () => setState(() => _photos.removeAt(i)),
                            ),
                          ),
                        ],
                      ),
                    if (!_busy)
                      OutlinedButton(
                        onPressed: _add,
                        style: OutlinedButton.styleFrom(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Icon(Icons.add_rounded, size: 32),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('book_clean'.tr()),
                  subtitle: Text('book_clean_hint'.tr()),
                  value: _clean,
                  onChanged: _busy ? null : (v) => setState(() => _clean = v),
                ),
              ],
            ),
      bottomNavigationBar: _photos.isEmpty
          ? null
          : ToolActionBar(
              label: _busy
                  ? 'conv_converting'.tr(
                      namedArgs: {
                        'done': '$_done',
                        'total': '${_photos.length}',
                      },
                    )
                  : 'create_pdf'.tr(),
              icon: Icons.picture_as_pdf_outlined,
              busy: _busy,
              onPressed: _build,
            ),
    );
  }
}
