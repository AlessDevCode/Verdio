import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/refresh.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/errors.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/common.dart';
import '../currency/currency.dart';
import '../expenses/add_expense_sheet.dart';
import '../expenses/expense_repository.dart';
import 'bucket_sheet.dart';
import 'models.dart';
import 'period_repository.dart';
import 'replenish_sheet.dart';
import 'add_item_sheet.dart';

enum _PeriodView { items, history }

class PeriodDetailPage extends ConsumerWidget {
  const PeriodDetailPage({super.key, required this.periodId});
  final String periodId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final period = ref.watch(periodProvider(periodId));
    return period.when(
      loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(
        appBar: AppBar(),
        body: EmptyState(icon: Icons.error_outline, title: 'Error', message: friendlyError(e)),
      ),
      data: (p) {
        if (p == null) {
          return Scaffold(
            appBar: AppBar(),
            body: const EmptyState(icon: Icons.search_off_rounded, title: 'Período no encontrado'),
          );
        }
        return _Body(p);
      },
    );
  }
}

class _Body extends ConsumerStatefulWidget {
  const _Body(this.p);
  final Period p;
  @override
  ConsumerState<_Body> createState() => _BodyState();
}

class _BodyState extends ConsumerState<_Body> {
  _PeriodView _view = _PeriodView.items;
  Period get p => widget.p;

  // ---------------------------------------------------------------- helpers
  /// Ejecuta una acción de negocio y refresca Períodos, Caja y Resumen anual.
  /// El container se captura antes del await: los datos se refrescan aunque la pantalla ya no esté montada.
  Future<void> _guard(Future<void> Function() action, String ok) async {
    final container = ProviderScope.containerOf(context);
    try {
      await action();
      invalidateFinanceIn(container);
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      showSnack(context, ok);
    } catch (e) {
      if (!mounted) return;
      showSnack(context, friendlyError(e), error: true);
    }
  }

