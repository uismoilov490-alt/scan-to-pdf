import 'dart:math';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../services/pdf/pdf_fonts.dart';
import '../../services/pdf/pdf_toolkit.dart';
import '../../services/pdf_service.dart';
import '../../widgets/pdf_source_sheet.dart';
import '../../widgets/tool_widgets.dart';

/// Har bir sahifaga qiya, yarim shaffof matn (watermark) qo'yadi.
class PdfWatermarkScreen extends StatefulWidget {
  const PdfWatermarkScreen({super.key});

  @override
  State<PdfWatermarkScreen> createState() => _PdfWatermarkScreenState();
}

class _PdfWatermarkScreenState extends State<PdfWatermarkScreen> {
  PickedPdf? _pdf;
  late final _text = TextEditingController(text: 'watermark_default'.tr());
  double _opacity = 0.2;
  bool _busy = false;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    final picked = await pickPdfBytes(context);
    if (picked != null && mounted) setState(() => _pdf = picked);
  }

  Future<void> _apply() async {
    final pdf = _pdf!;
    final text = _text.text.trim();
    if (text.isEmpty) return;
    setState(() => _busy = true);
    try {
      final font = await PdfFonts.forText(text);
      final bytes = await PdfToolkit.watermark(
        pdf.bytes,
        text,
        font: font,
        opacity: _opacity,
      );
      final file = await PdfService.savePdfBytes(
        bytes,
        '${pdf.name}_watermark',
      );
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

  /// Ko'rinish: PDF'ga yoziladigan qiya matnning taxminiy nusxasi.
  Widget _overlay(BuildContext context, Size size) {
    final diagonal = sqrt(size.width * size.width + size.height * size.height);
    return Center(
      child: Transform.rotate(
        angle: -atan2(size.height, size.width),
        child: SizedBox(
          width: diagonal * 0.7,
          child: FittedBox(
            child: Text(
              _text.text,
              style: TextStyle(
                color: Colors.grey.shade600.withValues(alpha: _opacity),
                fontSize: 60,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pdf = _pdf;
    return Scaffold(
      appBar: AppBar(title: Text('feature_pdf_watermark'.tr())),
      body: pdf == null
          ? ToolEmptyState(
              icon: Icons.branding_watermark_outlined,
              title: 'feature_pdf_watermark'.tr(),
              hint: 'watermark_hint'.tr(),
              buttonText: 'pick_pdf'.tr(),
              onPressed: _pick,
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 260),
                    child: PdfPagePreview(pdf: pdf.bytes, overlay: _overlay),
                  ),
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: _text,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    labelText: 'watermark_text'.tr(),
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                Text('watermark_opacity'.tr()),
                Slider(
                  value: _opacity,
                  min: 0.08,
                  max: 0.6,
                  onChanged: (v) => setState(() => _opacity = v),
                ),
              ],
            ),
      bottomNavigationBar: pdf == null
          ? null
          : ToolActionBar(
              label: 'save_pdf'.tr(),
              icon: Icons.check_rounded,
              busy: _busy,
              onPressed: _text.text.trim().isEmpty ? null : _apply,
            ),
    );
  }
}
