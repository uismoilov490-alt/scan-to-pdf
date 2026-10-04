import 'dart:convert';
import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

enum Script { cyrillic, latin, unknown }

/// Oʻzbek kirill ↔ lotin oʻgirish (1995-yilgi rasmiy imlo qoidalari asosida).
/// Lotin chiqishida oʻ/gʻ uchun ʻ (U+02BB), tutuq belgisi uchun ʼ (U+02BC).
class TransliterationService {
  TransliterationService._();

  static const _okina = 'ʻ'; // U+02BB — oʻ, gʻ
  static const _tutuq = 'ʼ'; // U+02BC — tutuq belgisi

  // ── Kirill → Lotin (е va ц alohida qoida bilan, pastda) ───────────────────
  static const Map<String, String> _cyrToLat = {
    'А': 'A',
    'а': 'a',
    'Б': 'B',
    'б': 'b',
    'В': 'V',
    'в': 'v',
    'Г': 'G',
    'г': 'g',
    'Д': 'D',
    'д': 'd',
    'Ё': 'Yo',
    'ё': 'yo',
    'Ж': 'J',
    'ж': 'j',
    'З': 'Z',
    'з': 'z',
    'И': 'I',
    'и': 'i',
    'Й': 'Y',
    'й': 'y',
    'К': 'K',
    'к': 'k',
    'Л': 'L',
    'л': 'l',
    'М': 'M',
    'м': 'm',
    'Н': 'N',
    'н': 'n',
    'О': 'O',
    'о': 'o',
    'П': 'P',
    'п': 'p',
    'Р': 'R',
    'р': 'r',
    'С': 'S',
    'с': 's',
    'Т': 'T',
    'т': 't',
    'У': 'U',
    'у': 'u',
    'Ф': 'F',
    'ф': 'f',
    'Х': 'X',
    'х': 'x',
    'Ч': 'Ch',
    'ч': 'ch',
    'Ш': 'Sh',
    'ш': 'sh',
    'Щ': 'Sh',
    'щ': 'sh',
    'Ъ': _tutuq,
    'ъ': _tutuq,
    'Ы': 'I',
    'ы': 'i',
    'Ь': '',
    'ь': '',
    'Э': 'E',
    'э': 'e',
    'Ю': 'Yu',
    'ю': 'yu',
    'Я': 'Ya',
    'я': 'ya',
    'Қ': 'Q',
    'қ': 'q',
    'Ғ': 'G$_okina',
    'ғ': 'g$_okina',
    'Ҳ': 'H',
    'ҳ': 'h',
    'Ў': 'O$_okina',
    'ў': 'o$_okina',
  };

  static const _cyrVowels = 'аеёиоуўэюяыАЕЁИОУЎЭЮЯЫ';
  static const _latVowels = 'aeiouAEIOU';

  // Oy nomlarining rasmiy yozilishi: сентябрь → sentabr, октябрь → oktabr
  static const _cyrMonthFixes = [
    ('сентябр', 'сентабр'),
    ('Сентябр', 'Сентабр'),
    ('СЕНТЯБР', 'СЕНТАБР'),
    ('октябр', 'октабр'),
    ('Октябр', 'Октабр'),
    ('ОКТЯБР', 'ОКТАБР'),
  ];

  // Lotindan kirillga: ь belgisi tiklanadigan oy nomlari
  static const _latMonths = {
    'yanvar': 'январь',
    'fevral': 'февраль',
    'aprel': 'апрель',
    'iyun': 'июнь',
    'iyul': 'июль',
    'sentabr': 'сентябрь',
    'oktabr': 'октябрь',
    'noyabr': 'ноябрь',
    'dekabr': 'декабрь',
  };

