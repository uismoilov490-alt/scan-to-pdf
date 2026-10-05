import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../services/pdf/pdf_toolkit.dart';
import '../../services/pdf_service.dart';
import '../../widgets/pdf_source_sheet.dart';
import '../../widgets/tool_widgets.dart';

/// PDF'ga ochish paroli qo'yadi ([lock] = true) yoki parolni olib tashlaydi.
class PdfSecurityScreen extends StatefulWidget {
  final bool lock;

  const PdfSecurityScreen({super.key, required this.lock});

  @override
  State<PdfSecurityScreen> createState() => _PdfSecurityScreenState();
}

class _PdfSecurityScreenState extends State<PdfSecurityScreen> {
  PickedPdf? _pdf;
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  String? _error;
  bool _busy = false;
  bool _obscure = true;

  bool get _lock => widget.lock;

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    // Qulfni ochishda parolni shu ekranning o'zi so'raydi
    final picked = await pickPdfBytes(context, unlock: false);
    if (picked == null) return;
    final locked = await PdfToolkit.needsPassword(picked.bytes);
    if (!mounted) return;
    if (locked == _lock) {
      showToolMessage(
        context,
        (_lock ? 'pdf_already_locked' : 'pdf_not_locked').tr(),
        error: true,
      );
      return;
    }
    setState(() {
      _pdf = picked;
      _error = null;
    });
  }

  Future<void> _run() async {
    final pdf = _pdf!;
    final password = _password.text;
    if (_lock && password.length < 4) {
      setState(() => _error = 'lock_too_short'.tr());
      return;
    }
    if (_lock && password != _confirm.text) {
      setState(() => _error = 'lock_mismatch'.tr());
      return;
    }
    setState(() => _busy = true);
    try {
      final bytes = _lock
          ? await PdfToolkit.protect(pdf.bytes, password)
          : await PdfToolkit.unlock(pdf.bytes, password);
      final file = await PdfService.savePdfBytes(
        bytes,
        '${pdf.name}_${_lock ? 'locked' : 'unlocked'}',
      );
      if (!mounted) return;
      showToolMessage(
        context,
        'saved_as'.tr(namedArgs: {'name': file.uri.pathSegments.last}),
      );
      Navigator.pop(context, true);
    } on PdfPasswordException {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = 'pdf_password_wrong'.tr();
        });
      }
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

  InputDecoration _field(String label, {String? error, Widget? suffix}) =>
      InputDecoration(
        labelText: label,
        errorText: error,
        suffixIcon: suffix,
        border: const OutlineInputBorder(),
      );

  @override
  Widget build(BuildContext context) {
    final pdf = _pdf;
    final title = (_lock ? 'feature_pdf_lock' : 'feature_pdf_unlock').tr();
    final icon = _lock ? Icons.lock_outline_rounded : Icons.lock_open_rounded;
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: pdf == null
          ? ToolEmptyState(
              icon: icon,
              title: title,
              hint: (_lock ? 'lock_hint' : 'unlock_hint').tr(),
              buttonText: 'pick_pdf'.tr(),
              onPressed: _pick,
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                ToolFileCard(
                  name: pdf.name,
                  trailing: IconButton(
                    icon: const Icon(Icons.swap_horiz_rounded),
                    onPressed: _busy ? null : _pick,
                  ),
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: _password,
                  obscureText: _obscure,
                  autofocus: true,
                  onChanged: (_) {
                    if (_error != null) setState(() => _error = null);
                  },
                  decoration: _field(
                    'lock_password'.tr(),
                    error: _lock ? null : _error,
                    suffix: IconButton(
                      icon: Icon(
                        _obscure
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                      ),
                      onPressed: () => setState(() => _obscure = !_obscure),
                    ),
                  ),
                ),
                if (_lock) ...[
                  const SizedBox(height: 14),
                  TextField(
                    controller: _confirm,
                    obscureText: _obscure,
                    onChanged: (_) {
                      if (_error != null) setState(() => _error = null);
                    },
                    decoration: _field('lock_confirm'.tr(), error: _error),
                  ),
                ],
              ],
            ),
      bottomNavigationBar: pdf == null
          ? null
          : ToolActionBar(
              label: (_lock ? 'lock_btn' : 'unlock_btn').tr(),
              icon: icon,
              busy: _busy,
              onPressed: _run,
            ),
    );
  }
}
