import 'dart:io';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../providers/subscription_provider.dart';
import '../../services/ai_service.dart';
import '../../widgets/ai_error.dart';

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
  // AI rejimi kirill va qo'lyozmani o'qiydi; tezkor rejim telefonda, bepul.
  bool _useAi = true;

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
      _text = null;
      _error = null;
    });
    await _recognize();
  }

  Future<void> _recognize() async {
    if (_image == null) return;
    setState(() {
      _processing = true;
      _text = null;
      _error = null;
    });
    try {
      final String text;
      if (_useAi) {
        final result = await AiService.ocr(await _image!.readAsBytes());
        if (mounted) context.read<SubscriptionProvider>().updateQuota(result.quota);
        text = result.text;
      } else {
        final result = await _recognizer.processImage(InputImage.fromFile(_image!));
        text = result.text;
      }
      if (mounted) {
        setState(() {
          _text = text;
          _processing = false;
        });
      }
    } on AiException catch (e) {
      if (!mounted) return;
      setState(() => _processing = false);
      await showAiError(context, e);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _processing = false;
        });
      }
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
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: theme.colorScheme.primary,
        foregroundColor: theme.colorScheme.onPrimary,
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
          _buildModeBar(theme),
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
            Text(
              'ocr_processing'.tr(),
              style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
            ),
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
        return Center(
          child: Text(
            'ocr_no_text'.tr(),
            style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
          ),
        );
      }
      return SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.45),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(
                  alpha: theme.brightness == Brightness.dark ? 0.35 : 0.06,
                ),
                blurRadius: 12,
              ),
            ],
          ),
          child: SelectableText(
            _text!,
            style: TextStyle(
              fontSize: 15,
              height: 1.7,
              color: theme.colorScheme.onSurface,
            ),
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
            Text(
              'ocr_hint'.tr(),
              textAlign: TextAlign.center,
              style: TextStyle(
                color: theme.colorScheme.onSurfaceVariant,
                fontSize: 15,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildModeBar(ThemeData theme) {
    final quota = context.watch<SubscriptionProvider>().quota;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SegmentedButton<bool>(
            segments: [
              ButtonSegment(
                value: true,
                icon: const Icon(Icons.auto_awesome, size: 18),
                label: Text('ocr_mode_ai'.tr()),
              ),
              ButtonSegment(
                value: false,
                icon: const Icon(Icons.bolt, size: 18),
                label: Text('ocr_mode_fast'.tr()),
              ),
            ],
            selected: {_useAi},
            onSelectionChanged: _processing
                ? null
                : (s) {
                    setState(() => _useAi = s.first);
                    if (_image != null) _recognize();
                  },
          ),
          const SizedBox(height: 6),
          Text(
            _useAi
                ? (quota != null
                    ? '${'ocr_ai_hint'.tr()} · ${'ai_quota_left'.tr(namedArgs: {
                          'remaining': '${quota.remaining}',
                          'limit': '${quota.limit}',
                        })}'
                    : 'ocr_ai_hint'.tr())
                : 'ocr_fast_hint'.tr(),
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12.5, color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
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
