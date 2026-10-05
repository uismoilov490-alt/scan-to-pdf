import 'dart:io';
import 'dart:typed_data';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:pdfx/pdfx.dart' as pdfx;
import 'package:share_plus/share_plus.dart';

/// Vosita ekranlari uchun umumiy bo'laklar — har bir ekran ixcham qoladi.

/// Hali fayl tanlanmagan holat: katta belgi, izoh va tanlash tugmasi.
class ToolEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String hint;
  final String buttonText;
  final VoidCallback onPressed;

  const ToolEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.hint,
    required this.buttonText,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                color: cs.primaryContainer,
                borderRadius: BorderRadius.circular(28),
              ),
              child: Icon(icon, size: 48, color: cs.primary),
            ),
            const SizedBox(height: 20),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              hint,
              textAlign: TextAlign.center,
              style: TextStyle(color: cs.onSurfaceVariant, height: 1.4),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: onPressed,
              icon: const Icon(Icons.add_rounded),
              label: Text(buttonText),
            ),
          ],
        ),
      ),
    );
  }
}

/// Tanlangan PDF kartasi: nomi, sahifalar soni va o'ng tomonda amal.
class ToolFileCard extends StatelessWidget {
  final String name;
  final int? pages;
  final Widget? trailing;

  const ToolFileCard({
    super.key,
    required this.name,
    this.pages,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.surfaceContainerLow,
      borderRadius: BorderRadius.circular(18),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: const Color(0xFFFF3B30).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.picture_as_pdf_outlined,
                color: Color(0xFFFF3B30),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$name.pdf',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                  ),
                  if (pages != null)
                    Text(
                      'pages_count'.tr(namedArgs: {'count': '$pages'}),
                      style: TextStyle(
                        color: cs.onSurfaceVariant,
                        fontSize: 13,
                      ),
                    ),
                ],
              ),
            ),
            ?trailing,
          ],
        ),
      ),
    );
  }
}

/// Pastdagi asosiy amal tugmasi (ish ketayotganda aylanuvchi belgi).
class ToolActionBar extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool busy;
  final VoidCallback? onPressed;

  const ToolActionBar({
    super.key,
    required this.label,
    required this.icon,
    required this.onPressed,
    this.busy = false,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      minimum: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: SizedBox(
        height: 54,
        child: FilledButton.icon(
          onPressed: busy ? null : onPressed,
          icon: busy
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                )
              : Icon(icon),
          label: Text(label, style: const TextStyle(fontSize: 16)),
        ),
      ),
    );
  }
}

/// Muvaffaqiyat/xato xabari.
void showToolMessage(BuildContext context, String text, {bool error = false}) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(text),
      backgroundColor: error ? Colors.red : null,
      behavior: SnackBarBehavior.floating,
    ),
  );
}

/// PDF sahifasining rasmini chizib ko'rsatadi (tanlangan sahifa almashsa
/// qayta chiziladi). [overlay] — sahifa ustiga qo'yiladigan qatlam
/// (o'lchami sahifa rasmi bilan bir xil bo'ladi).
class PdfPagePreview extends StatefulWidget {
  final Uint8List pdf;
  final int page;
  final Widget Function(BuildContext context, Size size)? overlay;

  const PdfPagePreview({
    super.key,
    required this.pdf,
    this.page = 0,
    this.overlay,
  });

  @override
  State<PdfPagePreview> createState() => _PdfPagePreviewState();
}

class _PdfPagePreviewState extends State<PdfPagePreview> {
  Uint8List? _image;
  double _aspect = 0.707;

  @override
  void initState() {
    super.initState();
    _render();
  }

  @override
  void didUpdateWidget(PdfPagePreview old) {
    super.didUpdateWidget(old);
    if (old.page != widget.page || old.pdf != widget.pdf) _render();
  }

  Future<void> _render() async {
    final doc = await pdfx.PdfDocument.openData(widget.pdf);
    try {
      final page = await doc.getPage(widget.page + 1);
      // Ekran uchun ~900 px kenglik yetarli
      final scale = 900 / page.width;
      final r = await page.render(
        width: page.width * scale,
        height: page.height * scale,
        format: pdfx.PdfPageImageFormat.jpeg,
        backgroundColor: '#ffffff',
        quality: 85,
      );
      await page.close();
      if (r != null && mounted) {
        setState(() {
          _image = r.bytes;
          _aspect =
              (r.width ?? page.width.round()) /
              (r.height ?? page.height.round());
        });
      }
    } finally {
      await doc.close();
    }
  }

  @override
  Widget build(BuildContext context) {
    final image = _image;
    return AspectRatio(
      aspectRatio: _aspect,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.12),
              blurRadius: 12,
            ),
          ],
        ),
        child: image == null
            ? const Center(child: CircularProgressIndicator())
            : LayoutBuilder(
                builder: (context, c) => Stack(
                  children: [
                    Positioned.fill(
                      child: Image.memory(
                        image,
                        fit: BoxFit.fill,
                        gaplessPlayback: true,
                      ),
                    ),
                    if (widget.overlay != null)
                      widget.overlay!(context, c.biggest),
                  ],
                ),
              ),
      ),
    );
  }
}

/// Saqlangan (PDF bo'lmagan) fayl uchun: ochish yoki ulashish.
Future<void> showSavedFileSheet(BuildContext context, File file) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(
              Icons.check_circle_rounded,
              color: Color(0xFF34C759),
              size: 48,
            ),
            const SizedBox(height: 12),
            Text(
              'saved_as'.tr(namedArgs: {'name': p.basename(file.path)}),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: () => OpenFilex.open(file.path),
              icon: const Icon(Icons.open_in_new_rounded),
              label: Text('open_file'.tr()),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => Share.shareXFiles([XFile(file.path)]),
              icon: const Icon(Icons.share_outlined),
              label: Text('share'.tr()),
            ),
          ],
        ),
      ),
    ),
  );
}
