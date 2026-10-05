import 'dart:typed_data';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../services/pdf/pdf_toolkit.dart';
import '../../services/pdf_service.dart';
import '../../widgets/pdf_source_sheet.dart';
import '../../widgets/tool_widgets.dart';

/// Bir nechta PDF'ni tanlangan tartibda bitta faylga birlashtiradi
/// (sahifalar sifati va matni o'zgarmaydi).
class PdfMergeScreen extends StatefulWidget {
  const PdfMergeScreen({super.key});

  @override
  State<PdfMergeScreen> createState() => _PdfMergeScreenState();
}

class _Item {
  static int _next = 0;
  final int id = _next++;
  final String name;
  final Uint8List bytes;
  final int pages;

  _Item(this.name, this.bytes, this.pages);
}

class _PdfMergeScreenState extends State<PdfMergeScreen> {
  final List<_Item> _items = [];
  bool _busy = false;

  Future<void> _add() async {
    final picked = await pickPdfBytes(context);
    if (picked == null) return;
    final pages = await PdfToolkit.pageCount(picked.bytes);
    if (mounted)
      setState(() => _items.add(_Item(picked.name, picked.bytes, pages)));
  }

  Future<void> _merge() async {
    setState(() => _busy = true);
    try {
      final bytes = await PdfToolkit.merge([for (final i in _items) i.bytes]);
      final file = await PdfService.savePdfBytes(
        bytes,
        '${_items.first.name}_merged',
      );
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
    final total = _items.fold<int>(0, (s, i) => s + i.pages);
    return Scaffold(
      appBar: AppBar(title: Text('feature_pdf_merge'.tr())),
      body: _items.isEmpty
          ? ToolEmptyState(
              icon: Icons.call_merge_rounded,
              title: 'feature_pdf_merge'.tr(),
              hint: 'merge_hint'.tr(),
              buttonText: 'merge_add'.tr(),
              onPressed: _add,
            )
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
                  child: Row(
                    children: [
                      Text(
                        'pages_count'.tr(namedArgs: {'count': '$total'}),
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const Spacer(),
                      TextButton.icon(
                        onPressed: _busy ? null : _add,
                        icon: const Icon(Icons.add_rounded),
                        label: Text('merge_add'.tr()),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ReorderableListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                    itemCount: _items.length,
                    onReorderItem: (from, to) => setState(
                      () => _items.insert(to, _items.removeAt(from)),
                    ),
                    itemBuilder: (_, i) {
                      final item = _items[i];
                      return Padding(
                        key: ValueKey(item.id),
                        padding: const EdgeInsets.only(bottom: 10),
                        child: ToolFileCard(
                          name: item.name,
                          pages: item.pages,
                          trailing: IconButton(
                            icon: const Icon(Icons.close_rounded),
                            onPressed: _busy
                                ? null
                                : () => setState(() => _items.removeAt(i)),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
      bottomNavigationBar: _items.isEmpty
          ? null
          : ToolActionBar(
              label: _items.length < 2
                  ? 'merge_need_two'.tr()
                  : 'merge_btn'.tr(),
              icon: Icons.call_merge_rounded,
              busy: _busy,
              onPressed: _items.length < 2 ? null : _merge,
            ),
    );
  }
}
