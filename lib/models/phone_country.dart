/// Minimal phone-region metadata for international dialing (E.164 prefix).
class PhoneCountry {
  const PhoneCountry({
    required this.iso2,
    required this.englishName,
    required this.dialDigits,
  });

  /// Empty when user enters a dial code manually without picking a flag row.
  final String iso2;
  final String englishName;

  /// Country calling code digits only (no "+").
  final String dialDigits;

  bool get isManualOnly => iso2.isEmpty;

  String get flagEmoji => PhoneCountry.flagFromIso2(iso2);

  /// Unicode regional-indicator flag from ISO 3166-1 alpha-2; globe fallback.
  static String flagFromIso2(String iso2) {
    if (iso2.length != 2) return '🌐';
    final code = iso2.toUpperCase();
    final first = code.codeUnitAt(0);
    final second = code.codeUnitAt(1);
    if (first < 65 ||
        first > 90 ||
        second < 65 ||
        second > 90) {
      return '🌐';
    }
    const base = 0x1F1E6;
    return String.fromCharCodes([base + first - 65, base + second - 65]);
  }

  static const uz = PhoneCountry(
    iso2: 'UZ',
    englishName: 'Uzbekistan',
    dialDigits: '998',
  );

  PhoneCountry copyWith({
    String? iso2,
    String? englishName,
    String? dialDigits,
  }) {
    return PhoneCountry(
      iso2: iso2 ?? this.iso2,
      englishName: englishName ?? this.englishName,
      dialDigits: dialDigits ?? this.dialDigits,
    );
  }

  /// Manual dial row — name comes from localization at UI layer.
  factory PhoneCountry.manualDial(String digits) {
    final d = digits.replaceAll(RegExp(r'\D'), '');
    return PhoneCountry(iso2: '', englishName: '', dialDigits: d);
  }
}
