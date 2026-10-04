import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../models/translate_language.dart';

/// Tarjima tilini tanlash oynasi: qidiruv, ko'p ishlatiladiganlar va to'liq ro'yxat.
/// [allowAuto] — "Avtomatik aniqlash" bandi (faqat manba til uchun).
Future<String?> pickTranslateLanguage(
  BuildContext context, {
  required String selected,
  bool allowAuto = false,
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => _LanguagePicker(selected: selected, allowAuto: allowAuto),
  );
}

class _LanguagePicker extends StatefulWidget {
  final String selected;
  final bool allowAuto;

  const _LanguagePicker({required this.selected, required this.allowAuto});

  @override
  State<_LanguagePicker> createState() => _LanguagePickerState();
}

class _LanguagePickerState extends State<_LanguagePicker> {
  String _query = '';

  bool _matches(TranslateLanguage l) {
    if (_query.isEmpty) return true;
    final q = _query.toLowerCase();
    return [
      l.nativeName,
      l.uz,
      l.ru,
      l.en,
      l.code,
    ].any((s) => s.toLowerCase().contains(q));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final locale = context.locale.languageCode;
    final popular = TranslateLanguage.popularCodes
        .map(TranslateLanguage.byCode)
        .whereType<TranslateLanguage>()
        .where(_matches)
        .toList();
    final rest =
        TranslateLanguage.all
            .where((l) => !TranslateLanguage.popularCodes.contains(l.code))
            .where(_matches)
            .toList()
          ..sort((a, b) => a.localName(locale).compareTo(b.localName(locale)));

    Widget tile(String code, String title, String? subtitle, {IconData? icon}) {
      final isSelected = code == widget.selected;
      return ListTile(
        leading: icon != null ? Icon(icon, color: cs.primary) : null,
        title: Text(
          title,
          style: TextStyle(
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
        subtitle: subtitle == null || subtitle == title ? null : Text(subtitle),
        trailing: isSelected
            ? Icon(Icons.check_circle, color: cs.primary)
            : null,
        selected: isSelected,
        onTap: () => Navigator.pop(context, code),
      );
    }

    Widget header(String text) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Text(
        text,
        style: TextStyle(
          fontWeight: FontWeight.w700,
          color: cs.onSurfaceVariant,
          fontSize: 13,
        ),
      ),
    );

    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.8,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: TextField(
              autofocus: false,
              decoration: InputDecoration(
                hintText: 'translate_search_language'.tr(),
                prefixIcon: const Icon(Icons.search),
                filled: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
              ),
              onChanged: (v) => setState(() => _query = v.trim()),
            ),
          ),
          Expanded(
            child: ListView(
              children: [
                if (widget.allowAuto && _query.isEmpty)
                  tile(
                    TranslateLanguage.auto,
                    'translate_auto_detect'.tr(),
                    null,
                    icon: Icons.auto_awesome,
                  ),
                if (popular.isNotEmpty) header('translate_popular'.tr()),
                for (final l in popular)
                  tile(l.code, l.nativeName, l.localName(locale)),
                if (rest.isNotEmpty) header('translate_all_languages'.tr()),
                for (final l in rest)
                  tile(l.code, l.nativeName, l.localName(locale)),
                if (popular.isEmpty && rest.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Center(child: Text('translate_no_language'.tr())),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
