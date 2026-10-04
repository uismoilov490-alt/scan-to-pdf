import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scan_to_pdf/services/document_export_service.dart';
import 'package:scan_to_pdf/services/transliteration_service.dart';

// Rasmiy imlo: oʻ/gʻ — U+02BB (ʻ), tutuq belgisi — U+02BC (ʼ)
void main() {
  group('Kirill → Lotin', () {
    final cases = {
      'Ўзбекистон Республикаси': 'Oʻzbekiston Respublikasi',
      'ғалаба': 'gʻalaba',
      'маъно': 'maʼno',
      'мактаб': 'maktab',
      'юлдуз': 'yulduz',
      'Ёшлик': 'Yoshlik',
      'Шаҳар': 'Shahar',
      // е: soʻz boshida, unli va ъ/ь dan keyin — "ye"
      'ер': 'yer',
      'Европа': 'Yevropa',
      'поезд': 'poyezd',
      'кеча': 'kecha',
      // ц: unlidan keyin "ts", soʻz boshida va undoshdan keyin "s"
      'цирк': 'sirk',
      'концерт': 'konsert',
      'милиция': 'militsiya',
      // Bosh harflar bilan yozilgan soʻz
      'ШАҲАР': 'SHAHAR',
      'ЧЎЛ': 'CHOʻL',
      'ЎЗБЕКИСТОН': 'OʻZBEKISTON',
      // Oy nomlari (rasmiy yozilishi)
      '4 сентябрь': '4 sentabr',
      'Октябрь ойи': 'Oktabr oyi',
      'январь': 'yanvar',
    };
    cases.forEach((cyr, lat) {
      test('$cyr → $lat', () => expect(TransliterationService.toLatin(cyr), lat));
    });
  });

  group('Lotin → Kirill', () {
    final cases = {
      'Oʻzbekiston': 'Ўзбекистон',
      "o'zbek": 'ўзбек',
      'gʻalaba': 'ғалаба',
      'maʼno': 'маъно',
      "ma'no": 'маъно',
      'Shahar': 'Шаҳар',
      'SHAHAR': 'ШАҲАР',
      // e: soʻz boshida va unlidan keyin — "э", "ye" — "е"
      'ertaga': 'эртага',
      'poeziya': 'поэзия',
      'kecha': 'кеча',
      'yer': 'ер',
      'Yevropa': 'Европа',
      // "yo'" — y + oʻ (ё emas)
      "yo'l": 'йўл',
      'Yoʻq': 'Йўқ',
      // t + s alohida tovushlar (ц emas)
      'ketsa': 'кетса',
      'aytsa': 'айтса',
      "Is'hoq": 'Исҳоқ',
      // Oy nomlari
      '4 sentabr': '4 сентябрь',
      'Oktabr oyi': 'Октябрь ойи',
      'yanvar': 'январь',
    };
    cases.forEach((lat, cyr) {
      test('$lat → $cyr', () => expect(TransliterationService.toCyrillic(lat), cyr));
    });
  });

  test('Word (.docx) fayl ichida oʻgiriladi', () {
    final docx = DocumentExportService.buildDocx('Тошкент шаҳри\nАриза');
    final out = TransliterationService.convertDocxBytes(docx, Script.cyrillic);
    expect(DocumentExportService.docxText(out), 'Toshkent shahri\nAriza');
  });

  test('Word: boʻlaklarga boʻlingan soʻz (Ш + ер) toʻgʻri oʻgiriladi', () {
    // Word bitta soʻzni formatlash sababli bir necha <w:t> ga boʻlib yozadi
    const xml = '<?xml version="1.0" encoding="UTF-8"?>'
        '<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:body>'
        '<w:p><w:r><w:t>Ш</w:t></w:r><w:r><w:t>ер ва е</w:t></w:r><w:r><w:t>р</w:t></w:r></w:p>'
        '</w:body></w:document>';
    final bytes = utf8.encode(xml);
    final archive = Archive()..addFile(ArchiveFile('word/document.xml', bytes.length, bytes));
    final docx = ZipEncoder().encode(archive)!;
    final out = TransliterationService.convertDocxBytes(docx, Script.cyrillic);
    expect(DocumentExportService.docxText(out), 'Sher va yer');
  });

  test('Yozuvni aniqlash', () {
    expect(TransliterationService.detectScript('Тошкент шаҳри'), Script.cyrillic);
    expect(TransliterationService.detectScript('Toshkent shahri'), Script.latin);
  });
}
