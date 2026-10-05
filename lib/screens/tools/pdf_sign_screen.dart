import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../services/pdf/pdf_toolkit.dart';
import '../../services/pdf_service.dart';
import '../../widgets/pdf_source_sheet.dart';
import '../../widgets/signature_pad.dart';
import '../../widgets/tool_widgets.dart';

/// Imzo qo'yish: sahifa tanlanadi, imzo barmoq bilan joylanadi va kattalashtiriladi.
class PdfSignScreen extends StatefulWidget {
  const PdfSignScreen({super.key});

  @override
  State<PdfSignScreen> createState() => _PdfSignScreenState();
}

class _PdfSignScreenState extends State<PdfSignScreen> {
  PickedPdf? _pdf;
  int _pages = 0;
  int _page = 0;
  Uint8List? _signature;
  double _sigAspect = 3; // eni / bo'yi
  // Imzo o'rni sahifaga nisbatan (0..1): chap, yuqori, eni
  double _left = 0.55, _top = 0.78, _width = 0.32;
  double _pageAspect = 0.707; // ko'rinadigan sahifa eni / bo'yi
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    SignatureStore.load().then(_setSignature);
  }

  Future<void> _setSignature(Uint8List? png) async {
    if (png == null) return;
    final codec = await ui.instantiateImageCodec(png);
    final frame = await codec.getNextFrame();
    final aspect = frame.image.width / frame.image.height;
    frame.image.dispose();
    if (mounted) {
      setState(() {
        _signature = png;
        _sigAspect = aspect;
      });
    }
  }

  Future<void> _pick() async {
    final picked = await pickPdfBytes(context);
    if (picked == null) return;
    final pages = await PdfToolkit.pageCount(picked.bytes);
    if (!mounted) return;
    setState(() {
      _pdf = picked;
      _pages = pages;
      _page = pages - 1; // imzo odatda oxirgi sahifada
    });
    if (_signature == null) await _draw();
  }

  Future<void> _draw() async => _setSignature(await showSignaturePad(context));

  Future<void> _apply() async {
    final pdf = _pdf!;
    setState(() => _busy = true);
    try {
      final height = _width * _pageAspect / _sigAspect;
      final bytes = await PdfToolkit.stampImage(
        pdf.bytes,
        _page,
        _signature!,
        Rect.fromLTWH(_left, _top, _width, height),
      );
      final file = await PdfService.savePdfBytes(bytes, '${pdf.name}_signed');
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

  Widget _overlay(BuildContext context, Size size) {
    _pageAspect = size.width / size.height;
    final sig = _signature;
    if (sig == null) return const SizedBox.shrink();
    final w = _width * size.width;
    final h = w / _sigAspect;
    final cs = Theme.of(context).colorScheme;
    return Positioned(
      left: _left * size.width,
      top: _top * size.height,
      width: w,
      height: h,
      child: GestureDetector(
        onPanUpdate: (d) => setState(() {
          _left = (_left + d.delta.dx / size.width).clamp(0, 1 - _width);
          _top = (_top + d.delta.dy / size.height).clamp(
            0,
            1 - h / size.height,
          );
        }),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(color: cs.primary, width: 1.2),
                ),
                child: Image.memory(sig, fit: BoxFit.fill),
              ),
            ),
            // O'lchamni o'zgartirish tutqichi
            Positioned(
              right: -14,
              bottom: -14,
              child: GestureDetector(
                onPanUpdate: (d) => setState(() {
                  _width = (_width + d.delta.dx / size.width).clamp(
                    0.08,
                    1 - _left,
                  );
                }),
                child: Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: cs.primary,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.open_in_full_rounded,
                    size: 15,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pdf = _pdf;
    return Scaffold(
      appBar: AppBar(
        title: Text('feature_pdf_sign'.tr()),
        actions: [
          if (pdf != null)
            IconButton(
              tooltip: 'sign_draw_title'.tr(),
              icon: const Icon(Icons.draw_outlined),
              onPressed: _busy ? null : _draw,
            ),
        ],
      ),
      body: pdf == null
          ? ToolEmptyState(
              icon: Icons.draw_outlined,
              title: 'feature_pdf_sign'.tr(),
              hint: 'sign_hint'.tr(),
              buttonText: 'pick_pdf'.tr(),
              onPressed: _pick,
            )
          // Aylantiriladigan ro'yxat emas: aks holda imzoni surish harakatini
          // ro'yxat "tutib oladi". Sahifa bo'sh joyga sig'diriladi.
          : Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Column(
                children: [
                  if (_pages > 1)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.chevron_left_rounded),
                          onPressed: _page > 0
                              ? () => setState(() => _page--)
                              : null,
                        ),
                        Text(
                          '${'edit_page_label'.tr(namedArgs: {'number': '${_page + 1}'})} / $_pages',
                        ),
                        IconButton(
                          icon: const Icon(Icons.chevron_right_rounded),
                          onPressed: _page < _pages - 1
                              ? () => setState(() => _page++)
                              : null,
                        ),
                      ],
                    ),
                  Expanded(
                    child: Center(
                      child: PdfPagePreview(
                        pdf: pdf.bytes,
                        page: _page,
                        overlay: _overlay,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'sign_place_hint'.tr(),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
      bottomNavigationBar: pdf == null
          ? null
          : ToolActionBar(
              label: 'sign_btn'.tr(),
              icon: Icons.check_rounded,
              busy: _busy,
              onPressed: _signature == null ? _draw : _apply,
            ),
    );
  }
}
