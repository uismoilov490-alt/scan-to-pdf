import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../services/pdf/pdf_toolkit.dart';
import '../../services/pdf_service.dart';
import '../../widgets/pdf_source_sheet.dart';
import '../../widgets/tool_widgets.dart';

/// PDF'ni bo'laklarga ajratadi: har bir sahifa alohida yoki "1-3, 5, 7-9"
/// kabi oraliqlar bo'yicha (har bir oraliq — alohida fayl).
class PdfSplitScreen extends StatefulWidget {
  const PdfSplitScreen({super.key});

  @override
  State<PdfSplitScreen> createState() => _PdfSplitScreenState();
}

/// "1-3, 5, 7-9" → [[0,1,2],[4],[6,7,8]] (0 dan); xato bo'lsa null.
List<List<int>>? parsePageRanges(String text, int pageCount) {
  final ranges = <List<int>>[];
  for (final part in text.split(RegExp(r'[,;]'))) {
    final t = part.trim();
    if (t.isEmpty) continue;
    final m = RegExp(r'^(\d+)\s*(?:[-–]\s*(\d+))?$').firstMatch(t);
    if (m == null) return null;
    final from = int.parse(m[1]!);
    final to = int.parse(m[2] ?? m[1]!);
    if (from < 1 || to > pageCount || from > to) return null;
    ranges.add([for (var p = from; p <= to; p++) p - 1]);
  }
  return ranges.isEmpty ? null : ranges;
}

class _PdfSplitScreenState extends State<PdfSplitScreen> {
  PickedPdf? _pdf;
  int _pages = 0;
  bool _each = true;
  final _ranges = TextEditingController();
  String? _rangeError;
  bool _busy = false;

  @override
  void dispose() {
    _ranges.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    final picked = await pickPdfBytes(context);
    if (picked == null) return;
    final pages = await PdfToolkit.pageCount(picked.bytes);
    if (mounted) {
      setState(() {
        _pdf = picked;
        _pages = pages;
        _rangeError = null;
      });
    }
  }

  Future<void> _split() async {
    final pdf = _pdf!;
    final ranges = _each
        ? [
            for (var i = 0; i < _pages; i++) [i],
          ]
        : parsePageRanges(_ranges.text, _pages);
    if (ranges == null) {
      setState(
        () => _rangeError = 'split_bad_range'.tr(namedArgs: {'max': '$_pages'}),
      );
      return;
    }
    setState(() => _busy = true);
    try {
      final parts = await PdfToolkit.split(pdf.bytes, ranges);
      for (var i = 0; i < parts.length; i++) {
        await PdfService.savePdfBytes(parts[i], '${pdf.name}_${i + 1}');
      }
      if (!mounted) return;
      showToolMessage(
        context,
        'files_saved'.tr(namedArgs: {'count': '${parts.length}'}),
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
      appBar: AppBar(title: Text('feature_pdf_split'.tr())),
      body: pdf == null
          ? ToolEmptyState(
              icon: Icons.call_split_rounded,
              title: 'feature_pdf_split'.tr(),
              hint: 'split_hint'.tr(),
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
                SegmentedButton<bool>(
                  segments: [
                    ButtonSegment(
                      value: true,
                      label: Text('split_mode_each'.tr()),
                    ),
                    ButtonSegment(
                      value: false,
                      label: Text('split_mode_ranges'.tr()),
                    ),
                  ],
                  selected: {_each},
                  onSelectionChanged: (s) => setState(() => _each = s.first),
                ),
                const SizedBox(height: 16),
                if (_each)
                  Text(
                    'split_each_info'.tr(namedArgs: {'count': '$_pages'}),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  )
                else
                  TextField(
                    controller: _ranges,
                    keyboardType: TextInputType.text,
                    onChanged: (_) {
                      if (_rangeError != null)
                        setState(() => _rangeError = null);
                    },
                    decoration: InputDecoration(
                      labelText: 'split_ranges_label'.tr(),
                      hintText: '1-3, 5, 7-9',
                      helperText: 'split_ranges_help'.tr(),
                      errorText: _rangeError,
                      border: const OutlineInputBorder(),
                    ),
                  ),
              ],
            ),
      bottomNavigationBar: pdf == null
          ? null
          : ToolActionBar(
              label: 'split_btn'.tr(),
              icon: Icons.call_split_rounded,
              busy: _busy,
              onPressed: _pages < 2 ? null : _split,
            ),
    );
  }
}
