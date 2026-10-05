import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

/// Saqlangan imzo (shaffof PNG) — har safar qayta chizish shart emas.
abstract final class SignatureStore {
  static Future<File> _file() async =>
      File('${(await getApplicationDocumentsDirectory()).path}/signature.png');

  static Future<Uint8List?> load() async {
    final f = await _file();
    return await f.exists() ? f.readAsBytes() : null;
  }

  static Future<void> save(Uint8List png) async =>
      (await _file()).writeAsBytes(png, flush: true);
}

/// Barmoq bilan imzo chizish oynasi; tayyor imzoni shaffof PNG qilib qaytaradi.
Future<Uint8List?> showSignaturePad(BuildContext context) =>
    showModalBottomSheet<Uint8List>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerLow,
      builder: (_) => const _SignaturePadSheet(),
    );

class _SignaturePadSheet extends StatefulWidget {
  const _SignaturePadSheet();

  @override
  State<_SignaturePadSheet> createState() => _SignaturePadSheetState();
}

class _SignaturePadSheetState extends State<_SignaturePadSheet> {
  static const _ink = Color(0xFF0B2A6F);
  static const _stroke = 3.2;
  final List<List<Offset>> _strokes = [];

  /// Faqat chizilgan qism, aniqroq bo'lishi uchun 3 barobar kattalikda.
  Future<Uint8List?> _export() async {
    final points = _strokes.expand((s) => s);
    if (points.isEmpty) return null;
    var bounds = Rect.fromPoints(points.first, points.first);
    for (final p in points) {
      bounds = bounds.expandToInclude(
        Rect.fromCenter(center: p, width: 1, height: 1),
      );
    }
    bounds = bounds.inflate(_stroke * 2);
    const scale = 3.0;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)
      ..scale(scale)
      ..translate(-bounds.left, -bounds.top);
    _SignaturePainter(_strokes, _ink, _stroke).paint(canvas, bounds.size);
    final image = await recorder.endRecording().toImage(
      (bounds.width * scale).ceil(),
      (bounds.height * scale).ceil(),
    );
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return data?.buffer.asUint8List();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'sign_draw_title'.tr(),
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            Container(
              height: 220,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: cs.outlineVariant),
              ),
              clipBehavior: Clip.antiAlias,
              child: GestureDetector(
                onPanStart: (d) =>
                    setState(() => _strokes.add([d.localPosition])),
                onPanUpdate: (d) =>
                    setState(() => _strokes.last.add(d.localPosition)),
                child: CustomPaint(
                  painter: _SignaturePainter(_strokes, _ink, _stroke),
                  child: _strokes.isEmpty
                      ? Center(
                          child: Text(
                            'sign_draw_hint'.tr(),
                            style: TextStyle(color: cs.onSurfaceVariant),
                          ),
                        )
                      : const SizedBox.expand(),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                TextButton.icon(
                  onPressed: _strokes.isEmpty
                      ? null
                      : () => setState(_strokes.clear),
                  icon: const Icon(Icons.delete_outline_rounded),
                  label: Text('sign_clear'.tr()),
                ),
                const Spacer(),
                FilledButton(
                  onPressed: _strokes.isEmpty
                      ? null
                      : () async {
                          final png = await _export();
                          if (png != null) await SignatureStore.save(png);
                          if (context.mounted) Navigator.pop(context, png);
                        },
                  child: Text('save'.tr()),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SignaturePainter extends CustomPainter {
  final List<List<Offset>> strokes;
  final Color color;
  final double width;

  _SignaturePainter(this.strokes, this.color, this.width);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = width
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    for (final s in strokes) {
      if (s.length == 1) {
        canvas.drawCircle(
          s.first,
          width / 2,
          paint..style = PaintingStyle.fill,
        );
        paint.style = PaintingStyle.stroke;
        continue;
      }
      final path = Path()..moveTo(s.first.dx, s.first.dy);
      for (final p in s.skip(1)) {
        path.lineTo(p.dx, p.dy);
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
