import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'ad_service.dart';

/// Excel (.xlsx) va PowerPoint (.pptx) fayllarini kutubxonasiz yaratadi
/// (Office Open XML — XML bo'laklardan iborat ZIP).
abstract final class OfficeExport {
  /// `scan_to_pdf/hujjatlar` papkasiga noyob nom bilan yozadi.
  static Future<File> save(List<int> bytes, String baseName, String ext) async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(base.path, 'scan_to_pdf', 'hujjatlar'));
    await dir.create(recursive: true);
    final safe = baseName.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
    var file = File(p.join(dir.path, '${safe.isEmpty ? 'hujjat' : safe}.$ext'));
    for (var i = 1; await file.exists(); i++) {
      file = File(p.join(dir.path, '${safe}_$i.$ext'));
    }
    await file.writeAsBytes(bytes, flush: true);
    AdService.recordSave();
    return file;
  }

  static String _esc(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      // XML 1.0 da taqiqlangan boshqaruv belgilari
      .replaceAll(RegExp(r'[\u0000-\u0008\u000B\u000C\u000E-\u001F]'), '');

  static const _xml =
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n';

  static Uint8List _zip(Map<String, Object> parts) {
    final archive = Archive();
    parts.forEach((name, data) {
      final bytes = data is String ? utf8.encode(data) : data as List<int>;
      archive.addFile(ArchiveFile(name, bytes.length, bytes));
    });
    return Uint8List.fromList(ZipEncoder().encode(archive)!);
  }

  // ── Excel ────────────────────────────────────────────────────────────

  static final _number = RegExp(r'^-?\d+(\.\d+)?$');

  /// Excel ustun harfi: 0 → A, 26 → AA.
  static String _col(int i) {
    var s = '';
    for (var n = i + 1; n > 0; n = (n - 1) ~/ 26) {
      s = String.fromCharCode(65 + (n - 1) % 26) + s;
    }
    return s;
  }

  /// Varaq nomi: 31 belgigacha, taqiqlangan belgilarsiz, takrorlanmas.
  static List<String> _sheetNames(List<String> names) {
    final used = <String>{};
    return [
      for (final (i, raw) in names.indexed)
        () {
          var n = raw.replaceAll(RegExp(r'[\[\]:*?/\\]'), ' ').trim();
          if (n.isEmpty) n = 'Sheet${i + 1}';
          if (n.length > 31) n = n.substring(0, 31);
          var unique = n;
          for (var k = 2; !used.add(unique.toLowerCase()); k++) {
            final suffix = ' ($k)';
            unique =
                '${n.substring(0, (31 - suffix.length).clamp(0, n.length))}$suffix';
          }
          return unique;
        }(),
    ];
  }

  /// Jadvallardan .xlsx: har bir jadval — alohida varaq; sonlar son sifatida.
  static Uint8List xlsx(List<({String name, List<List<String>> rows})> tables) {
    final names = _sheetNames([for (final t in tables) t.name]);
    final parts = <String, Object>{};
    for (final (i, t) in tables.indexed) {
      final rows = StringBuffer();
      for (final (r, row) in t.rows.indexed) {
        rows.write('<row r="${r + 1}">');
        for (final (c, value) in row.indexed) {
          final v = value.trim();
          if (v.isEmpty) continue;
          final ref = '${_col(c)}${r + 1}';
          // Raqamli matn (masalan "007" yoki telefon) son bo'lib qolmasin
          final isNumber =
              _number.hasMatch(v) &&
              !(v.length > 1 && v.startsWith('0') && !v.startsWith('0.'));
          rows.write(
            isNumber
                ? '<c r="$ref"><v>$v</v></c>'
                : '<c r="$ref" t="inlineStr"${r == 0 ? ' s="1"' : ''}><is><t xml:space="preserve">${_esc(v)}</t></is></c>',
          );
        }
        rows.write('</row>');
      }
      parts['xl/worksheets/sheet${i + 1}.xml'] =
          '$_xml<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
          '<sheetData>$rows</sheetData></worksheet>';
    }
    final sheets = [
      for (var i = 0; i < tables.length; i++)
        '<sheet name="${_esc(names[i])}" sheetId="${i + 1}" r:id="rId${i + 1}"/>',
    ].join();
    final sheetRels = [
      for (var i = 0; i < tables.length; i++)
        '<Relationship Id="rId${i + 1}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet${i + 1}.xml"/>',
    ].join();
    final sheetTypes = [
      for (var i = 0; i < tables.length; i++)
        '<Override PartName="/xl/worksheets/sheet${i + 1}.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>',
    ].join();
    parts.addAll({
      '[Content_Types].xml':
          '$_xml<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
          '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
          '<Default Extension="xml" ContentType="application/xml"/>'
          '<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>'
          '<Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>'
          '$sheetTypes</Types>',
      '_rels/.rels':
          '$_xml<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
          '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>'
          '</Relationships>',
      'xl/workbook.xml':
          '$_xml<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" '
          'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">'
          '<sheets>$sheets</sheets></workbook>',
      'xl/_rels/workbook.xml.rels':
          '$_xml<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
          '$sheetRels'
          '<Relationship Id="rId${tables.length + 1}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>'
          '</Relationships>',
      // 0 — oddiy, 1 — qalin (birinchi qator sarlavha)
      'xl/styles.xml':
          '$_xml<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
          '<fonts count="2"><font><sz val="11"/><name val="Calibri"/></font><font><b/><sz val="11"/><name val="Calibri"/></font></fonts>'
          '<fills count="2"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill></fills>'
          '<borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders>'
          '<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>'
          '<cellXfs count="2"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>'
          '<xf numFmtId="0" fontId="1" fillId="0" borderId="0" xfId="0" applyFont="1"/></cellXfs>'
          '</styleSheet>',
    });
    return _zip(parts);
  }

  // ── PowerPoint ───────────────────────────────────────────────────────

  static const _emuPerPt = 12700;
  static const _pml =
      'http://schemas.openxmlformats.org/presentationml/2006/main';
  static const _dml = 'http://schemas.openxmlformats.org/drawingml/2006/main';
  static const _rel =
      'http://schemas.openxmlformats.org/officeDocument/2006/relationships';
  static const _relPkg =
      'http://schemas.openxmlformats.org/package/2006/relationships';
  static const _relType =
      'http://schemas.openxmlformats.org/officeDocument/2006/relationships';

  /// Har bir JPEG — alohida slayd (butun slaydni egallaydi). Slayd o'lchami
  /// birinchi sahifa nisbatida ([widthPt]×[heightPt] punkt).
  static Uint8List pptx(
    List<Uint8List> jpegs, {
    required double widthPt,
    required double heightPt,
  }) {
    final cx = (widthPt * _emuPerPt).round();
    final cy = (heightPt * _emuPerPt).round();
    final n = jpegs.length;
    final parts = <String, Object>{};
    for (var i = 1; i <= n; i++) {
      parts['ppt/media/image$i.jpeg'] = jpegs[i - 1];
      parts['ppt/slides/slide$i.xml'] =
          '$_xml<p:sld xmlns:a="$_dml" xmlns:r="$_rel" xmlns:p="$_pml"><p:cSld><p:spTree>'
          '<p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr>'
          '<p:grpSpPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="0" cy="0"/><a:chOff x="0" y="0"/><a:chExt cx="0" cy="0"/></a:xfrm></p:grpSpPr>'
          '<p:pic><p:nvPicPr><p:cNvPr id="2" name="Page $i"/><p:cNvPicPr><a:picLocks noChangeAspect="1"/></p:cNvPicPr><p:nvPr/></p:nvPicPr>'
          '<p:blipFill><a:blip r:embed="rId2"/><a:stretch><a:fillRect/></a:stretch></p:blipFill>'
          '<p:spPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="$cx" cy="$cy"/></a:xfrm><a:prstGeom prst="rect"><a:avLst/></a:prstGeom></p:spPr>'
          '</p:pic></p:spTree></p:cSld><p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr></p:sld>';
      parts['ppt/slides/_rels/slide$i.xml.rels'] =
          '$_xml<Relationships xmlns="$_relPkg">'
          '<Relationship Id="rId1" Type="$_relType/slideLayout" Target="../slideLayouts/slideLayout1.xml"/>'
          '<Relationship Id="rId2" Type="$_relType/image" Target="../media/image$i.jpeg"/>'
          '</Relationships>';
    }
    final slideIds = [
      for (var i = 1; i <= n; i++)
        '<p:sldId id="${255 + i}" r:id="rId${i + 1}"/>',
    ].join();
    final slideRels = [
      for (var i = 1; i <= n; i++)
        '<Relationship Id="rId${i + 1}" Type="$_relType/slide" Target="slides/slide$i.xml"/>',
    ].join();
    final slideTypes = [
      for (var i = 1; i <= n; i++)
        '<Override PartName="/ppt/slides/slide$i.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.slide+xml"/>',
    ].join();
    const emptyTree =
        '<p:cSld><p:spTree><p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr>'
        '<p:grpSpPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="0" cy="0"/><a:chOff x="0" y="0"/><a:chExt cx="0" cy="0"/></a:xfrm></p:grpSpPr>'
        '</p:spTree></p:cSld>';
    parts.addAll({
      '[Content_Types].xml':
          '$_xml<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
          '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
          '<Default Extension="xml" ContentType="application/xml"/>'
          '<Default Extension="jpeg" ContentType="image/jpeg"/>'
          '<Override PartName="/ppt/presentation.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.presentation.main+xml"/>'
          '<Override PartName="/ppt/slideMasters/slideMaster1.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.slideMaster+xml"/>'
          '<Override PartName="/ppt/slideLayouts/slideLayout1.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.slideLayout+xml"/>'
          '<Override PartName="/ppt/theme/theme1.xml" ContentType="application/vnd.openxmlformats-officedocument.theme+xml"/>'
          '$slideTypes</Types>',
      '_rels/.rels':
          '$_xml<Relationships xmlns="$_relPkg">'
          '<Relationship Id="rId1" Type="$_relType/officeDocument" Target="ppt/presentation.xml"/>'
          '</Relationships>',
      'ppt/presentation.xml':
          '$_xml<p:presentation xmlns:a="$_dml" xmlns:r="$_rel" xmlns:p="$_pml">'
          '<p:sldMasterIdLst><p:sldMasterId id="2147483648" r:id="rId1"/></p:sldMasterIdLst>'
          '<p:sldIdLst>$slideIds</p:sldIdLst>'
          '<p:sldSz cx="$cx" cy="$cy"/><p:notesSz cx="$cy" cy="$cx"/></p:presentation>',
      'ppt/_rels/presentation.xml.rels':
          '$_xml<Relationships xmlns="$_relPkg">'
          '<Relationship Id="rId1" Type="$_relType/slideMaster" Target="slideMasters/slideMaster1.xml"/>'
          '$slideRels'
          '<Relationship Id="rId${n + 2}" Type="$_relType/theme" Target="theme/theme1.xml"/>'
          '</Relationships>',
      'ppt/slideMasters/slideMaster1.xml':
          '$_xml<p:sldMaster xmlns:a="$_dml" xmlns:r="$_rel" xmlns:p="$_pml">$emptyTree'
          '<p:clrMap bg1="lt1" tx1="dk1" bg2="lt2" tx2="dk2" accent1="accent1" accent2="accent2" accent3="accent3" '
          'accent4="accent4" accent5="accent5" accent6="accent6" hlink="hlink" folHlink="folHlink"/>'
          '<p:sldLayoutIdLst><p:sldLayoutId id="2147483649" r:id="rId1"/></p:sldLayoutIdLst></p:sldMaster>',
      'ppt/slideMasters/_rels/slideMaster1.xml.rels':
          '$_xml<Relationships xmlns="$_relPkg">'
          '<Relationship Id="rId1" Type="$_relType/slideLayout" Target="../slideLayouts/slideLayout1.xml"/>'
          '<Relationship Id="rId2" Type="$_relType/theme" Target="../theme/theme1.xml"/>'
          '</Relationships>',
      'ppt/slideLayouts/slideLayout1.xml':
          '$_xml<p:sldLayout xmlns:a="$_dml" xmlns:r="$_rel" xmlns:p="$_pml" type="blank">$emptyTree'
          '<p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr></p:sldLayout>',
      'ppt/slideLayouts/_rels/slideLayout1.xml.rels':
          '$_xml<Relationships xmlns="$_relPkg">'
          '<Relationship Id="rId1" Type="$_relType/slideMaster" Target="../slideMasters/slideMaster1.xml"/>'
          '</Relationships>',
      'ppt/theme/theme1.xml': '$_xml$_theme',
    });
    return _zip(parts);
  }

  /// PowerPoint talab qiladigan eng kichik to'liq mavzu.
  static const _theme =
      '<a:theme xmlns:a="$_dml" name="Office"><a:themeElements>'
      '<a:clrScheme name="Office"><a:dk1><a:srgbClr val="000000"/></a:dk1><a:lt1><a:srgbClr val="FFFFFF"/></a:lt1>'
      '<a:dk2><a:srgbClr val="1F497D"/></a:dk2><a:lt2><a:srgbClr val="EEECE1"/></a:lt2>'
      '<a:accent1><a:srgbClr val="4F81BD"/></a:accent1><a:accent2><a:srgbClr val="C0504D"/></a:accent2>'
      '<a:accent3><a:srgbClr val="9BBB59"/></a:accent3><a:accent4><a:srgbClr val="8064A2"/></a:accent4>'
      '<a:accent5><a:srgbClr val="4BACC6"/></a:accent5><a:accent6><a:srgbClr val="F79646"/></a:accent6>'
      '<a:hlink><a:srgbClr val="0000FF"/></a:hlink><a:folHlink><a:srgbClr val="800080"/></a:folHlink></a:clrScheme>'
      '<a:fontScheme name="Office"><a:majorFont><a:latin typeface="Calibri"/><a:ea typeface=""/><a:cs typeface=""/></a:majorFont>'
      '<a:minorFont><a:latin typeface="Calibri"/><a:ea typeface=""/><a:cs typeface=""/></a:minorFont></a:fontScheme>'
      '<a:fmtScheme name="Office"><a:fillStyleLst>'
      '<a:solidFill><a:schemeClr val="phClr"/></a:solidFill><a:solidFill><a:schemeClr val="phClr"/></a:solidFill><a:solidFill><a:schemeClr val="phClr"/></a:solidFill>'
      '</a:fillStyleLst><a:lnStyleLst>'
      '<a:ln w="9525"><a:solidFill><a:schemeClr val="phClr"/></a:solidFill></a:ln><a:ln w="25400"><a:solidFill><a:schemeClr val="phClr"/></a:solidFill></a:ln><a:ln w="38100"><a:solidFill><a:schemeClr val="phClr"/></a:solidFill></a:ln>'
      '</a:lnStyleLst><a:effectStyleLst>'
      '<a:effectStyle><a:effectLst/></a:effectStyle><a:effectStyle><a:effectLst/></a:effectStyle><a:effectStyle><a:effectLst/></a:effectStyle>'
      '</a:effectStyleLst><a:bgFillStyleLst>'
      '<a:solidFill><a:schemeClr val="phClr"/></a:solidFill><a:solidFill><a:schemeClr val="phClr"/></a:solidFill><a:solidFill><a:schemeClr val="phClr"/></a:solidFill>'
      '</a:bgFillStyleLst></a:fmtScheme></a:themeElements></a:theme>';
}
