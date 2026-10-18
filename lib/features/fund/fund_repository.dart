import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/providers.dart';
import '../expenses/expense_repository.dart';
import '../periods/models.dart';

/// remainderIn: remanente de un período · replenishment: transferencia a un período
/// deposit: ingreso externo · expense: gasto directo de la Caja
enum FundEntryKind { remainderIn, replenishment, deposit, expense }

/// Tipo de ingreso a la Caja. El fondo inicial es único por usuario.
enum DepositKind { initial, extra, savings }

extension DepositKindX on DepositKind {
  String get label => switch (this) {
        DepositKind.initial => 'Fondo inicial',
        DepositKind.extra => 'Ingreso extra',
        DepositKind.savings => 'Ahorro',
      };
}

DepositKind depositKindFromDb(String? v) =>
    DepositKind.values.firstWhere((k) => k.name == v, orElse: () => DepositKind.extra);

/// Línea unificada del historial de la Caja General.
class FundEntry {
  const FundEntry({
    required this.id,
    required this.kind,
    required this.title,
    required this.amount,
    required this.date,
    this.periodId,
    this.depositKind,
    this.expense,
  });

  final String id; // id del movimiento o del gasto, según [kind]
  final FundEntryKind kind;
  final String title;
  final double amount; // siempre positivo
  final DateTime date;
  final String? periodId; // remanentes y reposiciones pertenecen a un período
  final DepositKind? depositKind; // solo para ingresos
  final Expense? expense; // solo para gastos directos

  bool get isIncome => kind == FundEntryKind.remainderIn || kind == FundEntryKind.deposit;

  /// Movimientos entre la Caja y los períodos: jamás cuentan como gasto.
  bool get isInternalTransfer => kind == FundEntryKind.remainderIn || kind == FundEntryKind.replenishment;

  /// Movimientos cuyo monto y nota se pueden editar directamente.
  bool get isEditableMovement => kind == FundEntryKind.replenishment || kind == FundEntryKind.deposit;

  bool get isInitialFund => kind == FundEntryKind.deposit && depositKind == DepositKind.initial;
}

/// Estado de la Caja que decide qué tipos de ingreso están disponibles.
class FundStatus {
  const FundStatus({required this.hasInitial, required this.isEmpty});
  final bool hasInitial;
  final bool isEmpty;

  /// Tipos de ingreso que el usuario puede registrar ahora mismo.
  List<DepositKind> get availableKinds {
    if (!hasInitial && isEmpty) return const [DepositKind.initial]; // Caja vacía: solo fondo inicial
    if (!hasInitial) return const [DepositKind.initial, DepositKind.extra, DepositKind.savings];
    return const [DepositKind.extra, DepositKind.savings]; // el fondo inicial ya no vuelve
  }
}

class FundRepository {
  FundRepository(this._c);
  final SupabaseClient _c;

  Future<double> balance() async => num0(await _c.rpc('get_fund_balance'));

  FundEntry _fromMovement(Map<String, dynamic> m) {
    final kind = switch (m['type']) {
      'remainder_in' => FundEntryKind.remainderIn,
      'deposit_in' => FundEntryKind.deposit,
      _ => FundEntryKind.replenishment,
    };
    final dep = kind == FundEntryKind.deposit ? depositKindFromDb(m['deposit_kind'] as String?) : null;
    return FundEntry(
      id: m['id'] as String,
      kind: kind,
      title: (m['note'] as String?) ??
          switch (kind) {
            FundEntryKind.remainderIn => 'Remanente recibido',
            FundEntryKind.deposit => dep!.label,
            _ => 'Reposición',
          },
      amount: num0(m['amount']),
      date: DateTime.parse(m['created_at'] as String).toLocal(),
      periodId: m['period_id'] as String?,
      depositKind: dep,
    );
  }

  FundEntry _fromExpense(Map<String, dynamic> e) => FundEntry(
        id: e['id'] as String,
        kind: FundEntryKind.expense,
        title: ((e['description'] as String?)?.isNotEmpty ?? false) ? e['description'] as String : 'Gasto directo',
        amount: num0(e['amount']),
        date: DateTime.parse(e['spent_on'] as String),
        expense: Expense.fromMap(e),
      );

  Future<List<FundEntry>> feed() async {
    final mv = await _c.from('fund_movements').select().order('created_at', ascending: false);
    final ex = await _c.from('expenses').select().eq('source', 'fund').order('spent_on', ascending: false);
    return [...mv.map(_fromMovement), ...ex.map(_fromExpense)]..sort((a, b) => b.date.compareTo(a.date));
  }

  /// Ingreso a la Caja. El servidor valida: un solo fondo inicial y "primero el fondo inicial" si la Caja está vacía.
  Future<double> deposit(double amount, DepositKind kind, String? note) async =>
      num0(await _c.rpc('deposit_to_fund', params: {'p_amount': amount, 'p_kind': kind.name, 'p_note': note}));

  /// Edita monto y nota de una reposición o de un ingreso.
  Future<void> updateMovement(String id, double amount, String? note) =>
      _c.rpc('update_fund_movement', params: {'p_id': id, 'p_amount': amount, 'p_note': note});

  /// Elimina una reposición o un ingreso, o revierte el envío de un remanente.
  Future<void> deleteMovement(String id) => _c.rpc('delete_fund_movement', params: {'p_id': id});
}

final fundRepositoryProvider = Provider((ref) => FundRepository(ref.watch(supabaseProvider)));

final fundBalanceProvider = FutureProvider<double>((ref) {
  ref.watch(userIdProvider);
  return ref.watch(fundRepositoryProvider).balance();
});

final fundFeedProvider = FutureProvider<List<FundEntry>>((ref) {
  ref.watch(userIdProvider);
  return ref.watch(fundRepositoryProvider).feed();
});

/// Derivado del historial: se refresca solo cada vez que cambia la Caja.
final fundStatusProvider = Provider<AsyncValue<FundStatus>>((ref) {
  return ref.watch(fundFeedProvider).whenData(
        (list) => FundStatus(
          hasInitial: list.any((e) => e.depositKind == DepositKind.initial),
          isEmpty: list.isEmpty,
        ),
      );
});