  Future<bool?> _confirm({
    required String title,
    required String message,
    required String confirmLabel,
    bool danger = false,
  }) =>
      showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
            FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size(0, 44), backgroundColor: danger ? AppColors.danger : null),
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(confirmLabel),
            ),
          ],
        ),
      );

  // ---------------------------------------------------------------- acciones
  Future<void> _close() async {
    final fmt = ref.read(moneyProvider);
    final hasRem = p.balance > 0;
    final hasDeficit = p.balance < 0;
    final choice = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Cerrar "${p.name}"'),
        content: Text(hasRem
            ? 'Remanente: ${fmt(p.balance)}.\n\nSi lo envías a la Caja General ahora, no podrá reenviarse (salvo que reabras el período). Un período cerrado no admite más gastos.'
            : hasDeficit
                ? 'El período tiene un déficit de ${fmt(-p.balance)}. Podrás cubrirlo con una reposición desde la Caja después de cerrarlo.'
                : 'El período no tiene remanente. Una vez cerrado no admitirá más gastos.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          if (hasRem) TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cerrar sin enviar')),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
            onPressed: () => Navigator.pop(ctx, hasRem),
            child: Text(hasRem ? 'Cerrar y enviar' : 'Cerrar'),
          ),
        ],
      ),
    );
    if (choice == null || !mounted) return;
    await _guard(() => ref.read(periodRepositoryProvider).close(p.id, sendToFund: choice), 'Período cerrado');
  }

  Future<void> _reopen() async {
    final fmt = ref.read(moneyProvider);
    final ok = await _confirm(
      title: 'Reabrir "${p.name}"',
      message: p.remainderSent
          ? 'El remanente de ${fmt(p.remainderAmount ?? 0)} enviado a la Caja General se revertirá (la Caja debe tener ese saldo disponible). El período volverá a aceptar gastos.'
          : 'El período volverá a aceptar gastos y movimientos.',
      confirmLabel: 'Reabrir',
    );
    if (ok != true || !mounted) return;
    await _guard(() => ref.read(periodRepositoryProvider).reopen(p.id), 'Período reabierto');
  }

  Future<void> _sendRemainder() async {
    final fmt = ref.read(moneyProvider);
    final ok = await _confirm(
      title: 'Enviar remanente',
      message: 'Se enviarán ${fmt(p.balance)} a la Caja General. Solo se puede enviar una vez (a menos que reabras el período).',
      confirmLabel: 'Enviar',
    );
    if (ok != true || !mounted) return;
    await _guard(() => ref.read(periodRepositoryProvider).sendRemainder(p.id), 'Remanente enviado a la Caja General');
  }

  Future<void> _replenish() => showReplenishSheet(context, period: p);

  Future<void> _deletePeriod() async {
    final ok = await _confirm(
      title: 'Eliminar período',
      message: 'Se eliminarán también sus gastos. Esta acción no se puede deshacer.',
      confirmLabel: 'Eliminar',
      danger: true,
    );
    if (ok != true || !mounted) return;
    final container = ProviderScope.containerOf(context);
    try {
      await ref.read(periodRepositoryProvider).delete(p.id);
      invalidateFinanceIn(container);
      if (!mounted) return;
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      showSnack(context, friendlyError(e), error: true);
    }
  }

  Future<void> _deleteExpense(Expense e) =>
      _guard(() => ref.read(expenseRepositoryProvider).delete(e.id), 'Movimiento eliminado');

  // ---------------------------------------------------------------- secciones
  List<Widget> _buildActions(String Function(num) fmt) {
    final deficit = p.balance < 0;
    if (!p.isClosed) {
      return [
        Row(children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _replenish,
              icon: const Icon(Icons.south_west_rounded),
              label: const Text('Reponer'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: FilledButton.icon(
              onPressed: _close,
              icon: const Icon(Icons.lock_outline_rounded),
              label: const Text('Cerrar'),
            ),
          ),
        ]),
      ];
    }
    return [
      if (deficit) ...[
        AppCard(
          child: Row(children: [
            const Icon(Icons.warning_amber_rounded, color: AppColors.danger),
            const SizedBox(width: 10),
            Expanded(child: Text('Este período cerró con un déficit de ${fmt(-p.balance)}.')),
          ]),
        ),
        const SizedBox(height: 10),
        FilledButton.icon(
          onPressed: _replenish,
          icon: const Icon(Icons.south_west_rounded),
          label: const Text('Reponer'),
        ),
        const SizedBox(height: 10),
      ],
      if (p.canSendRemainder) ...[
        FilledButton.icon(
          onPressed: _sendRemainder,
          icon: const Icon(Icons.north_east_rounded),
          label: Text('Enviar ${fmt(p.balance)} a la Caja'),
        ),
        const SizedBox(height: 10),
      ],
      if (p.remainderSent) ...[
        AppCard(
          child: Row(children: [
            const Icon(Icons.check_circle_rounded, color: AppColors.emerald),
            const SizedBox(width: 10),
            Expanded(
              child: Text('Remanente de ${fmt(p.remainderAmount ?? 0)} enviado a la Caja el ${longDate(p.remainderSentAt!.toLocal())}'),
            ),
          ]),
        ),
        const SizedBox(height: 10),
      ],
      OutlinedButton.icon(
        onPressed: _reopen,
        icon: const Icon(Icons.lock_open_rounded),
        label: const Text('Reabrir período'),
      ),
    ];
  }

  List<Widget> _itemsView({
    required List<PeriodItem> items,
    required Map<String, Category> cats,
    required Map<String, double> spentByItem,
    required double looseTotal,
    required int looseCount,
    required double plannedTotal,
  }) =>
      [
        // Resumen de planificación: se recalcula solo al agregar partidas o cambiar el presupuesto.
        if (items.isNotEmpty || !p.isClosed) ...[
          const SizedBox(height: 14),
          _PlanSummary(planned: plannedTotal, available: p.available),
        ],
        SectionTitle(
          items.isEmpty ? 'Gastos' : 'Partidas',
          trailing: p.isClosed
              ? null
              : TextButton.icon(
                  onPressed: () => showAddItemSheet(context, period: p),
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('Partida'),
                ),
        ),
        for (final it in items)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _ItemCard(
              item: it,
              spent: spentByItem[it.id] ?? 0,
              category: cats[it.categoryId],
              editable: !p.isClosed,
              onTap: () => showBucketSheet(context, period: p, item: it),
            ),
          ),
        if (!p.isClosed || looseCount > 0)
          _LooseCard(
            total: looseTotal,
            count: looseCount,
            editable: !p.isClosed,
            onTap: () => showBucketSheet(context, period: p),
          ),
      ];

  List<Widget> _historyView({
    required List<Expense> history,
    required bool loading,
    required Map<String, PeriodItem> itemsById,
    required Map<String, Category> cats,
  }) {
    final out = <Widget>[SectionTitle('Historial del período (${history.length})')];
    if (loading && history.isEmpty) {
      return [...out, const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))];
    }
    if (history.isEmpty) {
      return [
        ...out,
        const Padding(
          padding: EdgeInsets.all(24),
          child: Text('Aún no hay gastos en este período.', textAlign: TextAlign.center, style: TextStyle(color: AppColors.muted)),
        ),
      ];
    }
    // `history` ya llega ordenado por fecha desc. (y creación desc.) desde la consulta SQL.
    DateTime? last;
    for (final e in history) {
      if (last == null || last != e.date) {
        out.add(Padding(
          padding: const EdgeInsets.fromLTRB(4, 10, 4, 6),
          child: Text(longDate(e.date), style: const TextStyle(color: AppColors.muted, fontWeight: FontWeight.w700, fontSize: 12)),
        ));
        last = e.date;
      }
      out.add(Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: _HistoryTile(
          expense: e,
          itemName: itemsById[e.plannedItemId]?.name,
          category: cats[e.categoryId],
          editable: !p.isClosed,
          onEdit: () => showAddExpenseSheet(context, period: p, editing: e),
          onDelete: () => _deleteExpense(e),
        ),
      ));
    }
    return out;
  }

  // ---------------------------------------------------------------- build
  @override
  Widget build(BuildContext context) {
    final fmt = ref.watch(moneyProvider);
    final expenses = ref.watch(periodExpensesProvider(p.id));
    final items = ref.watch(periodItemsProvider(p.id)).valueOrNull ?? const <PeriodItem>[];
    final cats = {for (final c in ref.watch(categoriesProvider).valueOrNull ?? const <Category>[]) c.id: c};
    final itemsById = {for (final i in items) i.id: i};
    final list = expenses.valueOrNull ?? const <Expense>[];

    final spentByItem = <String, double>{};
    var looseTotal = 0.0;
    var looseCount = 0;
    for (final e in list) {
      if (e.amount <= 0) continue;
      final id = e.plannedItemId;
      if (id != null) {
        spentByItem.update(id, (v) => v + e.amount, ifAbsent: () => e.amount);
      } else {
        looseTotal += e.amount;
        looseCount++;
      }
    }
    final history = list.where((e) => e.amount > 0).toList();
    final plannedTotal = items.fold<double>(0, (s, i) => s + i.planned);

    return Scaffold(
      appBar: AppBar(
        title: Text(p.name),
        actions: [
          if (!p.isClosed)
            PopupMenuButton<String>(
              onSelected: (v) => v == 'delete' ? _deletePeriod() : null,
              itemBuilder: (_) => const [PopupMenuItem(value: 'delete', child: Text('Eliminar período'))],
            ),
        ],
      ),
      floatingActionButton: p.isClosed
          ? null
          : FloatingActionButton.extended(
              icon: const Icon(Icons.add_rounded),
              label: const Text('Gasto'),
              onPressed: () => showBucketSheet(context, period: p),
            ),
      body: RefreshIndicator(
        onRefresh: () async {
          await refreshFinance(ref);
          await ref.read(periodProvider(p.id).future);
        },
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 96), children: [
          AppCard(
            gradient: heroGradient,
            padding: const EdgeInsets.all(20),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(rangeLabel(p.start, p.end), style: const TextStyle(color: Color(0xFFBFE5D1))),
              const SizedBox(height: 10),
              const Text('Disponible', style: TextStyle(color: Color(0xFFBFE5D1), fontSize: 13)),
              Text(fmt(p.balance), style: const TextStyle(color: Colors.white, fontSize: 36, fontWeight: FontWeight.w800)),
              const SizedBox(height: 14),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: p.progress.clamp(0.0, 1.0).toDouble(),
                  minHeight: 8,
                  backgroundColor: Colors.white24,
                  color: p.progress > 0.9 ? const Color(0xFFFFB4A8) : Colors.white,
                ),
              ),
              const SizedBox(height: 14),
              Row(children: [
                _Stat('Presupuesto', fmt(p.budget)),
                if (p.transfersIn > 0) _Stat('Desde Caja', fmt(p.transfersIn)),
                _Stat('Gastado', fmt(p.spent)),
              ]),
            ]),
          ),
          const SizedBox(height: 14),
          ..._buildActions(fmt),
          const SizedBox(height: 16),
          SegmentedButton<_PeriodView>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: _PeriodView.items, icon: Icon(Icons.pie_chart_outline_rounded), label: Text('Partidas')),
              ButtonSegment(value: _PeriodView.history, icon: Icon(Icons.history_rounded), label: Text('Historial')),
            ],
            selected: {_view},
            onSelectionChanged: (s) {
              HapticFeedback.selectionClick();
              setState(() => _view = s.first);
            },
          ),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            child: Column(
              key: ValueKey(_view),
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: _view == _PeriodView.items
                  ? _itemsView(
                      items: items,
                      cats: cats,
                      spentByItem: spentByItem,
                      looseTotal: looseTotal,
                      looseCount: looseCount,
                      plannedTotal: plannedTotal,
                    )
                  : _historyView(history: history, loading: expenses.isLoading, itemsById: itemsById, cats: cats),
            ),
          ),
        ]),
      ),
    );
  }
}

