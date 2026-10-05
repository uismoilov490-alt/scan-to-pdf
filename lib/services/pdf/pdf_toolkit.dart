import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' show Offset, Rect, Size;

import 'package:image/image.dart' as img;
import 'package:syncfusion_flutter_pdf/pdf.dart';

/// Yangi hujjatdagi bitta sahifa: mavjud PDF sahifasi yoki rasm.
sealed class PageSource {
  /// Foydalanuvchi qo'shimcha aylantirishi (soat yo'nalishida, 90° qadamlar)
  final int quarterTurns;

  const PageSource({this.quarterTurns = 0});

  /// Shu sahifa, lekin boshqa burilish bilan.
  PageSource rotated(int turns) => switch (this) {
    PdfPageRef(:final pdf, :final page) => PdfPageRef(
      pdf,
      page,
      quarterTurns: turns,
    ),
    ImagePage(:final bytes) => ImagePage(bytes, quarterTurns: turns),
  };
}

/// [sources]dagi [pdf]-indeksli faylning [page]-sahifasi (0 dan).
final class PdfPageRef extends PageSource {
  final int pdf;
  final int page;

  const PdfPageRef(this.pdf, this.page, {super.quarterTurns});
}

/// JPEG/PNG rasm — A4 sahifaga sig'diriladi.
final class ImagePage extends PageSource {
  final Uint8List bytes;

  const ImagePage(this.bytes, {super.quarterTurns});
}

enum PageNumberPosition { bottomCenter, bottomRight, topRight }

class PdfPasswordException implements Exception {
  /// true — parol umuman berilmagan, false — berilgan parol noto'g'ri
  final bool required;

  const PdfPasswordException({required this.required});
}

/// PDF bilan sahifalarni rasmga aylantirmasdan ishlash: matn, vektor grafika
/// va sifat saqlanadi. Og'ir ishlar alohida isolate'da bajariladi — UI qotmaydi.
abstract final class PdfToolkit {
  static const _a4 = Size(595.28, 841.89);

  /// A4 300 dpi kengligi — bundan katta rasm PDF'da sezilarli farq bermaydi
  static const _maxImageSide = 2480;

  /// Istalgan rasmni (JPG/PNG/WebP, kamera fotosi) PDF sahifasiga tayyorlaydi:
  /// EXIF burilishini qo'llaydi, shaffof fonni oq qiladi, haddan katta
  /// rasmni kichraytiradi va JPEG qiladi. O'qib bo'lmasa — null.
  static Future<Uint8List?> prepareImage(Uint8List bytes) => Isolate.run(() {
    var image = img.decodeImage(bytes);
    if (image == null) return null;
    image = img.bakeOrientation(image);
    if (image.hasAlpha) {
      final white = img.Image(width: image.width, height: image.height)
        ..clear(img.ColorRgb8(255, 255, 255));
      image = img.compositeImage(white, image);
    }
    if (image.width > _maxImageSide || image.height > _maxImageSide) {
      image = image.width >= image.height
          ? img.copyResize(image, width: _maxImageSide)
          : img.copyResize(image, height: _maxImageSide);
    }
    return Uint8List.fromList(img.encodeJpg(image, quality: 90));
  });

  /// Sahifalar soni. Parol kerak bo'lsa [PdfPasswordException].
  static Future<int> pageCount(Uint8List pdf, {String? password}) =>
      Isolate.run(() {
        final doc = _open(pdf, password);
        try {
          return doc.pages.count;
        } finally {
          doc.dispose();
        }
      });

  /// Parol bilan himoyalanganmi (ochish uchun parol talab qiladimi).
  static Future<bool> needsPassword(Uint8List pdf) => Isolate.run(() {
    try {
      _open(pdf, null).dispose();
      return false;
    } on PdfPasswordException {
      return true;
    }
  });

  /// [pages] ro'yxati bo'yicha yangi PDF yig'adi: birlashtirish, tartiblash,
  /// o'chirish, aylantirish va rasm qo'shish — hammasi shu bitta amal.
  static Future<Uint8List> assemble(
    List<Uint8List> sources,
    List<PageSource> pages, {
    List<String?>? passwords,
  }) => Isolate.run(() => _assemble(sources, pages, passwords));

  /// Bir nechta PDF'ni ketma-ket birlashtiradi.
  static Future<Uint8List> merge(List<Uint8List> pdfs) async {
    final pages = <PageSource>[];
    for (var i = 0; i < pdfs.length; i++) {
      final count = await pageCount(pdfs[i]);
      for (var p = 0; p < count; p++) {
        pages.add(PdfPageRef(i, p));
      }
    }
    return assemble(pdfs, pages);
  }

  /// PDF'ni bo'laklarga ajratadi; har bir [ranges] elementi — sahifa
  /// indekslari (0 dan) ro'yxati, natijada shuncha alohida PDF.
  static Future<List<Uint8List>> split(Uint8List pdf, List<List<int>> ranges) =>
      Isolate.run(
        () => [
          for (final r in ranges)
            _assemble([pdf], [for (final p in r) PdfPageRef(0, p)], null),
        ],
      );