  // ── Lotin → Kirill: koʻp belgili birikmalar (tartib muhim) ────────────────
  static const List<(String, String)> _latToCyrSeq = [
    ("O'", 'Ў'),
    ("o'", 'ў'),
    ("G'", 'Ғ'),
    ("g'", 'ғ'),
    ('SH', 'Ш'),
    ('Sh', 'Ш'),
    ('sh', 'ш'),
    ('CH', 'Ч'),
    ('Ch', 'Ч'),
    ('ch', 'ч'),
    ('YO', 'Ё'),
    ('Yo', 'Ё'),
    ('yo', 'ё'),
    ('YU', 'Ю'),
    ('Yu', 'Ю'),
    ('yu', 'ю'),
    ('YA', 'Я'),
    ('Ya', 'Я'),
    ('ya', 'я'),
    ('YE', 'Е'),
    ('Ye', 'Е'),
    ('ye', 'е'),
  ];

  // ── Lotin → Kirill: yakka harflar (e alohida qoida bilan) ─────────────────
  static const Map<String, String> _latToCyrSingle = {
    'A': 'А',
    'a': 'а',
    'B': 'Б',
    'b': 'б',
    'D': 'Д',
    'd': 'д',
    'F': 'Ф',
    'f': 'ф',
    'G': 'Г',
    'g': 'г',
    'H': 'Ҳ',
    'h': 'ҳ',
    'I': 'И',
    'i': 'и',
    'J': 'Ж',
    'j': 'ж',
    'K': 'К',
    'k': 'к',
    'L': 'Л',
    'l': 'л',
    'M': 'М',
    'm': 'м',
    'N': 'Н',
    'n': 'н',
    'O': 'О',
    'o': 'о',
    'P': 'П',
    'p': 'п',
    'Q': 'Қ',
    'q': 'қ',
    'R': 'Р',
    'r': 'р',
    'S': 'С',
    's': 'с',
    'T': 'Т',
    't': 'т',
    'U': 'У',
    'u': 'у',
    'V': 'В',
    'v': 'в',
    'X': 'Х',
    'x': 'х',
    'Y': 'Й',
    'y': 'й',
    'Z': 'З',
    'z': 'з',
    "'": 'ъ',
  };

  static bool _isLetter(String? c) =>
      c != null && c.toLowerCase() != c.toUpperCase();

  static bool _isUpper(String c) => c != c.toLowerCase();

  // ── Asosiy metodlar ────────────────────────────────────────────────────────

  /// Kirill → Lotin.
  /// [before]/[after] — matn boʻlagidan oldingi va keyingi belgi (Word'da bitta
  /// soʻz bir necha boʻlakka boʻlinganda qoidalar toʻgʻri ishlashi uchun).
  static String toLatin(String input, {String? before, String? after}) {
    var text = input;
    for (final (from, to) in _cyrMonthFixes) {
      text = text.replaceAll(from, to);
    }
    final chars = text.split('');
    final buf = StringBuffer();
    for (var i = 0; i < chars.length; i++) {
      final ch = chars[i];
      final prev = i > 0 ? chars[i - 1] : before;
      final next = i + 1 < chars.length ? chars[i + 1] : after;
      final upper = _isUpper(ch);

      String out;
      if (ch == 'Е' || ch == 'е') {
        // Soʻz boshida, unlidan va ъ/ь dan keyin — "ye"
        final ye =
            !_isLetter(prev) ||
            _cyrVowels.contains(prev!) ||
            'ЪъЬь'.contains(prev);
        out = ye ? (upper ? 'Ye' : 'ye') : (upper ? 'E' : 'e');
      } else if (ch == 'Ц' || ch == 'ц') {
        // Unlidan keyin "ts", soʻz boshida va undoshdan keyin "s"
        final ts = prev != null && _cyrVowels.contains(prev);
        out = ts ? (upper ? 'Ts' : 'ts') : (upper ? 'S' : 's');
      } else {
        out = _cyrToLat[ch] ?? ch;
      }

      // BOSH HARFLI soʻzda: Ш → SH (Sh emas)
      if (upper && out.length > 1 && _isLetter(out[1])) {
        final allCaps =
            (_isLetter(next) && _isUpper(next!)) ||
            (!_isLetter(next) && _isLetter(prev) && _isUpper(prev!));
        if (allCaps) out = out.toUpperCase();
      }
      buf.write(out);
    }
    return buf.toString();
  }

