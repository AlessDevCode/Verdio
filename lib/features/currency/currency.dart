import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/providers.dart';

class Currency {
  const Currency({required this.code, required this.name, required this.symbol, required this.decimals, required this.locale});
  final String code, name, symbol, locale;
  final int decimals;

  factory Currency.fromJson(Map<String, dynamic> j) => Currency(
        code: j['code'] as String,
        name: j['name'] as String,
        symbol: j['symbol'] as String,
        decimals: (j['decimals'] as num?)?.toInt() ?? 2,
        locale: (j['locale'] as String?) ?? 'en_US',
      );

  static const fallback = Currency(code: 'USD', name: 'US Dollar', symbol: r'$', decimals: 2, locale: 'en_US');
}

/// Carga assets/currencies.json (una sola vez).
final currenciesProvider = FutureProvider<List<Currency>>((ref) async {
  final raw = await rootBundle.loadString('assets/currencies.json');
  return (jsonDecode(raw) as List).map((e) => Currency.fromJson(e as Map<String, dynamic>)).toList();
});

/// Moneda elegida por el usuario (guardada en profiles.currency_code).
class CurrencyCodeNotifier extends AsyncNotifier<String> {
  @override
  Future<String> build() async {
    final uid = ref.watch(userIdProvider);
    if (uid == null) return 'USD';
    final r = await ref.read(supabaseProvider).from('profiles').select('currency_code').eq('id', uid).maybeSingle();
    return (r?['currency_code'] as String?) ?? 'USD';
  }

  Future<void> select(String code) async {
    final uid = ref.read(userIdProvider);
    if (uid == null) return;
    await ref.read(supabaseProvider).from('profiles').update({'currency_code': code}).eq('id', uid);
    state = AsyncData(code);
  }
}

final currencyCodeProvider = AsyncNotifierProvider<CurrencyCodeNotifier, String>(CurrencyCodeNotifier.new);

final currentCurrencyProvider = Provider<Currency>((ref) {
  final list = ref.watch(currenciesProvider).valueOrNull ?? const <Currency>[];
  final code = ref.watch(currencyCodeProvider).valueOrNull ?? 'USD';
  return list.firstWhere((c) => c.code == code, orElse: () => Currency.fallback);
});

/// Formateador global: `ref.watch(moneyProvider)(1234.5)` => "S/ 1,234.50"
final moneyProvider = Provider<String Function(num)>((ref) {
  final c = ref.watch(currentCurrencyProvider);
  final f = NumberFormat.currency(locale: c.locale, symbol: c.symbol, decimalDigits: c.decimals);
  return (n) => f.format(n);
});
