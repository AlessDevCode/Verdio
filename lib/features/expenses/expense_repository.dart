import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/providers.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/icons.dart';
import '../periods/models.dart';

class Category {
  const Category({required this.id, required this.name, required this.icon, required this.color});
  final String id, name;
  final IconData icon;
  final Color color;

  factory Category.fromMap(Map<String, dynamic> m) => Category(
        id: m['id'] as String,
        name: m['name'] as String,
        icon: iconFor(m['icon'] as String?),
        color: colorFromHex(m['color'] as String?),
      );
}

class Expense {
  const Expense({required this.id, required this.description, required this.amount, required this.date,
      this.categoryId, this.plannedItemId, this.fromFund = false});
  final String id, description;
  final double amount;
  final DateTime date;
  final String? categoryId, plannedItemId;
  final bool fromFund;

  factory Expense.fromMap(Map<String, dynamic> m) => Expense(
        id: m['id'] as String,
        description: (m['description'] as String?) ?? '',
        amount: num0(m['amount']),
        date: DateTime.parse(m['spent_on'] as String),
        categoryId: m['category_id'] as String?,
        plannedItemId: m['planned_item_id'] as String?,
        fromFund: m['source'] == 'fund',
      );
}

class ExpenseRepository {
  ExpenseRepository(this._c);
  final SupabaseClient _c;

  Future<List<Category>> categories() async {
    final r = await _c.from('categories').select().order('name');
    return r.map<Category>(Category.fromMap).toList();
  }

  Future<List<Expense>> byPeriod(String periodId) async {
    final r = await _c.from('expenses').select().eq('period_id', periodId)
        .order('spent_on', ascending: false).order('created_at', ascending: false);
    return r.map<Expense>(Expense.fromMap).toList();
  }

  /// Si [periodId] es null y no es de la Caja, la BD asigna el período según la fecha real.
  Future<void> add({
    required double amount,
    required String description,
    required DateTime date,
    String? categoryId,
    String? periodId,
    String? plannedItemId,
    bool fromFund = false,
  }) =>
      _c.from('expenses').insert({
        'amount': amount,
        'description': description,
        'spent_on': dbDate(date),
        'category_id': categoryId,
        'planned_item_id': plannedItemId,
        'source': fromFund ? 'fund' : 'period',
        if (!fromFund && periodId != null) 'period_id': periodId,
      });

  Future<void> delete(String id) => _c.from('expenses').delete().eq('id', id);
  
  Future<void> update(
    String id, {
    required double amount,
    required String description,
    required DateTime date,
    String? categoryId,
  }) =>
      _c.from('expenses').update({
        'amount': amount,
        'description': description,
        'spent_on': dbDate(date),
        'category_id': categoryId,
      }).eq('id', id);
}

final expenseRepositoryProvider = Provider((ref) => ExpenseRepository(ref.watch(supabaseProvider)));

final categoriesProvider = FutureProvider<List<Category>>((ref) {
  ref.watch(userIdProvider);
  return ref.watch(expenseRepositoryProvider).categories();
});

final periodExpensesProvider = FutureProvider.family<List<Expense>, String>((ref, id) {
  ref.watch(userIdProvider);
  return ref.watch(expenseRepositoryProvider).byPeriod(id);
});