// ======================================================================== widgets

class _Stat extends StatelessWidget {
  const _Stat(this.label, this.value);
  final String label, value;
  @override
  Widget build(BuildContext context) => Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(color: Color(0xFFBFE5D1), fontSize: 12)),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
          ),
        ]),
      );
}

/// Partida planificada (con barra de límite).
class _ItemCard extends ConsumerWidget {
  const _ItemCard({required this.item, required this.spent, required this.editable, required this.onTap, this.category});
  final PeriodItem item;
  final double spent;
  final bool editable;
  final VoidCallback onTap;
  final Category? category;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fmt = ref.watch(moneyProvider);
    final over = item.planned > 0 && spent > item.planned;
    final color = category?.color ?? AppColors.primary;
    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.all(14),
      child: Column(children: [
        Row(children: [
          CircleAvatar(
            backgroundColor: color.withValues(alpha: 0.15),
            child: Icon(category?.icon ?? Icons.savings_rounded, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(item.name, style: const TextStyle(fontWeight: FontWeight.w700)),
              Text(
                item.planned > 0 ? 'de ${fmt(item.planned)} planificado' : 'Sin monto planificado',
                style: const TextStyle(color: AppColors.muted, fontSize: 12),
              ),
            ]),
          ),
          Text(fmt(spent), style: TextStyle(fontWeight: FontWeight.w800, color: over ? AppColors.danger : AppColors.forest)),
          Padding(
            padding: const EdgeInsets.only(left: 8),
            child: Icon(editable ? Icons.calculate_outlined : Icons.history_rounded, size: 20, color: AppColors.muted),
          ),
        ]),
        const SizedBox(height: 10),
        MoneyProgressBar(value: item.planned <= 0 ? (spent > 0 ? 1 : 0) : spent / item.planned, height: 6),
      ]),
    );
  }
}

