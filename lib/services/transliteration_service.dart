import 'dart:convert';
import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

enum Script { cyrillic, latin, unknown }

class TransliterationService {
  TransliterationService._();

  // ── Kirill → Lotin ────────────────────────────────────────────────────────
  static const Map<String, String> _cyrToLat = {
    'А': 'A',  'а': 'a',
    'Б': 'B',  'б': 'b',
    'В': 'V',  'в': 'v',
    'Г': 'G',  'г': 'g',
    'Д': 'D',  'д': 'd',
    'Е': 'E',  'е': 'e',
    'Ё': 'Yo', 'ё': 'yo',
    'Ж': 'J',  'ж': 'j',
    'З': 'Z',  'з': 'z',
    'И': 'I',  'и': 'i',
    'Й': 'Y',  'й': 'y',
    'К': 'K',  'к': 'k',
    'Л': 'L',  'л': 'l',
    'М': 'M',  'м': 'm',
    'Н': 'N',  'н': 'n',
    'О': 'O',  'о': 'o',
    'П': 'P',  'п': 'p',
    'Р': 'R',  'р': 'r',
    'С': 'S',  'с': 's',
    'Т': 'T',  'т': 't',
    'У': 'U',  'у': 'u',
    'Ф': 'F',  'ф': 'f',
    'Х': 'X',  'х': 'x',
    'Ц': 'Ts', 'ц': 'ts',
    'Ч': 'Ch', 'ч': 'ch',
    'Ш': 'Sh', 'ш': 'sh',
    'Щ': 'Sh', 'щ': 'sh',
    'Ъ': "'",  'ъ': "'",
    'Ы': 'I',  'ы': 'i',
    'Ь': '',   'ь': '',
    'Э': 'E',  'э': 'e',
    'Ю': 'Yu', 'ю': 'yu',
    'Я': 'Ya', 'я': 'ya',
    'Қ': 'Q',  'қ': 'q',
    'Ғ': "G'", 'ғ': "g'",
    'Ҳ': 'H',  'ҳ': 'h',
    'Ў': "O'", 'ў': "o'",
  };

  // ── Lotin → Kirill: ko'p belgili ketma-ketliklar ──────────────────────────
  // Har bir harfiy variant alohida — lowercase() ishlatilmaydi,
  // shuning uchun "Sh"→"Ш", "SH"→"Ш", "sh"→"ш" barchasi to'g'ri.
  static const List<(String, String)> _latToCyrSeq = [
    // Apostrof birikmalari (o' / g') — avval tekshiriladi
    ("O'", 'Ў'), ("o'", 'ў'),
    ("G'", 'Ғ'), ("g'", 'ғ'),
    // SH
    ('SH', 'Ш'), ('Sh', 'Ш'), ('sh', 'ш'),
    // CH
    ('CH', 'Ч'), ('Ch', 'Ч'), ('ch', 'ч'),
    // YO
    ('YO', 'Ё'), ('Yo', 'Ё'), ('yo', 'ё'),
    // YU
    ('YU', 'Ю'), ('Yu', 'Ю'), ('yu', 'ю'),
    // YA
    ('YA', 'Я'), ('Ya', 'Я'), ('ya', 'я'),
    // TS
    ('TS', 'Ц'), ('Ts', 'Ц'), ('ts', 'ц'),
  ];

  // ── Lotin → Kirill: yakka harflar (katta va kichik alohida) ───────────────
  static const Map<String, String> _latToCyrSingle = {
    'A': 'А', 'a': 'а',
    'B': 'Б', 'b': 'б',
    'D': 'Д', 'd': 'д',
    'E': 'Е', 'e': 'е',
    'F': 'Ф', 'f': 'ф',
    'G': 'Г', 'g': 'г',
    'H': 'Ҳ', 'h': 'ҳ',
    'I': 'И', 'i': 'и',
    'J': 'Ж', 'j': 'ж',
    'K': 'К', 'k': 'к',
    'L': 'Л', 'l': 'л',
    'M': 'М', 'm': 'м',
    'N': 'Н', 'n': 'н',
    'O': 'О', 'o': 'о',
    'P': 'П', 'p': 'п',
    'Q': 'Қ', 'q': 'қ',
    'R': 'Р', 'r': 'р',
    'S': 'С', 's': 'с',
    'T': 'Т', 't': 'т',
    'U': 'У', 'u': 'у',
    'V': 'В', 'v': 'в',
    'X': 'Х', 'x': 'х',
    'Y': 'Й', 'y': 'й',
    'Z': 'З', 'z': 'з',
    "'": 'ъ',
  };

  // ── Asosiy metodlar ────────────────────────────────────────────────────────

  /// Kirill → Lotin
  static String toLatin(String input) {
    final buf = StringBuffer();
    for (final rune in input.runes) {
      final ch = String.fromCharCode(rune);
      buf.write(_cyrToLat[ch] ?? ch);
    }
    return buf.toString();
  }

  /// Lotin → Kirill
  /// Apostrof variantlari (ʻ ' ` ) avval normallanadi.
  static String toCyrillic(String input) {
    final text = input
        .replaceAll('ʻ', "'") // ʻ
        .replaceAll('‘', "'") // '
        .replaceAll('’', "'") // '
        .replaceAll('`', "'");

    final buf = StringBuffer();
    int i = 0;
    while (i < text.length) {
      bool matched = false;
      for (final (seq, cyr) in _latToCyrSeq) {
        if (text.startsWith(seq, i)) {
          buf.write(cyr);
          i += seq.length;
          matched = true;
          break;
        }
      }
      if (!matched) {
        buf.write(_latToCyrSingle[text[i]] ?? text[i]);
        i++;
      }
    }
    return buf.toString();
  }

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
      cp == 0x0401 || cp == 0x0451 ||   // Ё ё
      cp == 0x040E || cp == 0x045E ||   // Ў ў
      cp == 0x0492 || cp == 0x0493 ||   // Ғ ғ
      cp == 0x049A || cp == 0x049B ||   // Қ қ
      cp == 0x04B2 || cp == 0x04B3;     // Ҳ ҳ

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
        outArchive.addFile(
          ArchiveFile(entry.name, outBytes.length, outBytes),
        );
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
    // Avval barcha elementlarni yig'amiz, so'ng modifikatsiya (lazy iterator xavfidan saqlanish)
    final elements = doc.findAllElements('w:t').toList();
    for (final el in elements) {
      final text = el.innerText;
      if (text.isEmpty) continue;
      final converted = sourceScript == Script.cyrillic
          ? toLatin(text)
          : toCyrillic(text);
      el.children
        ..clear()
        ..add(XmlText(converted));
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
          for (final el in doc.findAllElements('w:t')) {
            buf.write(el.innerText);
            if (buf.length >= maxChars) break;
          }
          return buf.toString();
        }
      }
    } catch (_) {}
    return '';
  }
}
