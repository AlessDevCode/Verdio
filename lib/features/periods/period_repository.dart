import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/providers.dart';
import '../../core/utils/formatters.dart';
import 'models.dart';

/// Topes de una reposición, calculados en el servidor de forma atómica.
class ReplenishLimits {
  const ReplenishLimits({required this.deficit, required this.fund, required this.max});

  /// Lo que le falta al período para quedar en cero.
  final double deficit;

  /// Saldo real de la Caja General.
  final double fund;

  /// Máximo reponible = min(déficit, saldo de la Caja).
  final double max;
}

class PeriodRepository {
  PeriodRepository(this._c);
  final SupabaseClient _c;

  Future<List<Period>> list() async {
    final r = await _c.from('period_summary').select().order('start_date', ascending: false);
    return r.map<Period>(Period.fromMap).toList();
  }

  Future<Period?> get(String id) async {
    final r = await _c.from('period_summary').select().eq('id', id).maybeSingle();
    return r == null ? null : Period.fromMap(r);
  }

  Future<List<PeriodItem>> items(String periodId) async {
    final r = await _c.from('period_items').select().eq('period_id', periodId).order('created_at');
    return r.map<PeriodItem>(PeriodItem.fromMap).toList();
  }

  /// Agrega una partida a un período abierto. Si [increaseBudget] es true, el monto
  /// planificado también se suma al presupuesto del período (misma transacción).
  /// El servidor valida: período abierto, nombre único, categoría propia y monto >= 0.
  Future<String> addItem(
    String periodId, {
    required String name,
    String? categoryId,
    required double planned,
    bool increaseBudget = false,
  }) async {
    final id = await _c.rpc('add_period_item', params: {
      'p_period_id': periodId,
      'p_name': name,
      'p_category_id': categoryId,
      'p_planned': planned,
      'p_increase_budget': increaseBudget,
    });
    return id as String;
  }
  
  /// Edita nombre, categoría y monto planificado de una partida de un período abierto.
  /// [categoryId] == null deja la partida sin categoría. Si [adjustBudget] es true, el presupuesto
  /// del período se mueve en la misma diferencia que el monto planificado (misma transacción).
  Future<void> updateItem(
    String itemId, {
    required String name,
    String? categoryId,
    required double planned,
    bool adjustBudget = false,
  }) =>
      _c.rpc('update_period_item', params: {
        'p_item_id': itemId,
        'p_name': name,
        'p_category_id': categoryId,
        'p_planned': planned,
        'p_adjust_budget': adjustBudget,
      });

  Future<String> create({
    required String name,
    required PeriodKind kind,
    required DateTime start,
    required DateTime end,
    required double budget,
    String? templateId,
  }) async {
    final id = await _c.rpc('create_period', params: {
      'p_name': name,
      'p_kind': kind.name,
      'p_start': dbDate(start),
      'p_end': dbDate(end),
      'p_budget': budget,
      'p_template_id': templateId,
    });
    return id as String;
  }

  Future<void> delete(String id) => _c.from('periods').delete().eq('id', id);

  Future<void> close(String id, {required bool sendToFund}) =>
      _c.rpc('close_period', params: {'p_period_id': id, 'p_send_to_fund': sendToFund});

  /// Reabre un período cerrado; si había enviado remanente a la Caja, lo revierte.
  Future<void> reopen(String id) => _c.rpc('reopen_period', params: {'p_period_id': id});

  Future<void> sendRemainder(String id) => _c.rpc('send_remainder_to_fund', params: {'p_period_id': id});

  /// Reposición desde la Caja. El servidor rechaza montos mayores al déficit o al saldo de la Caja.
  Future<void> replenish(String id, double amount) =>
      _c.rpc('replenish_from_fund', params: {'p_period_id': id, 'p_amount': amount});

  /// Déficit del período, saldo de la Caja y máximo reponible (consulta fresca, no en caché).
  Future<ReplenishLimits> replenishLimits(String periodId) async {
    final r = await _c.rpc('replenish_limits', params: {'p_period_id': periodId});
    final rows = (r as List).cast<Map<String, dynamic>>();
    if (rows.isEmpty) throw Exception('Período no encontrado');
    final row = rows.first;
    return ReplenishLimits(
      deficit: num0(row['deficit']),
      fund: num0(row['fund']),
      max: num0(row['max_amount']),
    );
  }

  /// Inserta un movimiento real en la partida [itemId], o en "Otros gastos" si es null.
  Future<void> addBucketExpense(
    String periodId, {
    String? itemId,
    required double amount,
    String? note,
    required DateTime date,
    String? categoryId,
  }) =>
      _c.rpc('add_bucket_expense', params: {
        'p_period_id': periodId,
        'p_item_id': itemId,
        'p_amount': amount,
        'p_note': note,
        'p_date': dbDate(date),
        'p_category_id': categoryId,
      });

  /// Fija el total del cubo (sube con un ajuste, baja recortando lo más reciente).
  Future<void> setBucketTotal(String periodId, {String? itemId, required double total, required DateTime date}) =>
      _c.rpc('set_bucket_total', params: {
        'p_period_id': periodId,
        'p_item_id': itemId,
        'p_total': total,
        'p_date': dbDate(date),
      });
}

final periodRepositoryProvider = Provider((ref) => PeriodRepository(ref.watch(supabaseProvider)));

final periodsProvider = FutureProvider<List<Period>>((ref) {
  ref.watch(userIdProvider);
  return ref.watch(periodRepositoryProvider).list();
});

final periodProvider = FutureProvider.family<Period?, String>((ref, id) {
  ref.watch(userIdProvider);
  return ref.watch(periodRepositoryProvider).get(id);
});

final periodItemsProvider = FutureProvider.family<List<PeriodItem>, String>((ref, id) {
  ref.watch(userIdProvider);
  return ref.watch(periodRepositoryProvider).items(id);
});

/// Se descarta al cerrar el modal: cada apertura consulta topes frescos.
final replenishLimitsProvider = FutureProvider.autoDispose.family<ReplenishLimits, String>((ref, periodId) {
  ref.watch(userIdProvider);
  return ref.watch(periodRepositoryProvider).replenishLimits(periodId);
});