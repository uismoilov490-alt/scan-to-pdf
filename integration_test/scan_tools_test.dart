// Qurilmada: flutter test integration_test/scan_tools_test.dart -d <qurilma>
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:integration_test/integration_test.dart';
import 'package:google_mlkit_barcode_scanning/google_mlkit_barcode_scanning.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pdfx/pdfx.dart' as pdfx;
import 'package:scan_to_pdf/services/book_splitter.dart';
import 'package:scan_to_pdf/services/photo_stamp_service.dart';

/// Oq "kitob yoyilmasi"; [gutterX] berilsa — o'sha joyda qorong'i bukish chizig'i.
img.Image spread({int? gutterX}) {
  final im = img.Image(width: 1200, height: 800)
    ..clear(img.ColorRgb8(245, 245, 240));
  if (gutterX != null) {
    img.fillRect(
      im,
      x1: gutterX - 6,
      y1: 0,
      x2: gutterX + 6,
      y2: 799,
      color: img.ColorRgb8(90, 90, 90),
    );
  }
  return im;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  test('kitob: bukish chizig\'i topiladi', () {
    final g = BookSplitter.findGutter(spread(gutterX: 650));
    expect((g - 650).abs(), lessThan(12));
  });

  test('kitob: chiziq bo\'lmasa o\'rtadan bo\'linadi', () {
    expect(BookSplitter.findGutter(spread()), 600);
  });

  test('kitob: yotiq surat 2 sahifa, tik surat 1 sahifa', () async {
    final wide = Uint8List.fromList(img.encodeJpg(spread(gutterX: 600)));
    final tall = Uint8List.fromList(
      img.encodeJpg(img.Image(width: 600, height: 900)),
    );
    final pages = await BookSplitter.split(wide);
    expect(pages.length, 2);
    expect(img.decodeJpg(pages[0])!.width, closeTo(600, 12));
    expect((await BookSplitter.split(tall)).length, 1);
  });

  test(
    'vaqt tamg\'asi: EXIF sanasi o\'qiladi va pastki o\'ngga yoziladi',
    () async {
      final photo = img.Image(width: 800, height: 600)
        ..clear(img.ColorRgb8(30, 60, 120));
      photo.exif.exifIfd['DateTimeOriginal'] = '2024:05:06 07:08:09';
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/stamp_test.jpg')
        ..writeAsBytesSync(img.encodeJpg(photo));

      final prepared = await PhotoStampService.prepare(file);
      expect(prepared.takenAt, DateTime(2024, 5, 6, 7, 8, 9));

      final out = img.decodeJpg(
        await PhotoStampService.stamp(prepared.jpeg, '06.05.2024  07:08'),
      )!;
      expect(out.width, 800);
      expect(out.height, 600);
      // To'q sariq yozuv pastki o'ng choragida bor, chap yuqorida yo'q
      bool orangeIn(int x0, int y0, int x1, int y1) {
        for (var y = y0; y < y1; y += 2) {
          for (var x = x0; x < x1; x += 2) {
            final p = out.getPixel(x, y);
            if (p.r > 200 && p.g > 120 && p.b < 80) return true;
          }
        }
        return false;
      }

      expect(orangeIn(400, 450, 800, 600), isTrue);
      expect(orangeIn(0, 0, 400, 300), isFalse);
    },
  );

  test('QR: ML Kit rasmdagi kodni o\'qiydi', () async {
    const url = 'https://scan.example/qr-test-42';
    final doc = pw.Document()
      ..addPage(
        pw.Page(
          build: (_) => pw.Center(
            child: pw.BarcodeWidget(
              barcode: pw.Barcode.qrCode(),
              data: url,
              width: 200,
              height: 200,
            ),
          ),
        ),
      );
    final pdf = await pdfx.PdfDocument.openData(await doc.save());
    final page = await pdf.getPage(1);
    final png = await page.render(
      width: page.width * 2,
      height: page.height * 2,
      format: pdfx.PdfPageImageFormat.png,
      backgroundColor: '#ffffff',
    );
    await page.close();
    await pdf.close();
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/qr_test.png')..writeAsBytesSync(png!.bytes);

    final scanner = BarcodeScanner();
    final codes = await scanner.processImage(
      InputImage.fromFilePath(file.path),
    );
    await scanner.close();
    expect(codes, isNotEmpty);
    expect(codes.first.rawValue, url);
    expect(codes.first.type, BarcodeType.url);
  });
}