/// "Otros gastos": gastos sueltos, sin barra de límite.
class _LooseCard extends ConsumerWidget {
  const _LooseCard({required this.total, required this.count, required this.editable, required this.onTap});
  final double total;
  final int count;
  final bool editable;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fmt = ref.watch(moneyProvider);
    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.all(14),
      child: Row(children: [
        const CircleAvatar(
          backgroundColor: AppColors.mint,
          child: Icon(Icons.receipt_long_rounded, color: AppColors.primary),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Otros gastos', style: TextStyle(fontWeight: FontWeight.w700)),
            Text(
              count == 0 ? 'Sin movimientos' : '$count movimiento${count == 1 ? '' : 's'}',
              style: const TextStyle(color: AppColors.muted, fontSize: 12),
            ),
          ]),
        ),
        Text(fmt(total), style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.forest)),
        Padding(
          padding: const EdgeInsets.only(left: 8),
          child: Icon(editable ? Icons.calculate_outlined : Icons.history_rounded, size: 20, color: AppColors.muted),
        ),
      ]),
    );
  }
}

/// Fila del historial cronológico. En períodos cerrados es de solo lectura.
class _HistoryTile extends ConsumerWidget {
  const _HistoryTile({
    required this.expense,
    required this.itemName,
    required this.category,
    required this.editable,
    required this.onEdit,
    required this.onDelete,
  });
  final Expense expense;
  final String? itemName;
  final Category? category;
  final bool editable;
  final VoidCallback onEdit;
  final Future<void> Function() onDelete;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fmt = ref.watch(moneyProvider);
    final color = category?.color ?? AppColors.muted;
    final title = expense.description.isNotEmpty ? expense.description : (itemName ?? category?.name ?? 'Gasto');
    final tile = AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      onTap: editable ? onEdit : null,
      child: Row(children: [
        CircleAvatar(
          backgroundColor: color.withValues(alpha: 0.15),
          child: Icon(category?.icon ?? Icons.receipt_long_rounded, color: color),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
            Text(itemName ?? 'Otros gastos', style: const TextStyle(color: AppColors.muted, fontSize: 12)),
          ]),
        ),
        Text('-${fmt(expense.amount)}', style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.forest)),
      ]),
    );
    if (!editable) return tile;
    return Dismissible(
      key: ValueKey(expense.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(color: AppColors.danger, borderRadius: BorderRadius.circular(22)),
        child: const Icon(Icons.delete_outline_rounded, color: Colors.white),
      ),
      // Se borra y se refresca la lista (evita el assert de "dismissed widget still in tree").
      confirmDismiss: (_) async {
        await onDelete();
        return false;
      },
      child: tile,
    );
  }
}

class _PlanSummary extends ConsumerWidget {
  const _PlanSummary({required this.planned, required this.available});
  final double planned, available;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fmt = ref.watch(moneyProvider);
    final diff = available - planned;
    final over = diff < 0;
    return AppCard(
      padding: const EdgeInsets.all(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Expanded(child: Text('Planificado en partidas', style: TextStyle(fontWeight: FontWeight.w700))),
          Text('${fmt(planned)} de ${fmt(available)}', style: const TextStyle(color: AppColors.muted, fontSize: 13)),
        ]),
        const SizedBox(height: 10),
        MoneyProgressBar(value: available <= 0 ? (planned > 0 ? 1 : 0) : planned / available, height: 6),
        const SizedBox(height: 8),
        Text(
          over ? 'Las partidas superan el presupuesto en ${fmt(-diff)}' : 'Sin asignar: ${fmt(diff)}',
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: over ? AppColors.danger : AppColors.muted),
        ),
      ]),
    );
  }
}