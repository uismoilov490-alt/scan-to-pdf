import 'dart:io';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';

class OcrScreen extends StatefulWidget {
  const OcrScreen({super.key});

  @override
  State<OcrScreen> createState() => _OcrScreenState();
}

class _OcrScreenState extends State<OcrScreen> {
  File? _image;
  String? _text;
  bool _processing = false;
  String? _error;

  final _picker = ImagePicker();
  final _recognizer = TextRecognizer(script: TextRecognitionScript.latin);

  @override
  void dispose() {
    _recognizer.close();
    super.dispose();
  }

  Future<void> _pick(ImageSource source) async {
    final xfile = await _picker.pickImage(source: source, imageQuality: 95);
    if (xfile == null) return;
    setState(() {
      _image = File(xfile.path);
      _processing = true;
      _text = null;
      _error = null;
    });
    try {
      final inputImage = InputImage.fromFile(_image!);
      final result = await _recognizer.processImage(inputImage);
      if (mounted) setState(() { _text = result.text; _processing = false; });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _processing = false; });
    }
  }

  Future<void> _copy() async {
    if (_text == null) return;
    await Clipboard.setData(ClipboardData(text: _text!));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('ocr_copied'.tr()), duration: const Duration(seconds: 2)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        backgroundColor: theme.colorScheme.primary,
        foregroundColor: Colors.white,
        title: Text('ocr_title'.tr()),
        actions: [
          if (_text != null && _text!.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.copy),
              tooltip: 'ocr_copy'.tr(),
              onPressed: _copy,
            ),
        ],
      ),
      body: Column(
        children: [
          if (_image != null)
            SizedBox(
              height: 180,
              width: double.infinity,
              child: ColoredBox(
                color: Colors.black,
                child: Image.file(_image!, fit: BoxFit.contain),
              ),
            ),
          Expanded(child: _buildContent(theme)),
          _buildActions(theme),
        ],
      ),
    );
  }

  Widget _buildContent(ThemeData theme) {
    if (_processing) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text('ocr_processing'.tr(), style: TextStyle(color: Colors.grey[600])),
          ],
        ),
      );
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 52, color: Colors.red),
              const SizedBox(height: 12),
              Text(_error!, style: const TextStyle(color: Colors.red), textAlign: TextAlign.center),
            ],
          ),
        ),
      );
    }
    if (_text != null) {
      if (_text!.isEmpty) {
        return Center(child: Text('ocr_no_text'.tr(), style: TextStyle(color: Colors.grey[600])));
      }
      return SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 12)],
          ),
          child: SelectableText(
            _text!,
            style: const TextStyle(fontSize: 15, height: 1.7),
          ),
        ),
      );
    }
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.chrome_reader_mode_outlined, size: 80,
                color: theme.colorScheme.primary.withValues(alpha: 0.35)),
            const SizedBox(height: 20),
            Text('ocr_hint'.tr(),
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey[600], fontSize: 15)),
          ],
        ),
      ),
    );
  }

  Widget _buildActions(ThemeData theme) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _pick(ImageSource.camera),
                icon: const Icon(Icons.camera_alt),
                label: Text('camera'.tr()),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _pick(ImageSource.gallery),
                icon: const Icon(Icons.photo_library),
                label: Text('gallery'.tr()),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
