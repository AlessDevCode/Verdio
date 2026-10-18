import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/expenses/expense_repository.dart';
import '../features/fund/fund_repository.dart';
import '../features/periods/period_repository.dart';
import '../features/stats/stats_repository.dart';

/// Todo lo derivado de movimientos financieros. Las familias se invalidan completas.
final _financeProviders = <ProviderOrFamily>[
  periodsProvider,
  periodProvider,
  periodItemsProvider,
  periodExpensesProvider,
  fundBalanceProvider,
  fundFeedProvider,
  annualProvider,
];

/// Invalida Períodos, Caja General y Resumen Anual en un solo paso.
void invalidateFinance(WidgetRef ref) {
  for (final p in _financeProviders) {
    ref.invalidate(p);
  }
}

/// Igual que [invalidateFinance], pero con un [ProviderContainer] capturado antes de un `await`.
/// Permite refrescar los datos aunque la pantalla ya se haya cerrado mientras se esperaba.
void invalidateFinanceIn(ProviderContainer container) {
  for (final p in _financeProviders) {
    container.invalidate(p);
  }
}

/// Para pull-to-refresh: invalida y espera a que lo principal esté recargado.
Future<void> refreshFinance(WidgetRef ref) async {
  invalidateFinance(ref);
  await Future.wait([
    ref.read(periodsProvider.future),
    ref.read(fundBalanceProvider.future),
    ref.read(fundFeedProvider.future),
  ]);
}