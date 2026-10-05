import 'dart:typed_data';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../services/pdf/pdf_toolkit.dart';

/// PDF parol bilan himoyalangan bo'lsa parol so'raydi va himoyasiz nusxasini
/// qaytaradi; himoyasiz bo'lsa o'zini qaytaradi; bekor qilinsa — null.
Future<Uint8List?> unlockPdfIfNeeded(
  BuildContext context,
  Uint8List pdf,
) async {
  if (!await PdfToolkit.needsPassword(pdf)) return pdf;
  if (!context.mounted) return null;
  return showDialog<Uint8List>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _PasswordDialog(pdf),
  );
}

class _PasswordDialog extends StatefulWidget {
  final Uint8List pdf;

  const _PasswordDialog(this.pdf);

  @override
  State<_PasswordDialog> createState() => _PasswordDialogState();
}

class _PasswordDialogState extends State<_PasswordDialog> {
  final _controller = TextEditingController();
  bool _wrong = false;
  bool _busy = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy || _controller.text.isEmpty) return;
    setState(() => _busy = true);
    try {
      final open = await PdfToolkit.unlock(widget.pdf, _controller.text);
      if (mounted) Navigator.pop(context, open);
    } on PdfPasswordException {
      if (mounted) {
        setState(() {
          _wrong = true;
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      icon: const Icon(Icons.lock_outline_rounded),
      title: Text('pdf_password_title'.tr()),
      content: TextField(
        controller: _controller,
        autofocus: true,
        obscureText: true,
        onChanged: (_) {
          if (_wrong) setState(() => _wrong = false);
        },
        onSubmitted: (_) => _submit(),
        decoration: InputDecoration(
          hintText: 'pdf_password_hint'.tr(),
          errorText: _wrong ? 'pdf_password_wrong'.tr() : null,
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: Text('cancel'.tr()),
        ),
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: _busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text('continue_btn'.tr()),
        ),
      ],
    );
  }
}
