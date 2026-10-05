import 'dart:async';
import 'dart:ui' show Size;

import 'package:camera/camera.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_barcode_scanning/google_mlkit_barcode_scanning.dart';
import 'package:image_picker/image_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../widgets/tool_widgets.dart';

/// QR va shtrix-kod skaneri (kamera oqimi yoki galereyadagi rasm; internetsiz,
/// Google ML Kit).
class QrScannerScreen extends StatefulWidget {
  const QrScannerScreen({super.key});

  @override
  State<QrScannerScreen> createState() => _QrScannerScreenState();
}

class _QrScannerScreenState extends State<QrScannerScreen> {
  final _scanner = BarcodeScanner();
  CameraController? _camera;
  bool _busy = false; // kadr qayta ishlanmoqda
  bool _showing = false; // natija oynasi ochiq
  bool _torch = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    try {
      final cameras = await availableCameras();
      final back = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      final camera = CameraController(
        back,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.nv21,
      );
      await camera.initialize();
      if (!mounted) {
        await camera.dispose();
        return;
      }
      setState(() => _camera = camera);
      await camera.startImageStream(_onFrame);
    } on CameraException catch (e) {
      if (mounted) setState(() => _error = e.description ?? e.code);
    }
  }

  @override
  void dispose() {
    _camera?.dispose();
    _scanner.close();
    super.dispose();
  }

  /// Bir vaqtda faqat bitta kadr tahlil qilinadi — ortiqchasi tashlab yuboriladi.
  Future<void> _onFrame(CameraImage frame) async {
    final camera = _camera;
    if (_busy || _showing || camera == null) return;
    _busy = true;
    try {
      final input = InputImage.fromBytes(
        bytes: frame.planes.first.bytes,
        metadata: InputImageMetadata(
          size: Size(frame.width.toDouble(), frame.height.toDouble()),
          rotation:
              InputImageRotationValue.fromRawValue(
                camera.description.sensorOrientation,
              ) ??
              InputImageRotation.rotation0deg,
          format: InputImageFormat.nv21,
          bytesPerRow: frame.planes.first.bytesPerRow,
        ),
      );
      final codes = await _scanner.processImage(input);
      await _show(codes);
    } finally {
      _busy = false;
    }
  }

  Future<void> _show(List<Barcode> codes) async {
    final code = codes.where((c) => (c.rawValue ?? '').isNotEmpty).firstOrNull;
    if (code == null || _showing || !mounted) return;
    _showing = true;
    HapticFeedback.mediumImpact();
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerLow,
      builder: (_) => _ResultSheet(code),
    );
    _showing = false;
  }

  Future<void> _fromGallery() async {
    final image = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (image == null) return;
    final codes = await _scanner.processImage(
      InputImage.fromFilePath(image.path),
    );
    if (!mounted) return;
    if (codes.every((c) => (c.rawValue ?? '').isEmpty)) {
      showToolMessage(context, 'qr_not_found'.tr(), error: true);
      return;
    }
    await _show(codes);
  }

  Future<void> _toggleTorch() async {
    final camera = _camera;
    if (camera == null) return;
    _torch = !_torch;
    await camera.setFlashMode(_torch ? FlashMode.torch : FlashMode.off);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final camera = _camera;
    const white = Colors.white;
    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Text('feature_qr'.tr()),
        backgroundColor: Colors.transparent,
        foregroundColor: white,
        actions: [
          IconButton(
            icon: Icon(
              _torch
                  ? Icons.flashlight_off_outlined
                  : Icons.flashlight_on_outlined,
            ),
            onPressed: _toggleTorch,
          ),
          IconButton(
            icon: const Icon(Icons.photo_library_outlined),
            onPressed: _fromGallery,
          ),
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (camera != null && camera.value.isInitialized)
            FittedBox(
              fit: BoxFit.cover,
              child: SizedBox(
                // Oldindan ko'rish tik holatda: eni va bo'yi almashadi
                width: camera.value.previewSize!.height,
                height: camera.value.previewSize!.width,
                child: CameraPreview(camera),
              ),
            )
          else if (_error != null)
            Center(
              child: Text(
                _error!,
                style: const TextStyle(color: white),
                textAlign: TextAlign.center,
              ),
            ),
          // Yorug' tasvirda ham sarlavha va tugmalar ko'rinsin
          const Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: 160,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0x99000000), Color(0x00000000)],
                ),
              ),
            ),
          ),
          Center(
            child: Container(
              width: 250,
              height: 250,
              decoration: BoxDecoration(
                border: Border.all(color: white, width: 3),
                borderRadius: BorderRadius.circular(24),
              ),
            ),
          ),
          Positioned(
            left: 24,
            right: 24,
            bottom: 48,
            child: Text(
              'qr_hint'.tr(),
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: white,
                fontSize: 15,
                shadows: [Shadow(blurRadius: 6)],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ResultSheet extends StatelessWidget {
  final Barcode code;

  const _ResultSheet(this.code);

  @override
  Widget build(BuildContext context) {
    final value = code.rawValue!;
    final wifi = code.value is BarcodeWifi ? code.value as BarcodeWifi : null;
    final (IconData icon, String? openUri) = switch (code.type) {
      BarcodeType.url => (
        Icons.link_rounded,
        (code.value as BarcodeUrl?)?.url ?? value,
      ),
      BarcodeType.phone => (
        Icons.phone_outlined,
        value.startsWith('tel:') ? value : 'tel:$value',
      ),
      BarcodeType.email => (
        Icons.email_outlined,
        value.startsWith('mailto:') ? value : 'mailto:$value',
      ),
      BarcodeType.sms => (Icons.sms_outlined, value),
      BarcodeType.geoCoordinates => (Icons.place_outlined, value),
      BarcodeType.wifi => (Icons.wifi_rounded, null),
      _ => (Icons.qr_code_2_rounded, null),
    };
    final shown = wifi != null
        ? '${wifi.ssid ?? ''}\n${'lock_password'.tr()}: ${wifi.password ?? ''}'
        : value;

    void copy(String text) {
      Clipboard.setData(ClipboardData(text: text));
      showToolMessage(context, 'ocr_copied'.tr());
    }

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(icon, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 10),
                Text(
                  'qr_result'.tr(),
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SelectableText(
              shown,
              style: const TextStyle(fontSize: 16, height: 1.4),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (openUri != null)
                  FilledButton.icon(
                    onPressed: () => launchUrl(
                      Uri.parse(openUri),
                      mode: LaunchMode.externalApplication,
                    ),
                    icon: const Icon(Icons.open_in_new_rounded),
                    label: Text('open_file'.tr()),
                  ),
                OutlinedButton.icon(
                  onPressed: () => copy(wifi?.password ?? value),
                  icon: const Icon(Icons.copy_rounded),
                  label: Text('ocr_copy'.tr()),
                ),
                OutlinedButton.icon(
                  onPressed: () => Share.share(value),
                  icon: const Icon(Icons.share_outlined),
                  label: Text('share'.tr()),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