  /// Lotin → Kirill. Apostrof variantlari (ʻ ʼ ‘ ’ `) avval normallanadi.
  /// [before] — matn boʻlagidan oldingi belgi (Word boʻlaklari uchun).
  static String toCyrillic(String input, {String? before}) {
    var text = _normalizeApostrophes(input);

    text = text.replaceAllMapped(
      RegExp(r'\b(' + _latMonths.keys.join('|') + r')\b', caseSensitive: false),
      (m) {
        final word = m[0]!;
        final cyr = _latMonths[word.toLowerCase()]!;
        if (word.length > 1 && word == word.toUpperCase())
          return cyr.toUpperCase();
        if (_isUpper(word[0])) return cyr[0].toUpperCase() + cyr.substring(1);
        return cyr;
      },
    );

    final prevNorm = before == null ? null : _normalizeApostrophes(before);
    final buf = StringBuffer();
    var i = 0;
    while (i < text.length) {
      final ch = text[i];
      final prev = i > 0 ? text[i - 1] : prevNorm;

      // s + tutuq + h: "Is'hoq" → "Исҳоқ" (ш emas)
      if ((ch == 's' || ch == 'S') &&
          i + 2 < text.length &&
          text[i + 1] == "'" &&
          (text[i + 2] == 'h' || text[i + 2] == 'H')) {
        buf.write(ch == 'S' ? 'С' : 'с');
        buf.write(text[i + 2] == 'H' ? 'Ҳ' : 'ҳ');
        i += 3;
        continue;
      }

      // "yo'" — y + oʻ ("yo'l" → "йўл", ё emas)
      if ((ch == 'y' || ch == 'Y') &&
          i + 2 < text.length &&
          (text[i + 1] == 'o' || text[i + 1] == 'O') &&
          text[i + 2] == "'") {
        buf.write(ch == 'Y' ? 'Й' : 'й');
        i += 1;
        continue;
      }

      var matched = false;
      for (final (seq, cyr) in _latToCyrSeq) {
        if (text.startsWith(seq, i)) {
          buf.write(cyr);
          i += seq.length;
          matched = true;
          break;
        }
      }
      if (matched) continue;

      if (ch == 'e' || ch == 'E') {
        // Soʻz boshida va unlidan keyin — "э", qolgan joyda — "е"
        final wordStart = !_isLetter(prev) && prev != "'";
        final afterVowel = prev != null && _latVowels.contains(prev);
        final e = wordStart || afterVowel;
        buf.write(e ? (ch == 'E' ? 'Э' : 'э') : (ch == 'E' ? 'Е' : 'е'));
      } else {
        buf.write(_latToCyrSingle[ch] ?? ch);
      }
      i++;
    }
    return buf.toString();
  }

  static String _normalizeApostrophes(String s) => s
      .replaceAll('ʻ', "'")
      .replaceAll('ʼ', "'")
      .replaceAll('‘', "'")
      .replaceAll('’', "'")
      .replaceAll('`', "'");

  /// Matndagi asosiy alifboni aniqlaydi (Kirill yoki Lotin harflari soni).
  static Script detectScript(String text) {
    int cyr = 0, lat = 0;
    for (final rune in text.runes) {
      if (_isCyrillicRune(rune)) {
        cyr++;
      } else if ((rune >= 0x41 && rune <= 0x5A) ||
          (rune >= 0x61 && rune <= 0x7A)) {
        lat++;
      }
    }
    final total = cyr + lat;
    if (total == 0) return Script.unknown;
    return cyr >= total * 0.5 ? Script.cyrillic : Script.latin;
  }

