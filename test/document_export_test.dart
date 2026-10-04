import 'package:flutter_test/flutter_test.dart';
import 'package:scan_to_pdf/services/document_export_service.dart';

void main() {
  test('Word: yozilgan matn qayta o\'qilganda o\'zgarmaydi', () {
    const text = 'Ariza\nToshkent shahar, 2026-yil\n\nМен, Исмоилов У., & <test>';
    final docx = DocumentExportService.buildDocx(text);
    expect(DocumentExportService.docxText(docx), text.trim());
  });

  test('Word: RTL (arab) xatboshi belgisi qo\'shiladi va matn saqlanadi', () {
    const text = 'مرحبا بالعالم';
    final docx = DocumentExportService.buildDocx(text, rtl: true);
    expect(DocumentExportService.docxText(docx), text);
  });

  test('Word: boshqaruv belgilari olib tashlanadi (XML buzilmasin)', () {
    final docx = DocumentExportService.buildDocx('salom\u0001dunyo');
    expect(DocumentExportService.docxText(docx), 'salomdunyo');
  });
}
