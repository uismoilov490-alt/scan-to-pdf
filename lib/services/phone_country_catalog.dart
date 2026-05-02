import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

import '../models/phone_country.dart';

/// Loads and caches ~world-scale calling-code rows from bundled REST-derived JSON.
abstract final class PhoneCountryCatalog {
  static const _assetPath = 'assets/data/country_phone_rest.json';

  static List<PhoneCountry>? _cache;

  static Future<List<PhoneCountry>> ensureLoaded() async {
    if (_cache != null) return _cache!;
    final raw = await rootBundle.loadString(_assetPath);
    final decoded = jsonDecode(raw) as List<dynamic>;
    _cache = _parse(decoded);
    return _cache!;
  }

  /// Case-insensitive match on English name, ISO2, or dial digits (with or without "+").
  static List<PhoneCountry> filter(List<PhoneCountry> all, String query) {
    final q = query.trim().toLowerCase().replaceFirst('+', '');
    if (q.isEmpty) return List<PhoneCountry>.from(all);
    return all.where((c) {
      return c.englishName.toLowerCase().contains(q) ||
          c.iso2.toLowerCase().contains(q) ||
          c.dialDigits.contains(q);
    }).toList();
  }

  static void _add(
    List<PhoneCountry> out,
    Set<String> seen,
    String iso,
    String name,
    String dial,
  ) {
    if (dial.isEmpty) return;
    if (!RegExp(r'^[1-9]\d*$').hasMatch(dial)) return;
    if (dial.length > 6) return;
    final key = '$iso|$dial';
    if (!seen.add(key)) return;
    out.add(PhoneCountry(iso2: iso, englishName: name, dialDigits: dial));
  }

  static List<PhoneCountry> _parse(List<dynamic> raw) {
    final out = <PhoneCountry>[];
    final seen = <String>{};

    for (final dynamic item in raw) {
      final map = item as Map<String, dynamic>;
      final iso = map['cca2'] as String? ?? '';
      if (iso.isEmpty || iso == 'AQ' || iso == 'HM') continue;

      final nameMap = map['name'] as Map<String, dynamic>?;
      final name = nameMap?['common'] as String? ?? iso;

      final idd = map['idd'] as Map<String, dynamic>?;
      final root = (idd?['root'] as String?) ?? '';
      final suffixes =
          (idd?['suffixes'] as List<dynamic>?)?.map((e) => '$e').toList() ??
              const <String>[];

      final rd = root.replaceAll('+', '');
      if (rd.isEmpty) continue;

      if (iso == 'US') {
        _add(out, seen, iso, name, '1');
        continue;
      }
      if (iso == 'RU' || iso == 'KZ') {
        _add(out, seen, iso, name, '7');
        continue;
      }

      if (rd == '1') {
        if (suffixes.isEmpty || suffixes.every((s) => s.isEmpty)) {
          _add(out, seen, iso, name, '1');
        } else {
          for (final s in suffixes) {
            if (s.isEmpty) {
              _add(out, seen, iso, name, '1');
            } else {
              _add(out, seen, iso, name, '1$s');
            }
          }
        }
        continue;
      }

      if (suffixes.isEmpty || suffixes.every((s) => s.isEmpty)) {
        _add(out, seen, iso, name, rd);
      } else {
        for (final s in suffixes) {
          if (s.isEmpty) {
            _add(out, seen, iso, name, rd);
          } else {
            _add(out, seen, iso, name, '$rd$s');
          }
        }
      }
    }

    out.sort((a, b) {
      final byName = a.englishName.compareTo(b.englishName);
      if (byName != 0) return byName;
      return a.dialDigits.compareTo(b.dialDigits);
    });
    return out;
  }
}