  static bool _isCyrillicRune(int cp) =>
      (cp >= 0x0410 && cp <= 0x044F) || // А–я (asosiy)
      cp == 0x0401 ||
      cp == 0x0451 || // Ё ё
      cp == 0x040E ||
      cp == 0x045E || // Ў ў
      cp == 0x0492 ||
      cp == 0x0493 || // Ғ ғ
      cp == 0x049A ||
      cp == 0x049B || // Қ қ
      cp == 0x04B2 ||
      cp == 0x04B3; // Ҳ ҳ

  // ── DOCX konvertatsiya ─────────────────────────────────────────────────────

  /// DOCX baytlarini in-place o'giradi: XML teglar va formatlash saqlanadi,
  /// faqat `w:t` elementlari ichidagi matn konvertatsiya qilinadi.
  static List<int> convertDocxBytes(List<int> bytes, Script sourceScript) {
    final archive = ZipDecoder().decodeBytes(bytes);
    final outArchive = Archive();

    for (final entry in archive) {
      if (_isConvertibleWordPart(entry.name)) {
        final xmlStr = utf8.decode(entry.content as List<int>);
        final converted = _convertWordXml(xmlStr, sourceScript);
        final outBytes = utf8.encode(converted);
        outArchive.addFile(ArchiveFile(entry.name, outBytes.length, outBytes));
      } else {
        outArchive.addFile(entry);
      }
    }

    return ZipEncoder().encode(outArchive)!;
  }

  static bool _isConvertibleWordPart(String name) =>
      name == 'word/document.xml' ||
      name == 'word/endnotes.xml' ||
      name == 'word/footnotes.xml' ||
      (name.startsWith('word/header') && name.endsWith('.xml')) ||
      (name.startsWith('word/footer') && name.endsWith('.xml'));

  static String _convertWordXml(String xmlContent, Script sourceScript) {
    final doc = XmlDocument.parse(xmlContent);
    // Xatboshi ichidagi boʻlaklar bir-biriga qoʻshni: soʻz boʻlaklarga boʻlingan
    // boʻlsa ham "е"/"ц" qoidalari qoʻshni harfga qarab toʻgʻri qoʻllanadi.
    for (final para in doc.findAllElements('w:p').toList()) {
      final runs = para.findAllElements('w:t').toList();
      final originals = runs.map((e) => e.innerText).toList();
      for (var k = 0; k < runs.length; k++) {
        final text = originals[k];
        if (text.isEmpty) continue;
        final before = k > 0 && originals[k - 1].isNotEmpty
            ? originals[k - 1][originals[k - 1].length - 1]
            : null;
        final after = k + 1 < runs.length && originals[k + 1].isNotEmpty
            ? originals[k + 1][0]
            : null;
        final converted = sourceScript == Script.cyrillic
            ? toLatin(text, before: before, after: after)
            : toCyrillic(text, before: before);
        runs[k].children
          ..clear()
          ..add(XmlText(converted));
      }
    }
    return doc.toXmlString(pretty: false);
  }

  /// DOCX dagi birinchi N belgi matnini qaytaradi (alifbo aniqlash uchun).
  static String extractDocxPreview(List<int> bytes, {int maxChars = 500}) {
    try {
      final archive = ZipDecoder().decodeBytes(bytes);
      for (final entry in archive) {
        if (entry.name == 'word/document.xml') {
          final xmlStr = utf8.decode(entry.content as List<int>);
          final doc = XmlDocument.parse(xmlStr);
          final buf = StringBuffer();
          for (final para in doc.findAllElements('w:p')) {
            final line = para
                .findAllElements('w:t')
                .map((e) => e.innerText)
                .join();
            if (line.isEmpty) continue;
            if (buf.isNotEmpty) buf.write('\n');
            buf.write(line);
            if (buf.length >= maxChars) break;
          }
          return buf.toString();
        }
      }
    } catch (_) {}
    return '';
  }
}
