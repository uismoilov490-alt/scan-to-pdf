import 'dart:io';
import 'package:camera/camera.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import '../preview_screen.dart';

enum ScanOverlayMode { passport, idCard }

class OverlayCameraScreen extends StatefulWidget {
  final ScanOverlayMode mode;

  const OverlayCameraScreen({super.key, required this.mode});

  @override
  State<OverlayCameraScreen> createState() => _OverlayCameraScreenState();
}

class _OverlayCameraScreenState extends State<OverlayCameraScreen> {
  CameraController? _controller;
  bool _initialized = false;
  bool _capturing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  Future<void> _initCamera() async {
    final status = await Permission.camera.request();
    if (!status.isGranted) {
      if (mounted) setState(() => _error = 'camera_permission_denied'.tr());
      return;
    }
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        if (mounted) setState(() => _error = 'no_camera_found'.tr());
        return;
      }
      _controller = CameraController(
        cameras.first,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );
      await _controller!.initialize();
      if (mounted) setState(() => _initialized = true);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _capture() async {
    if (_controller == null || !_initialized || _capturing) return;
    setState(() => _capturing = true);
    try {
      final picture = await _controller!.takePicture();
      if (!mounted) return;
      final wasSaved = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (_) => PreviewScreen(pages: [File(picture.path)]),
        ),
      );
      if (wasSaved == true && mounted) Navigator.pop(context, true);
    } finally {
      if (mounted) setState(() => _capturing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.mode == ScanOverlayMode.passport
        ? 'passport_scan_title'.tr()
        : 'id_card_scan_title'.tr();
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black54,
        foregroundColor: Colors.white,
        title: Text(title),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.no_photography_outlined,
                size: 64,
                color: Colors.white54,
              ),
              const SizedBox(height: 16),
              Text(
                _error!,
                style: const TextStyle(color: Colors.white70),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () => Navigator.pop(context),
                child: Text('back'.tr()),
              ),
            ],
          ),
        ),
      );
    }
    if (!_initialized) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        CameraPreview(_controller!),
        CustomPaint(painter: _OverlayPainter(mode: widget.mode)),
        _buildHint(),
        _buildCaptureButton(),
      ],
    );
  }

  Widget _buildHint() {
    final hint = widget.mode == ScanOverlayMode.passport
        ? 'passport_position_hint'.tr()
        : 'id_card_position_hint'.tr();
    return Positioned(
      bottom: 130,
      left: 24,
      right: 24,
      child: Text(
        hint,
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 14,
          shadows: [Shadow(color: Colors.black54, blurRadius: 6)],
        ),
      ),
    );
  }

  Widget _buildCaptureButton() {
    return Positioned(
      bottom: 40,
      left: 0,
      right: 0,
      child: Center(
        child: GestureDetector(
          onTap: _capturing ? null : _capture,
          child: Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white70, width: 4),
              boxShadow: const [
                BoxShadow(color: Colors.black38, blurRadius: 8),
              ],
            ),
            child: _capturing
                ? const Padding(
                    padding: EdgeInsets.all(18),
                    child: CircularProgressIndicator(strokeWidth: 3),
                  )
                : const Icon(Icons.camera_alt, size: 34, color: Colors.black87),
          ),
        ),
      ),
    );
  }
}

class _OverlayPainter extends CustomPainter {
  final ScanOverlayMode mode;

  const _OverlayPainter({required this.mode});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = _guideRect(size);

    // Semi-transparent overlay with cutout
    final overlayPaint = Paint()..color = Colors.black.withValues(alpha: 0.55);
    final outer = Path()..addRect(Rect.fromLTWH(0, 0, size.width, size.height));
    final inner = Path()
      ..addRRect(RRect.fromRectAndRadius(rect, const Radius.circular(8)));
    canvas.drawPath(
      Path.combine(PathOperation.difference, outer, inner),
      overlayPaint,
    );

    // White border around guide
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(8)),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.85)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );

    // Corner marks
    final corner = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    const L = 22.0;
    final tl = rect.topLeft;
    final tr = rect.topRight;
    final bl = rect.bottomLeft;
    final br = rect.bottomRight;
    canvas
      ..drawLine(tl, tl + const Offset(L, 0), corner)
      ..drawLine(tl, tl + const Offset(0, L), corner)
      ..drawLine(tr, tr - const Offset(L, 0), corner)
      ..drawLine(tr, tr + const Offset(0, L), corner)
      ..drawLine(bl, bl + const Offset(L, 0), corner)
      ..drawLine(bl, bl - const Offset(0, L), corner)
      ..drawLine(br, br - const Offset(L, 0), corner)
      ..drawLine(br, br - const Offset(0, L), corner);
  }

  Rect _guideRect(Size size) {
    // Passport: 125×88mm → ratio 1.42:1 (landscape)
    // ID Card:  85.6×54mm → ratio 1.585:1 (landscape)
    final w = size.width * 0.82;
    final ratio = mode == ScanOverlayMode.passport ? 1.42 : 1.585;
    final h = w / ratio;
    return Rect.fromCenter(
      center: Offset(size.width / 2, size.height * 0.44),
      width: w,
      height: h,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