  /// Ochish uchun parol qo'yadi (AES-256).
  static Future<Uint8List> protect(Uint8List pdf, String password) =>
      Isolate.run(() {
        final doc = _open(pdf, null);
        try {
          doc.security
            ..algorithm = PdfEncryptionAlgorithm.aesx256Bit
            ..userPassword = password
            ..ownerPassword = password;
          return Uint8List.fromList(doc.saveSync());
        } finally {
          doc.dispose();
        }
      });

  /// Parolni olib tashlaydi (to'g'ri parol bilan): sahifalar himoyasiz
  /// yangi hujjatga ko'chiriladi.
  static Future<Uint8List> unlock(Uint8List pdf, String password) =>
      Isolate.run(() {
        final doc = _open(pdf, password);
        final count = doc.pages.count;
        doc.dispose();
        return _assemble(
          [pdf],
          [for (var i = 0; i < count; i++) PdfPageRef(0, i)],
          [password],
        );
      });

  /// Hujjatdagi matn (skanerlangan PDF'da bo'sh bo'ladi — u holda OCR kerak).
  static Future<String> extractText(Uint8List pdf, {String? password}) =>
      Isolate.run(() {
        final doc = _open(pdf, password);
        try {
          return PdfTextExtractor(doc).extractText();
        } finally {
          doc.dispose();
        }
      });

  /// Har bir sahifa markaziga qiya, yarim shaffof [text] yozadi.
  /// [font] — TTF baytlari (lotin-1'dan tashqari yozuvlar uchun shart).
  static Future<Uint8List> watermark(
    Uint8List pdf,
    String text, {
    Uint8List? font,
    double opacity = 0.2,
  }) => _edit(pdf, (doc) {
    for (var i = 0; i < doc.pages.count; i++) {
      _drawVisual(doc.pages[i], (g, size) {
        // Matn sahifa diagonalining ~70% ini egallaydi
        final diagonal = sqrt(
          size.width * size.width + size.height * size.height,
        );
        final probe = _font(font, 100);
        final width100 = probe.measureString(text).width;
        final pdfFont = _font(
          font,
          (diagonal * 0.7 / width100 * 100).clamp(18, 160),
        );
        final m = pdfFont.measureString(text);
        g
          ..save()
          ..setTransparency(opacity)
          ..translateTransform(size.width / 2, size.height / 2)
          ..rotateTransform(-atan2(size.height, size.width) * 180 / pi)
          ..drawString(
            text,
            pdfFont,
            brush: PdfSolidBrush(PdfColor(120, 120, 120)),
            bounds: Rect.fromLTWH(
              -m.width / 2,
              -m.height / 2,
              m.width,
              m.height,
            ),
          )
          ..restore();
      });
    }
  });

  /// Sahifa raqamlarini qo'yadi ("3" yoki "3 / 10").
  static Future<Uint8List> pageNumbers(
    Uint8List pdf, {
    PageNumberPosition position = PageNumberPosition.bottomCenter,
    bool withTotal = true,
  }) => _edit(pdf, (doc) {
    final total = doc.pages.count;
    final font = PdfStandardFont(PdfFontFamily.helvetica, 11);
    for (var i = 0; i < total; i++) {
      final text = withTotal ? '${i + 1} / $total' : '${i + 1}';
      final m = font.measureString(text);
      _drawVisual(doc.pages[i], (g, size) {
        const margin = 22.0;
        final x = switch (position) {
          PageNumberPosition.bottomCenter => (size.width - m.width) / 2,
          _ => size.width - margin - m.width,
        };
        final y = position == PageNumberPosition.topRight
            ? margin
            : size.height - margin - m.height;
        g.drawString(
          text,
          font,
          brush: PdfSolidBrush(PdfColor(90, 90, 90)),
          bounds: Rect.fromLTWH(x, y, m.width, m.height),
        );
      });
    }
  });

  /// [page]-sahifaga (0 dan) rasmni (masalan imzo PNG) qo'yadi. [area] —
  /// sahifaning ko'rinadigan o'lchamiga nisbatan 0..1 koordinatalar.
  static Future<Uint8List> stampImage(
    Uint8List pdf,
    int page,
    Uint8List image,
    Rect area,
  ) => _edit(pdf, (doc) {
    _drawVisual(doc.pages[page], (g, size) {
      g.drawImage(
        PdfBitmap(image),
        Rect.fromLTWH(
          area.left * size.width,
          area.top * size.height,
          area.width * size.width,
          area.height * size.height,
        ),
      );
    });
  });

  // ── Ichki ──────────────────────────────────────────────────────────────

  /// Hujjatni ochib, [change] bilan o'zgartiradi va saqlaydi (isolate'da).
  static Future<Uint8List> _edit(
    Uint8List pdf,
    void Function(PdfDocument doc) change,
  ) => Isolate.run(() {
    final doc = _open(pdf, null);
    try {
      change(doc);
      return Uint8List.fromList(doc.saveSync());
    } finally {
      doc.dispose();
    }
  });

