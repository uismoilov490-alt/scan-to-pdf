import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:opencv_dart/opencv_dart.dart' as cv;

/// Natija ko'rinishi: rangli skaner, kulrang yoki oq-qora (matn uchun eng tiniq).
enum CleanMode { color, gray, bw }

/// Telefon kamerasi bilan olingan yoki qiyshiq skanerlangan hujjatni
/// skaner apparatidagidek ko'rinishga keltiradi (OpenCV, telefonning o'zida):
///  1) varaq chetlarini topib, perspektivani to'g'rilaydi va fonni kesadi;
///  2) soya, dog' va notekis yorug'likni yo'qotib, fonni oqartiradi;
///  3) tanlangan rejimga ko'ra rang/kulrang/oq-qora qiladi.
class DocumentCleaner {
  /// Alohida isolate'da ishlaydi — interfeys qotmaydi.
  static Future<Uint8List?> clean(Uint8List imageBytes, {CleanMode mode = CleanMode.color, bool crop = true}) {
    return Isolate.run(() => cleanSync(imageBytes, mode: mode, crop: crop));
  }

  static Uint8List? cleanSync(Uint8List imageBytes, {CleanMode mode = CleanMode.color, bool crop = true}) {
    final src = cv.imdecode(imageBytes, cv.IMREAD_COLOR);
    if (src.isEmpty) return null;

    var doc = (crop ? _warpToPage(src) : null) ?? src;
    doc = _limitSize(doc, 2480);

    final cv.Mat out = switch (mode) {
      CleanMode.color => _whitenColor(doc),
      CleanMode.gray => _whiten(cv.cvtColor(doc, cv.COLOR_BGR2GRAY)),
      // Butun sahifa bo'yicha yagona chegara (Otsu): faqat haqiqatan to'q narsa — matn —
      // qora bo'ladi; soya/dog' chetlari kabi xira izlar oq bo'lib ketadi.
      CleanMode.bw => cv.threshold(
          _whiten(cv.cvtColor(doc, cv.COLOR_BGR2GRAY)),
          0,
          255,
          cv.THRESH_BINARY | cv.THRESH_OTSU,
        ).$2,
    };

    final (ok, bytes) = cv.imencode('.jpg', out, params: cv.VecI32.fromList([cv.IMWRITE_JPEG_QUALITY, 92]));
    return ok ? bytes : null;
  }

  /// Varaqning 4 burchagini topib, uni to'g'ri to'rtburchakka "yoyadi".
  /// Varaq topilmasa (masalan, rasm allaqachon kesilgan) — null.
  static cv.Mat? _warpToPage(cv.Mat src) {
    final longSide = math.max(src.cols, src.rows);
    final scale = longSide > 1000 ? 1000 / longSide : 1.0;
    final small = scale < 1
        ? cv.resize(src, ((src.cols * scale).round(), (src.rows * scale).round()), interpolation: cv.INTER_AREA)
        : src;

    final gray = cv.cvtColor(small, cv.COLOR_BGR2GRAY);
    final blurred = cv.gaussianBlur(gray, (5, 5), 0);
    final edges = cv.canny(blurred, 50, 150);
    final kernel = cv.getStructuringElement(cv.MORPH_RECT, (3, 3));
    final closed = cv.dilate(edges, kernel, iterations: 2);

    final (contours, _) = cv.findContours(closed, cv.RETR_LIST, cv.CHAIN_APPROX_SIMPLE);
    final minArea = small.cols * small.rows * 0.2;
    List<cv.Point>? best;
    var bestArea = 0.0;
    for (final c in contours) {
      final area = cv.contourArea(c);
      if (area < minArea || area <= bestArea) continue;
      final approx = cv.approxPolyDP(c, 0.02 * cv.arcLength(c, true), true);
      if (approx.length == 4) {
        best = approx.toList();
        bestArea = area;
      }
    }
    if (best == null) return null;

    // Kichraytirilgan rasmdagi nuqtalarni asl o'lchamga qaytaramiz
    final pts = best.map((p) => (p.x / scale, p.y / scale)).toList();
    // Tartib: yuqori-chap, yuqori-o'ng, past-o'ng, past-chap
    final tl = pts.reduce((a, b) => a.$1 + a.$2 < b.$1 + b.$2 ? a : b);
    final br = pts.reduce((a, b) => a.$1 + a.$2 > b.$1 + b.$2 ? a : b);
    final tr = pts.reduce((a, b) => a.$2 - a.$1 < b.$2 - b.$1 ? a : b);
    final bl = pts.reduce((a, b) => a.$2 - a.$1 > b.$2 - b.$1 ? a : b);

    double dist((double, double) a, (double, double) b) =>
        math.sqrt(math.pow(a.$1 - b.$1, 2) + math.pow(a.$2 - b.$2, 2));
    final width = math.max(dist(tl, tr), dist(bl, br)).round();
    final height = math.max(dist(tl, bl), dist(tr, br)).round();
    if (width < 100 || height < 100) return null;

    cv.Point pt((double, double) p) => cv.Point(p.$1.round(), p.$2.round());
    final from = cv.VecPoint.fromList([pt(tl), pt(tr), pt(br), pt(bl)]);
    final to = cv.VecPoint.fromList([
      cv.Point(0, 0),
      cv.Point(width - 1, 0),
      cv.Point(width - 1, height - 1),
      cv.Point(0, height - 1),
    ]);
    final m = cv.getPerspectiveTransform(from, to);
    final warped = cv.warpPerspective(src, m, (width, height));
    // Varaq chetidagi stol/soya qoldig'i — har tomondan 1.5% kesiladi
    final mx = (width * 0.015).round();
    final my = (height * 0.015).round();
    return warped.region(cv.Rect(mx, my, width - 2 * mx, height - 2 * my)).clone();
  }

  static cv.Mat _limitSize(cv.Mat img, int maxSide) {
    final longSide = math.max(img.cols, img.rows);
    if (longSide <= maxSide) return img;
    final s = maxSide / longSide;
    return cv.resize(img, ((img.cols * s).round(), (img.rows * s).round()), interpolation: cv.INTER_AREA);
  }

  /// Soya va dog'ni yo'qotish: fon (matnsiz "yorug'lik xaritasi") taxmin qilinib,
  /// rasmdan ayiriladi — natijada fon bir tekis oq, matn esa to'q qoladi.
  static cv.Mat _whiten(cv.Mat channel) {
    final kernel = cv.getStructuringElement(cv.MORPH_RECT, (7, 7));
    final dilated = cv.dilate(channel, kernel);
    final background = cv.medianBlur(dilated, 21);
    final diff = cv.absDiff(channel, background);
    final inverted = cv.bitwiseNOT(diff);
    final normalized = cv.normalize(inverted, cv.Mat.empty(), alpha: 0, beta: 255, normType: cv.NORM_MINMAX);
    // "Oq nuqta" 225 ga tushiriladi: xira kulrang qoldiqlar (dog' izi, soya chegarasi) oqqa aylanadi
    return cv.convertScaleAbs(normalized, alpha: 255 / 225);
  }

  static cv.Mat _whitenColor(cv.Mat bgr) {
    final channels = cv.split(bgr);
    final cleaned = cv.VecMat.fromList([for (final ch in channels) _whiten(ch)]);
    return cv.merge(cleaned);
  }
}
