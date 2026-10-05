import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:gal/gal.dart';
import 'package:path/path.dart' as p;

import '../../services/image_convert_service.dart';
import '../../services/photo_stamp_service.dart';
import '../../widgets/image_source_sheet.dart';
import '../../widgets/tool_widgets.dart';

/// Fotoga surat olingan sana-vaqtni yozadi (EXIF'dan; bo'lmasa fayl vaqti).
class PhotoTimestampScreen extends StatefulWidget {
  const PhotoTimestampScreen({super.key});

  @override
  State<PhotoTimestampScreen> createState() => _PhotoTimestampScreenState();
}

class _PhotoTimestampScreenState extends State<PhotoTimestampScreen> {
  List<File> _photos = [];
  bool _withTime = true;
  bool _busy = false;
  int _done = 0;

  String get _pattern => _withTime ? 'dd.MM.yyyy  HH:mm' : 'dd.MM.yyyy';

  Future<void> _pick() async {
    final photos = await pickImages(context);
    if (photos.isNotEmpty && mounted) setState(() => _photos = photos);
  }

  Future<void> _apply() async {
    setState(() {
      _busy = true;
      _done = 0;
    });
    try {
      if (!await Gal.hasAccess()) await Gal.requestAccess();
      for (final photo in _photos) {
        final prepared = await PhotoStampService.prepare(photo);
        final text = DateFormat(_pattern).format(prepared.takenAt);
        final stamped = await PhotoStampService.stamp(prepared.jpeg, text);
        final out = await ImageConvertService.saveImage(
          stamped,
          '${p.basenameWithoutExtension(photo.path)}_time',
        );
        await Gal.putImage(out.path, album: 'Scan to PDF');
        if (mounted) setState(() => _done++);
      }
      if (!mounted) return;
      showToolMessage(context, 'conv_saved_gallery'.tr());
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      showToolMessage(
        context,
        'error_prefix'.tr(namedArgs: {'message': '$e'}),
        error: true,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text('feature_timestamp'.tr())),
      body: _photos.isEmpty
          ? ToolEmptyState(
              icon: Icons.schedule_rounded,
              title: 'feature_timestamp'.tr(),
              hint: 'timestamp_hint'.tr(),
              buttonText: 'conv_pick_images'.tr(),
              onPressed: _pick,
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Birinchi rasm va yoziladigan joyning ko'rinishi
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Stack(
                    children: [
                      Image.file(_photos.first, fit: BoxFit.cover),
                      Positioned(
                        right: 12,
                        bottom: 10,
                        child: Text(
                          DateFormat(
                            _pattern,
                          ).format(_photos.first.lastModifiedSync()),
                          style: const TextStyle(
                            color: Color(0xFFFF9F0A),
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            shadows: [
                              Shadow(color: Colors.black87, blurRadius: 4),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'conv_selected'.tr(namedArgs: {'count': '${_photos.length}'}),
                  style: TextStyle(color: cs.onSurfaceVariant),
                ),
                const SizedBox(height: 16),
                SegmentedButton<bool>(
                  segments: [
                    ButtonSegment(
                      value: true,
                      label: Text('timestamp_date_time'.tr()),
                    ),
                    ButtonSegment(
                      value: false,
                      label: Text('timestamp_date_only'.tr()),
                    ),
                  ],
                  selected: {_withTime},
                  onSelectionChanged: (s) =>
                      setState(() => _withTime = s.first),
                ),
                const SizedBox(height: 12),
                Text(
                  'timestamp_source_note'.tr(),
                  style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
                ),
              ],
            ),
      bottomNavigationBar: _photos.isEmpty
          ? null
          : ToolActionBar(
              label: _busy
                  ? 'conv_converting'.tr(
                      namedArgs: {
                        'done': '$_done',
                        'total': '${_photos.length}',
                      },
                    )
                  : 'conv_save_gallery'.tr(),
              icon: Icons.photo_library_outlined,
              busy: _busy,
              onPressed: _apply,
            ),
    );
  }
}