  static PdfFont _font(Uint8List? ttf, double size) => ttf == null
      ? PdfStandardFont(PdfFontFamily.helvetica, size)
      : PdfTrueTypeFont(ttf, size);

  /// Sahifaga foydalanuvchi ko'rib turgan yo'nalishda chizish: sahifa /Rotate
  /// bilan burilgan bo'lsa, koordinatalar shunga moslab aylantiriladi —
  /// (0,0) doim ko'rinadigan sahifaning chap-yuqori burchagi.
  static void _drawVisual(
    PdfPage page,
    void Function(PdfGraphics g, Size visualSize) draw,
  ) {
    final g = page.graphics;
    final w = page.size.width;
    final h = page.size.height;
    g.save();
    final Size visual;
    switch (page.rotation) {
      case PdfPageRotateAngle.rotateAngle90:
        g
          ..translateTransform(0, h)
          ..rotateTransform(-90);
        visual = Size(h, w);
      case PdfPageRotateAngle.rotateAngle180:
        g
          ..translateTransform(w, h)
          ..rotateTransform(180);
        visual = Size(w, h);
      case PdfPageRotateAngle.rotateAngle270:
        g
          ..translateTransform(w, 0)
          ..rotateTransform(90);
        visual = Size(h, w);
      case PdfPageRotateAngle.rotateAngle0:
        visual = Size(w, h);
    }
    draw(g, visual);
    g.restore();
  }

  static PdfDocument _open(Uint8List bytes, String? password) {
    try {
      // Faqat "egasi paroli" bo'lgan hujjatlar bo'sh parol bilan ochiladi
      return PdfDocument(inputBytes: bytes, password: password ?? '');
    } on ArgumentError catch (e) {
      if (e.name == 'password') {
        throw PdfPasswordException(
          required: password == null || password.isEmpty,
        );
      }
      rethrow;
    }
  }

  static Uint8List _assemble(
    List<Uint8List> sources,
    List<PageSource> pages,
    List<String?>? passwords,
  ) {
    final docs = <int, PdfDocument>{};
    PdfDocument source(int i) =>
        docs[i] ??= _open(sources[i], passwords == null ? null : passwords[i]);

    final out = PdfDocument();
    final pager = _Pager(out);
    // Sahifa burilishi yangi hujjatda faqat qayta ochilgandan keyin
    // o'rnatiladi (kutubxona cheklovi) — shu sababli alohida yig'amiz.
    final turns = <int>[];
    try {
      for (final p in pages) {
        switch (p) {
          case PdfPageRef(:final pdf, :final page):
            final src = source(pdf).pages[page];
            pager
                .add(src.size)
                .graphics
                .drawPdfTemplate(src.createTemplate(), Offset.zero);
            turns.add(src.rotation.index + p.quarterTurns);
          case ImagePage(:final bytes):
            final image = PdfBitmap(bytes);
            final landscape = image.width > image.height;
            final size = landscape ? Size(_a4.height, _a4.width) : _a4;
            pager.add(size).graphics.drawImage(image, _fit(image, size));
            turns.add(p.quarterTurns);
        }
      }
      final built = out.saveSync();
      if (turns.every((t) => t % 4 == 0)) return Uint8List.fromList(built);
      return _applyRotation(built, turns);
    } finally {
      out.dispose();
      for (final d in docs.values) {
        d.dispose();
      }
    }
  }

  static Uint8List _applyRotation(List<int> bytes, List<int> turns) {
    final doc = PdfDocument(inputBytes: bytes);
    try {
      for (var i = 0; i < turns.length; i++) {
        doc.pages[i].rotation = PdfPageRotateAngle.values[turns[i] % 4];
      }
      return Uint8List.fromList(doc.saveSync());
    } finally {
      doc.dispose();
    }
  }

  /// Rasmni sahifa markaziga nisbatini saqlab sig'diradi.
  static Rect _fit(PdfBitmap image, Size page) {
    final scale = [
      page.width / image.width,
      page.height / image.height,
    ].reduce((a, b) => a < b ? a : b);
    final w = image.width * scale;
    final h = image.height * scale;
    return Rect.fromLTWH((page.width - w) / 2, (page.height - h) / 2, w, h);
  }
}

/// Sahifalarni o'z o'lchami va yo'nalishi bilan qo'shadi. Kutubxonada o'lcham
/// faqat birinchi sahifagacha o'zgaradi va har doim tik qilib olinadi, shuning
/// uchun har bir yangi o'lcham — yangi bo'lim (bir xil o'lchamlar bir bo'limda).
class _Pager {
  final PdfDocument _doc;
  PdfSection? _section;
  Size? _size;

  _Pager(this._doc);

  PdfPage add(Size size) {
    if (_section == null || size != _size) {
      _size = size;
      _section = _doc.sections!.add()
        ..pageSettings.margins.all = 0
        ..pageSettings.orientation = size.width > size.height
            ? PdfPageOrientation.landscape
            : PdfPageOrientation.portrait
        ..pageSettings.size = size;
    }
    return _section!.pages.add();
  }
}
