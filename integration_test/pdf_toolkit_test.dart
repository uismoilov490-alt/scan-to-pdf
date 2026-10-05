// Qurilmada ishga tushiriladi: flutter test integration_test/pdf_toolkit_test.dart
import 'dart:typed_data';
import 'dart:ui' show Rect, Size;

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:integration_test/integration_test.dart';
import 'package:scan_to_pdf/screens/tools/pdf_split_screen.dart';
import 'package:scan_to_pdf/services/pdf/pdf_fonts.dart';
import 'package:scan_to_pdf/services/pdf/pdf_toolkit.dart';
import 'package:pdfx/pdfx.dart' as pdfx;
import 'package:syncfusion_flutter_pdf/pdf.dart';

/// Har bir sahifasida "<prefix> N" matni bo'lgan PDF.
Uint8List makePdf(String prefix, int pages) {
  final doc = PdfDocument();
  for (var i = 1; i <= pages; i++) {
    doc.pages.add().graphics.drawString(
      '$prefix $i',
      PdfStandardFont(PdfFontFamily.helvetica, 24),
      bounds: const Rect.fromLTWH(40, 40, 400, 40),
    );
  }
  final bytes = Uint8List.fromList(doc.saveSync());
  doc.dispose();
  return bytes;
}

List<int> rotations(Uint8List pdf) {
  final doc = PdfDocument(inputBytes: pdf);
  final r = [
    for (var i = 0; i < doc.pages.count; i++) doc.pages[i].rotation.index,
  ];
  doc.dispose();
  return r;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  final a = makePdf('Alpha', 2);
  final b = makePdf('Beta', 3);

  test('birlashtirish: sahifalar soni va matn saqlanadi', () async {
    final merged = await PdfToolkit.merge([a, b]);
    expect(await PdfToolkit.pageCount(merged), 5);
    final text = await PdfToolkit.extractText(merged);
    for (final s in ['Alpha 1', 'Alpha 2', 'Beta 1', 'Beta 3']) {
      expect(text, contains(s));
    }
    // Tartib saqlangan
    expect(text.indexOf('Alpha 2') < text.indexOf('Beta 1'), isTrue);
  });

  test('tartiblash, o\'chirish va aylantirish', () async {
    final out = await PdfToolkit.assemble(
      [a, b],
      const [
        PdfPageRef(1, 2, quarterTurns: 1),
        PdfPageRef(0, 0),
        PdfPageRef(1, 0, quarterTurns: 2),
      ],
    );
    expect(await PdfToolkit.pageCount(out), 3);
    final text = await PdfToolkit.extractText(out);
    expect(text.indexOf('Beta 3') < text.indexOf('Alpha 1'), isTrue);
    expect(text, isNot(contains('Alpha 2')));
    expect(rotations(out), [1, 0, 2]);
  });

  test('rasm sahifa: landshaft rasm landshaft sahifaga', () async {
    final png = Uint8List.fromList(
      img.encodePng(img.Image(width: 300, height: 200)),
    );
    final out = await PdfToolkit.assemble(
      [a],
      [PdfPageRef(0, 0), ImagePage(png)],
    );
    final doc = PdfDocument(inputBytes: out);
    expect(doc.pages.count, 2);
    expect(doc.pages[1].size.width > doc.pages[1].size.height, isTrue);
    doc.dispose();
  });

  test('turli o\'lchamli sahifalar o\'z o\'lchamini saqlaydi', () async {
    final wide = PdfDocument();
    wide.pageSettings
      ..orientation = PdfPageOrientation.landscape
      ..size = const Size(600, 300);
    wide.pages.add();
    final wideBytes = Uint8List.fromList(wide.saveSync());
    wide.dispose();

    final out = await PdfToolkit.merge([a, wideBytes, a]);
    final doc = PdfDocument(inputBytes: out);
    final sizes = [for (var i = 0; i < doc.pages.count; i++) doc.pages[i].size];
    doc.dispose();
    expect(sizes.length, 5);
    expect(sizes[2], const Size(600, 300));
    expect(sizes[0].height > sizes[0].width, isTrue);
    expect(sizes[4], sizes[0]);
  });

  test('sahifa oraliqlarini o\'qish', () {
    expect(parsePageRanges('1-3, 5,7 - 8', 10), [
      [0, 1, 2],
      [4],
      [6, 7],
    ]);
    expect(parsePageRanges('2;4', 4), [
      [1],
      [3],
    ]);
    expect(parsePageRanges('', 5), isNull);
    expect(parsePageRanges('0-2', 5), isNull);
    expect(parsePageRanges('3-1', 5), isNull);
    expect(parsePageRanges('1-6', 5), isNull);
    expect(parsePageRanges('a', 5), isNull);
  });

  test('ajratish', () async {
    final parts = await PdfToolkit.split(b, const [
      [0],
      [1, 2],
    ]);
    expect(parts.length, 2);
    expect(await PdfToolkit.pageCount(parts[0]), 1);
    expect(
      await PdfToolkit.extractText(parts[1]),
      allOf(contains('Beta 2'), contains('Beta 3')),
    );
  });

  test('parol qo\'yish, noto\'g\'ri parol, parolni olib tashlash', () async {
    final locked = await PdfToolkit.protect(a, 'sir123');
    expect(await PdfToolkit.needsPassword(locked), isTrue);
    expect(await PdfToolkit.needsPassword(a), isFalse);
    await expectLater(
      PdfToolkit.pageCount(locked, password: 'xato'),
      throwsA(
        isA<PdfPasswordException>().having(
          (e) => e.required,
          'required',
          false,
        ),
      ),
    );
    expect(await PdfToolkit.pageCount(locked, password: 'sir123'), 2);
    final open = await PdfToolkit.unlock(locked, 'sir123');
    expect(await PdfToolkit.needsPassword(open), isFalse);
    expect(await PdfToolkit.extractText(open), contains('Alpha 2'));
  });

  test('tezlik: 200 sahifani birlashtirish', () async {
    final big = makePdf('Big', 100);
    final sw = Stopwatch()..start();
    final merged = await PdfToolkit.merge([big, big]);
    sw.stop();
    expect(await PdfToolkit.pageCount(merged), 200);
    // ignore: avoid_print
    print(
      '[perf] 200 sahifa: ${sw.elapsedMilliseconds} ms, ${merged.length ~/ 1024} KB',
    );
  });

  // Burilgan sahifada ham rasm foydalanuvchi ko'radigan joyga tushishi kerak:
  // sahifa telefonda chiziladi va qizil piksellar o'rni tekshiriladi.
  Future<img.Image> renderFirst(Uint8List pdf) async {
    final doc = await pdfx.PdfDocument.openData(pdf);
    final page = await doc.getPage(1);
    final r = await page.render(
      width: page.width,
      height: page.height,
      format: pdfx.PdfPageImageFormat.png,
      backgroundColor: '#ffffff',
    );
    await page.close();
    await doc.close();
    return img.decodePng(r!.bytes)!;
  }

  for (final turns in [0, 1, 2, 3]) {
    test(
      'imzo burilgan sahifada ham chap-yuqorida (${turns * 90} gradus)',
      () async {
        final rotated = await PdfToolkit.assemble(
          [a],
          [PdfPageRef(0, 0, quarterTurns: turns)],
        );
        final red = img.Image(width: 40, height: 40)
          ..clear(img.ColorRgb8(255, 0, 0));
        final out = await PdfToolkit.stampImage(
          rotated,
          0,
          Uint8List.fromList(img.encodePng(red)),
          const Rect.fromLTWH(0, 0, 0.2, 0.2),
        );
        final im = await renderFirst(out);
        var sx = 0.0, sy = 0.0, n = 0;
        for (var y = 0; y < im.height; y += 2) {
          for (var x = 0; x < im.width; x += 2) {
            final p = im.getPixel(x, y);
            if (p.r > 200 && p.g < 80 && p.b < 80) {
              sx += x;
              sy += y;
              n++;
            }
          }
        }
        expect(n, greaterThan(50));
        expect(sx / n / im.width, lessThan(0.2));
        expect(sy / n / im.height, lessThan(0.2));
      },
    );
  }

  test('sahifa raqami va watermark matnni buzmaydi', () async {
    final numbered = await PdfToolkit.pageNumbers(b);
    final text = await PdfToolkit.extractText(numbered);
    expect(
      text,
      allOf(contains('Beta 1'), contains('1 / 3'), contains('3 / 3')),
    );
    final marked = await PdfToolkit.watermark(numbered, 'COPY');
    expect(await PdfToolkit.pageCount(marked), 3);
    expect(await PdfToolkit.extractText(marked), contains('COPY'));
  });

  test('kirill watermark (Noto shrifti bilan)', () async {
    const text = 'КОПИЯ';
    final font = await PdfFonts.forText(text);
    expect(font, isNotNull);
    final marked = await PdfToolkit.watermark(a, text, font: font);
    expect(await PdfToolkit.extractText(marked), contains(text));
  });
}
