import 'dart:io';
import 'package:flutter/material.dart';
import '../services/pdf_service.dart';

class DocumentProvider extends ChangeNotifier {
  List<File> _pdfs = [];
  bool _loading = false;

  List<File> get pdfs => _pdfs;
  bool get loading => _loading;

  Future<void> load() async {
    _loading = true;
    notifyListeners();
    try {
      _pdfs = await PdfService.listSavedPdfs();
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> delete(String path) async {
    await PdfService.deletePdf(path);
    _pdfs.removeWhere((f) => f.path == path);
    notifyListeners();
  }
}
