import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Ochiq kitob suratini ikki sahifaga ajratadi: o'rtadagi qorong'i "bukish"
/// chizig'ini topib, chap va o'ng yarmini alohida JPEG qiladi.
abstract final class BookSplitter {
  static const _maxSide = 2480;

  /// Yotiq (eni bo'yidan katta) surat — 2 sahifa, aks holda — 1 sahifa.
  static Future<List<Uint8List>> split(Uint8List bytes) => Isolate.run(() {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return <Uint8List>[];
    final image = img.bakeOrientation(decoded);
    if (image.width < image.height * 1.1) return [_jpg(image)];
    final gutter = findGutter(image);
    return [
      _jpg(
        img.copyCrop(image, x: 0, y: 0, width: gutter, height: image.height),
      ),
      _jpg(
        img.copyCrop(
          image,
          x: gutter,
          y: 0,
          width: image.width - gutter,
          height: image.height,
        ),
      ),
    ];
  });

  /// O'rta qismdagi (35–65%) eng qorong'i ustun; aniq chiziq bo'lmasa — o'rta.
  static int findGutter(img.Image image) {
    const sampleWidth = 300;
    final small = img.grayscale(img.copyResize(image, width: sampleWidth));
    final top = (small.height * 0.1).round();
    final bottom = (small.height * 0.9).round();
    final from = (sampleWidth * 0.35).round();
    final to = (sampleWidth * 0.65).round();

    final means = <double>[];
    for (var x = from; x < to; x++) {
      var sum = 0.0;
      for (var y = top; y < bottom; y++) {
        sum += small.getPixel(x, y).r;
      }
      means.add(sum / (bottom - top));
    }
    // Shovqinni kamaytirish uchun 5 ustunli o'rtacha
    final smooth = <double>[];
    for (var i = 0; i < means.length; i++) {
      final from = max(0, i - 2);
      final to = min(means.length, i + 3);
      smooth.add(means.sublist(from, to).reduce((x, y) => x + y) / (to - from));
    }
    var minIndex = 0;
    for (var i = 1; i < smooth.length; i++) {
      if (smooth[i] < smooth[minIndex]) minIndex = i;
    }
    final sorted = [...smooth]..sort();
    final median = sorted[sorted.length ~/ 2];
    // Bukish chizig'i atrofidan kamida 8% qorong'iroq bo'lishi kerak
    if (smooth[minIndex] > median * 0.92) return image.width ~/ 2;
    return ((from + minIndex) * image.width / sampleWidth).round();
  }

  static Uint8List _jpg(img.Image page) {
    final resized = page.width > _maxSide || page.height > _maxSide
        ? (page.width >= page.height
              ? img.copyResize(page, width: _maxSide)
              : img.copyResize(page, height: _maxSide))
        : page;
    return Uint8List.fromList(img.encodeJpg(resized, quality: 90));
  }
}
