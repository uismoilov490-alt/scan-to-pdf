import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../services/pdf/pdf_toolkit.dart';
import '../../services/pdf_service.dart';
import '../../widgets/pdf_source_sheet.dart';
import '../../widgets/tool_widgets.dart';

/// Har bir sahifaga raqam qo'yadi ("3" yoki "3 / 10").
class PdfPageNumbersScreen extends StatefulWidget {
  const PdfPageNumbersScreen({super.key});

  @override
  State<PdfPageNumbersScreen> createState() => _PdfPageNumbersScreenState();
}

class _PdfPageNumbersScreenState extends State<PdfPageNumbersScreen> {
  PickedPdf? _pdf;
  int _pages = 0;
  var _position = PageNumberPosition.bottomCenter;
  bool _withTotal = true;
  bool _busy = false;

  Future<void> _pick() async {
    final picked = await pickPdfBytes(context);
    if (picked == null) return;
    final pages = await PdfToolkit.pageCount(picked.bytes);
    if (mounted) {
      setState(() {
        _pdf = picked;
        _pages = pages;
      });
    }
  }

  Future<void> _apply() async {
    final pdf = _pdf!;
    setState(() => _busy = true);
    try {
      final bytes = await PdfToolkit.pageNumbers(
        pdf.bytes,
        position: _position,
        withTotal: _withTotal,
      );
      final file = await PdfService.savePdfBytes(bytes, '${pdf.name}_numbered');
      if (!mounted) return;
      showToolMessage(
        context,
        'saved_as'.tr(namedArgs: {'name': file.uri.pathSegments.last}),
      );
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
    final pdf = _pdf;
    return Scaffold(
      appBar: AppBar(title: Text('feature_page_numbers'.tr())),
      body: pdf == null
          ? ToolEmptyState(
              icon: Icons.format_list_numbered_rounded,
              title: 'feature_page_numbers'.tr(),
              hint: 'page_numbers_hint'.tr(),
              buttonText: 'pick_pdf'.tr(),
              onPressed: _pick,
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                ToolFileCard(
                  name: pdf.name,
                  pages: _pages,
                  trailing: IconButton(
                    icon: const Icon(Icons.swap_horiz_rounded),
                    onPressed: _busy ? null : _pick,
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'page_numbers_position'.tr(),
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                SegmentedButton<PageNumberPosition>(
                  segments: [
                    ButtonSegment(
                      value: PageNumberPosition.bottomCenter,
                      icon: const Icon(Icons.vertical_align_bottom_rounded),
                      label: Text('pos_bottom_center'.tr()),
                    ),
                    ButtonSegment(
                      value: PageNumberPosition.bottomRight,
                      icon: const Icon(Icons.south_east_rounded),
                      label: Text('pos_bottom_right'.tr()),
                    ),
                    ButtonSegment(
                      value: PageNumberPosition.topRight,
                      icon: const Icon(Icons.north_east_rounded),
                      label: Text('pos_top_right'.tr()),
                    ),
                  ],
                  selected: {_position},
                  showSelectedIcon: false,
                  onSelectionChanged: (s) =>
                      setState(() => _position = s.first),
                ),
                const SizedBox(height: 12),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('page_numbers_total'.tr()),
                  subtitle: Text(_withTotal ? '1 / $_pages' : '1'),
                  value: _withTotal,
                  onChanged: (v) => setState(() => _withTotal = v),
                ),
              ],
            ),
      bottomNavigationBar: pdf == null
          ? null
          : ToolActionBar(
              label: 'save_pdf'.tr(),
              icon: Icons.check_rounded,
              busy: _busy,
              onPressed: _apply,
            ),
    );
  }
}
