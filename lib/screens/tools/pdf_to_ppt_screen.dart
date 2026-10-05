import 'dart:typed_data';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:pdfx/pdfx.dart' as pdfx;

import '../../services/office_export.dart';
import '../../widgets/pdf_source_sheet.dart';
import '../../widgets/tool_widgets.dart';

/// PDF → PowerPoint: har bir sahifa alohida slayd (sahifa nisbatida).
class PdfToPptScreen extends StatefulWidget {
  const PdfToPptScreen({super.key});

  @override
  State<PdfToPptScreen> createState() => _PdfToPptScreenState();
}

class _PdfToPptScreenState extends State<PdfToPptScreen> {
  PickedPdf? _pdf;
  int _pages = 0;
  bool _busy = false;
  double _progress = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _pick());
  }

  Future<void> _pick() async {
    final pdf = await pickPdfBytes(context);
    if (pdf == null) return;
    final doc = await pdfx.PdfDocument.openData(pdf.bytes);
    final pages = doc.pagesCount;
    await doc.close();
    setState(() {
      _pdf = pdf;
      _pages = pages;
    });
  }

  Future<void> _convert() async {
    final pdf = _pdf!;
    setState(() {
      _busy = true;
      _progress = 0;
    });
    try {
      final doc = await pdfx.PdfDocument.openData(pdf.bytes);
      final slides = <Uint8List>[];
      var (w, h) = (0.0, 0.0);
      try {
        for (var i = 1; i <= doc.pagesCount; i++) {
          final page = await doc.getPage(i);
          try {
            if (i == 1) (w, h) = (page.width, page.height);
            // Slayd uchun ~1600px kenglik yetarli: aniq, lekin fayl yengil
            final scale = 1600 / page.width;
            final img = await page.render(
              width: page.width * scale,
              height: page.height * scale,
              format: pdfx.PdfPageImageFormat.jpeg,
              backgroundColor: '#ffffff',
              quality: 88,
            );
            if (img != null) slides.add(img.bytes);
          } finally {
            await page.close();
          }
          if (mounted) setState(() => _progress = i / doc.pagesCount);
        }
      } finally {
        await doc.close();
      }
      final file = await OfficeExport.save(
        OfficeExport.pptx(slides, widthPt: w, heightPt: h),
        pdf.name.replaceAll(RegExp(r'\.pdf$', caseSensitive: false), ''),
        'pptx',
      );
      if (mounted) await showSavedFileSheet(context, file);
    } catch (e) {
      if (mounted) showToolMessage(context, e.toString(), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pdf = _pdf;
    return Scaffold(
      appBar: AppBar(title: Text('feature_pdf_to_ppt'.tr())),
      body: pdf == null
          ? ToolEmptyState(
              icon: Icons.slideshow_rounded,
              title: 'feature_pdf_to_ppt'.tr(),
              hint: 'ppt_hint'.tr(),
              buttonText: 'pick_pdf'.tr(),
              onPressed: _pick,
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                ToolFileCard(name: pdf.name, pages: _pages),
                if (_busy) ...[
                  const SizedBox(height: 24),
                  LinearProgressIndicator(value: _progress),
                ],
              ],
            ),
      bottomNavigationBar: pdf == null
          ? null
          : ToolActionBar(
              label: 'conv_convert'.tr(),
              icon: Icons.slideshow_rounded,
              busy: _busy,
              onPressed: _convert,
            ),
    );
  }
}
