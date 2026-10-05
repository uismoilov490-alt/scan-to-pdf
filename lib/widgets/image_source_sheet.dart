import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

/// Kamera yoki galereyadan rasm(lar) tanlash; bekor qilinsa — bo'sh ro'yxat.
Future<List<File>> pickImages(
  BuildContext context, {
  bool multiple = true,
}) async {
  final camera = await showModalBottomSheet<bool>(
    context: context,
    showDragHandle: true,
    backgroundColor: Theme.of(context).colorScheme.surfaceContainerLow,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.photo_camera_outlined),
            title: Text('camera'.tr()),
            onTap: () => Navigator.pop(ctx, true),
          ),
          ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: Text('gallery'.tr()),
            onTap: () => Navigator.pop(ctx, false),
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
  if (camera == null) return [];
  final picker = ImagePicker();
  if (camera) {
    final shot = await picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 95,
    );
    return shot == null ? [] : [File(shot.path)];
  }
  if (!multiple) {
    final one = await picker.pickImage(source: ImageSource.gallery);
    return one == null ? [] : [File(one.path)];
  }
  return [for (final x in await picker.pickMultiImage()) File(x.path)];
}
