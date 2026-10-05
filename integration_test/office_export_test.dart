// Qurilmada: flutter test integration_test/office_export_test.dart -d <qurilma>
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:integration_test/integration_test.dart';
import 'package:scan_to_pdf/services/office_export.dart';
import 'package:xml/xml.dart';

/// Har bir XML qism to'g'ri tuzilgan, har bir bog'lanish (rels) mavjud faylga
/// ishora qiladi va har bir XML qismning turi [Content_Types] da bor.
Map<String, XmlDocument> checkPackage(Uint8List bytes) {
  final zip = ZipDecoder().decodeBytes(bytes);
  final names = {for (final f in zip.files) f.name};
  final xml = <String, XmlDocument>{};
  for (final f in zip.files) {
    if (f.name.endsWith('.xml') || f.name.endsWith('.rels')) {
      xml[f.name] = XmlDocument.parse(utf8.decode(f.content as List<int>));
    }
  }
  final types = xml['[Content_Types].xml']!;
  final overrides = types
      .findAllElements('Override')
      .map((e) => e.getAttribute('PartName')!.substring(1))
      .toSet();
  for (final name in names.where(
    (n) => n.endsWith('.xml') && n != '[Content_Types].xml',
  )) {
    expect(overrides, contains(name), reason: 'content type: $name');
  }
  for (final MapEntry(key: name, value: doc) in xml.entries.where(
    (e) => e.key.endsWith('.rels'),
  )) {
    final base = name
        .replaceFirst('_rels/', '')
        .replaceFirst(RegExp(r'[^/]*\.rels$'), '');
    for (final rel in doc.findAllElements('Relationship')) {
      final target = Uri.parse(base).resolve(rel.getAttribute('Target')!).path;
      expect(
        names,
        contains(target.startsWith('/') ? target.substring(1) : target),
        reason: '$name → $target',
      );
    }
  }
  return xml;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  test('xlsx: varaqlar, sonlar, matn va maxsus belgilar', () async {
    final bytes = OfficeExport.xlsx([
      (
        name: 'Narxlar <2026>',
        rows: [
          ['Mahsulot', 'Narx', 'Kod'],
          ['Olma & nok', '12.5', '007'],
          ['Яблоко "қизил"', '-3', ''],
        ],
      ),
      (
        name: 'Narxlar <2026>',
        rows: [
          ['x'],
        ],
      ),
    ]);
    final xml = checkPackage(bytes);
    final sheets = xml['xl/workbook.xml']!
        .findAllElements('sheet')
        .map((e) => e.getAttribute('name'))
        .toList();
    expect(sheets, ['Narxlar <2026>', 'Narxlar <2026> (2)']);
    final cells = {
      for (final c in xml['xl/worksheets/sheet1.xml']!.findAllElements('c'))
        c.getAttribute('r'): (c.getAttribute('t'), c.innerText),
    };
    expect(cells['B2'], (null, '12.5'));
    expect(cells['B3'], (null, '-3'));
    expect(cells['C2'], ('inlineStr', '007')); // boshidagi nol saqlanadi
    expect(cells['A2'], ('inlineStr', 'Olma & nok'));
    expect(cells['A3'], ('inlineStr', 'Яблоко "қизил"'));
    expect(cells.containsKey('C3'), isFalse);
    File('/storage/emulated/0/Download/test.xlsx').writeAsBytesSync(bytes);
  });

  test('pptx: har bir rasm — slayd, o\'lcham sahifa nisbatida', () async {
    final jpg = Uint8List.fromList(
      img.encodeJpg(img.Image(width: 60, height: 80)),
    );
    final bytes = OfficeExport.pptx(
      [jpg, jpg, jpg],
      widthPt: 595,
      heightPt: 842,
    );
    final xml = checkPackage(bytes);
    final pres = xml['ppt/presentation.xml']!;
    expect(pres.findAllElements('p:sldId').length, 3);
    final size = pres.findAllElements('p:sldSz').single;
    expect(size.getAttribute('cx'), '${595 * 12700}');
    expect(size.getAttribute('cy'), '${842 * 12700}');
    File('/storage/emulated/0/Download/test.pptx').writeAsBytesSync(bytes);
  });
}
