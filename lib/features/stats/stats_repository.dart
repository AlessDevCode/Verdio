import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/providers.dart';
import '../../core/utils/icons.dart';
import '../periods/models.dart';

class MonthStat {
  const MonthStat(this.month, this.spent, this.budget);
  final int month;
  final double spent, budget;
}

class CategoryStat {
  const CategoryStat(this.name, this.color, this.total);
  final String name;
  final Color color;
  final double total;
}

class AnnualData {
  const AnnualData(this.months, this.categories, this.fundSpent);
  final List<MonthStat> months;
  final List<CategoryStat> categories;

  /// Gastos directos de la Caja General (no pertenecen a ningún período).
  final double fundSpent;

  double get totalSpent => months.fold(0, (s, m) => s + m.spent);
  double get totalBudget => months.fold(0, (s, m) => s + m.budget);
  double get saved => totalBudget - totalSpent;
  double get monthlyAverage {
    final active = months.where((m) => m.spent > 0).length;
    return active == 0 ? 0 : totalSpent / active;
  }

  MonthStat? get peakMonth {
    final active = months.where((m) => m.spent > 0);
    return active.isEmpty ? null : active.reduce((a, b) => a.spent >= b.spent ? a : b);
  }
}

/// Resumen anual calculado con los MISMOS datos que la lista de períodos:
/// la vista `period_summary` (presupuesto y gasto reales por período) filtrada por `user_id`.
/// Cada período cuenta en el año y mes de su fecha de inicio, de modo que
/// la suma anual coincide exactamente con la suma de los períodos mostrados.
/// Las transferencias internas de la Caja nunca se consideran gasto.
class StatsRepository {
  StatsRepository(this._c);
  final SupabaseClient _c;

  List<Map<String, dynamic>> _rows(Object? data) => (data as List).cast<Map<String, dynamic>>();

  Future<AnnualData> annual(int year) async {
    final uid = _c.auth.currentUser?.id;
    if (uid == null) throw Exception('Sesión no válida. Vuelve a iniciar sesión.');
    final from = '$year-01-01';
    final to = '$year-12-31';

    final base = await Future.wait<Object?>([
      _c.from('period_summary').select('id, start_date, budget, spent').eq('user_id', uid).gte('start_date', from).lte('start_date', to),
      _c.from('expenses').select('amount').eq('user_id', uid).eq('source', 'fund').gte('spent_on', from).lte('spent_on', to),
      _c.from('categories').select('id, name, color').eq('user_id', uid),
    ]);
    final periodRows = _rows(base[0]);
    final fundRows = _rows(base[1]);
    final catRows = _rows(base[2]);

    // Totales por mes (según la fecha de inicio del período).
    final spent = List<double>.filled(12, 0);
    final budget = List<double>.filled(12, 0);
    final periodIds = <String>[];
    for (final r in periodRows) {
      final m = DateTime.parse(r['start_date'] as String).month - 1;
      spent[m] += num0(r['spent']);
      budget[m] += num0(r['budget']);
      periodIds.add(r['id'] as String);
    }
    final months = [for (var i = 0; i < 12; i++) MonthStat(i + 1, spent[i], budget[i])];

    // Desglose por categoría: gastos de esos mismos períodos.
    final byCategory = <String?, double>{};
    if (periodIds.isNotEmpty) {
      final rows = _rows(await _c
          .from('expenses')
          .select('amount, category_id')
          .eq('user_id', uid)
          .eq('source', 'period')
          .inFilter('period_id', periodIds));
      for (final r in rows) {
        final amount = num0(r['amount']);
        byCategory.update(r['category_id'] as String?, (v) => v + amount, ifAbsent: () => amount);
      }
    }
    final catMeta = {for (final c in catRows) c['id'] as String: c};
    final categories = [
      for (final entry in byCategory.entries)
        if (entry.value > 0)
          CategoryStat(
            catMeta[entry.key]?['name'] as String? ?? 'Sin categoría',
            colorFromHex(catMeta[entry.key]?['color'] as String?),
            entry.value,
          ),
    ]..sort((a, b) => b.total.compareTo(a.total));

    final fundSpent = fundRows.fold<double>(0, (s, r) => s + num0(r['amount']));
    return AnnualData(months, categories, fundSpent);
  }
}

final statsRepositoryProvider = Provider((ref) => StatsRepository(ref.watch(supabaseProvider)));
final statsYearProvider = StateProvider<int>((_) => DateTime.now().year);

final annualProvider = FutureProvider.family<AnnualData, int>((ref, year) {
  ref.watch(userIdProvider);
  return ref.watch(statsRepositoryProvider).annual(year);
});