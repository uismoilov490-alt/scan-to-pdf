import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

/// PDF tanlash oynasi: telefondagi istalgan PDF (Telegram, Yuklanmalar...)
/// yoki ilovaning o'zi saqlagan PDF'lar. Bekor qilinsa null qaytadi.
Future<File?> pickPdf(BuildContext context, List<File> saved) async {
  final choice = await showModalBottomSheet<Object>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (sheetCtx) => _PdfSourceSheet(saved: saved),
  );

  if (choice is File) return choice;
  if (choice != _deviceChoice) return null;

  final result = await FilePicker.platform.pickFiles(
    type: FileType.custom,
    allowedExtensions: const ['pdf'],
  );
  final path = result?.files.single.path;
  return path == null ? null : File(path);
}

const _deviceChoice = 'device';

class _PdfSourceSheet extends StatelessWidget {
  final List<File> saved;

  const _PdfSourceSheet({required this.saved});

  String _formatSize(int bytes) {
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final maxHeight = MediaQuery.of(context).size.height * 0.7;

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        children: [
          Card(
            elevation: 0,
            color: cs.primaryContainer,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 6,
              ),
              leading: Icon(
                Icons.folder_open_rounded,
                color: cs.onPrimaryContainer,
                size: 30,
              ),
              title: Text(
                'pick_from_device'.tr(),
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: cs.onPrimaryContainer,
                ),
              ),
              subtitle: Text(
                'pick_from_device_hint'.tr(),
                style: TextStyle(
                  color: cs.onPrimaryContainer.withValues(alpha: 0.8),
                ),
              ),
              trailing: Icon(Icons.chevron_right, color: cs.onPrimaryContainer),
              onTap: () => Navigator.pop(context, _deviceChoice),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'saved_in_app'.tr(),
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: cs.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          if (saved.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                'no_saved_pdf'.tr(),
                style: TextStyle(color: cs.onSurfaceVariant),
              ),
            )
          else
            for (final f in saved)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.picture_as_pdf, color: cs.error),
                title: Text(f.path.split(Platform.pathSeparator).last),
                subtitle: Text(_formatSize(f.statSync().size)),
                onTap: () => Navigator.pop(context, f),
              ),
        ],
      ),
    );
  }
}
