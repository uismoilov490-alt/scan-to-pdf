import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/phone_country.dart';
import '../services/phone_country_catalog.dart';

Future<PhoneCountry?> showPhoneCountryPickerSheet(
  BuildContext context, {
  required List<PhoneCountry> countries,
  PhoneCountry? selected,
}) {
  return showModalBottomSheet<PhoneCountry>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.45),
    builder: (ctx) => _PhoneCountryPickerSheet(
      countries: countries,
      selected: selected,
    ),
  );
}

class _PhoneCountryPickerSheet extends StatefulWidget {
  const _PhoneCountryPickerSheet({
    required this.countries,
    required this.selected,
  });

  final List<PhoneCountry> countries;
  final PhoneCountry? selected;

  @override
  State<_PhoneCountryPickerSheet> createState() =>
      _PhoneCountryPickerSheetState();
}

class _PhoneCountryPickerSheetState extends State<_PhoneCountryPickerSheet> {
  late List<PhoneCountry> _filtered;
  final _search = TextEditingController();
  final _manualDial = TextEditingController();
  final _manualFocus = FocusNode();
  bool _manualOpen = false;

  @override
  void initState() {
    super.initState();
    _filtered = List<PhoneCountry>.from(widget.countries);
    _search.addListener(_applySearch);
  }

  @override
  void dispose() {
    _search.removeListener(_applySearch);
    _search.dispose();
    _manualDial.dispose();
    _manualFocus.dispose();
    super.dispose();
  }

  void _applySearch() {
    setState(() {
      _filtered = PhoneCountryCatalog.filter(widget.countries, _search.text);
    });
  }

  void _confirmManual() {
    final digits = _manualDial.text.replaceAll(RegExp(r'\D'), '');
    if (!_validDialDigits(digits)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('auth_error_invalid_country_code'.tr()),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    Navigator.of(context).pop(PhoneCountry.manualDial(digits));
  }

  static bool _validDialDigits(String digits) {
    if (digits.isEmpty) return false;
    return RegExp(r'^[1-9]\d{0,5}$').hasMatch(digits) && digits.length <= 6;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final screenH = MediaQuery.of(context).size.height;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        constraints: BoxConstraints(maxHeight: screenH * 0.92),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.18),
              blurRadius: 28,
              offset: const Offset(0, -8),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            Container(
              width: 44,
              height: 5,
              decoration: BoxDecoration(
                color: cs.onSurfaceVariant.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 18, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'auth_country_picker_title'.tr(),
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.4,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                    style: IconButton.styleFrom(
                      foregroundColor: cs.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 22),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                child: _manualOpen
                    ? _ManualDialCard(
                        key: const ValueKey('manual'),
                        controller: _manualDial,
                        focusNode: _manualFocus,
                        colorScheme: cs,
                        onCancel: () => setState(() {
                          _manualOpen = false;
                          _manualDial.clear();
                        }),
                        onApply: _confirmManual,
                      )
                    : _SearchField(
                        key: const ValueKey('search'),
                        controller: _search,
                        colorScheme: cs,
                      ),
              ),
            ),
            const SizedBox(height: 12),
            if (!_manualOpen)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 22),
                child: SizedBox(
                  width: double.infinity,
                  child: TextButton.icon(
                    onPressed: () {
                      setState(() {
                        _manualOpen = true;
                        _search.clear();
                        _filtered = List<PhoneCountry>.from(widget.countries);
                      });
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        _manualFocus.requestFocus();
                      });
                    },
                    icon: Icon(Icons.dialpad_rounded, color: cs.primary),
                    label: Text(
                      'auth_country_manual_entry'.tr(),
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: cs.primary,
                      ),
                    ),
                  ),
                ),
              ),
            if (!_manualOpen)
              Expanded(
                child: Scrollbar(
                  thumbVisibility: true,
                  radius: const Radius.circular(99),
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 22),
                    itemCount: _filtered.length,
                    itemBuilder: (context, index) {
                      final c = _filtered[index];
                      final sel = widget.selected != null &&
                          widget.selected!.iso2 == c.iso2 &&
                          widget.selected!.dialDigits == c.dialDigits &&
                          !widget.selected!.isManualOnly;
                      return Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 3,
                        ),
                        child: Material(
                          color: sel
                              ? cs.primary.withValues(alpha: 0.09)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(16),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(16),
                            onTap: () => Navigator.of(context).pop(c),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 12,
                              ),
                              child: Row(
                                children: [
                                  Text(
                                    c.flagEmoji,
                                    style: const TextStyle(fontSize: 26),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      c.englishName,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 15,
                                        color: cs.onSurface,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 6,
                                    ),
                                    decoration: BoxDecoration(
                                      color: cs.surfaceContainerHigh,
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Text(
                                      '+${c.dialDigits}',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w800,
                                        fontFeatures: const [
                                          FontFeature.tabularFigures(),
                                        ],
                                        color: cs.onSurface,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            if (_manualOpen) const Spacer(),
          ],
        ),
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({
    super.key,
    required this.controller,
    required this.colorScheme,
  });

  final TextEditingController controller;
  final ColorScheme colorScheme;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        hintText: 'auth_country_search_hint'.tr(),
        prefixIcon: Icon(
          Icons.search_rounded,
          color: colorScheme.onSurfaceVariant,
        ),
        filled: true,
        fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.55),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: colorScheme.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: colorScheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: colorScheme.primary, width: 1.8),
        ),
      ),
    );
  }
}

class _ManualDialCard extends StatelessWidget {
  const _ManualDialCard({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.colorScheme,
    required this.onCancel,
    required this.onApply,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final ColorScheme colorScheme;
  final VoidCallback onCancel;
  final VoidCallback onApply;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            colorScheme.primary.withValues(alpha: 0.08),
            colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
          ],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'auth_country_manual_hint'.tr(),
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 13,
              color: colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                height: 52,
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: colorScheme.outlineVariant),
                ),
                child: Text(
                  '+',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 20,
                    color: colorScheme.onSurface,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: controller,
                  focusNode: focusNode,
                  keyboardType: TextInputType.phone,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9]')),
                    LengthLimitingTextInputFormatter(6),
                  ],
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 18,
                    letterSpacing: 0.6,
                    color: colorScheme.onSurface,
                  ),
                  decoration: InputDecoration(
                    hintText: '998',
                    filled: true,
                    fillColor: colorScheme.surfaceContainerHigh,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(color: colorScheme.outlineVariant),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(
                        color: colorScheme.primary,
                        width: 1.8,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: onCancel,
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: Text('auth_country_manual_back'.tr()),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: onApply,
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: Text('auth_country_manual_apply'.tr()),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
