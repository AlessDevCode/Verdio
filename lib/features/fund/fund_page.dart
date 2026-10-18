import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/refresh.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/common.dart';
import '../currency/currency.dart';
import '../expenses/add_expense_sheet.dart';
import '../home/settings_sheet.dart';
import 'fund_deposit_sheet.dart';
import 'fund_entry_sheet.dart';
import 'fund_grouping.dart';
import 'fund_repository.dart';

class FundPage extends ConsumerWidget {
  const FundPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fmt = ref.watch(moneyProvider);
    final balance = ref.watch(fundBalanceProvider);
    final groups = ref.watch(fundGroupsProvider);
    final mode = ref.watch(fundGroupingProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Caja General'),
        actions: [IconButton(icon: const Icon(Icons.account_circle_outlined), onPressed: () => showSettingsSheet(context))],
      ),
      body: RefreshIndicator(
        onRefresh: () => refreshFinance(ref),
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 32), children: [
          AppCard(
            gradient: heroGradient,
            padding: const EdgeInsets.all(22),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Fondo común disponible', style: TextStyle(color: Color(0xFFBFE5D1))),
              const SizedBox(height: 4),
              Text(balance.valueOrNull == null ? '···' : fmt(balance.value!),
                  style: const TextStyle(color: Colors.white, fontSize: 38, fontWeight: FontWeight.w800)),
              const SizedBox(height: 16),
              Row(children: [
                Expanded(
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: AppColors.forest),
                    onPressed: () => showFundDepositSheet(context),
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('Ingresar'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(foregroundColor: Colors.white, side: const BorderSide(color: Colors.white70)),
                    onPressed: () => showAddExpenseSheet(context, fromFund: true),
                    icon: const Icon(Icons.shopping_cart_checkout_rounded),
                    label: const Text('Gasto'),
                  ),
                ),
              ]),
              const SizedBox(height: 8),
              const Text('Para reponer un período, ábrelo y toca "Reponer".', style: TextStyle(color: Color(0xFFBFE5D1), fontSize: 12)),
            ]),
          ),
          const SectionTitle('Movimientos'),
          SegmentedButton<FundGrouping>(
            showSelectedIcon: false,
            segments: [for (final g in FundGrouping.values) ButtonSegment(value: g, label: Text(g.label))],
            selected: {mode},
            onSelectionChanged: (s) => ref.read(fundGroupingProvider.notifier).state = s.first,
          ),
          const SizedBox(height: 12),
          AsyncView<List<FundGroup>>(
            value: groups,
            onRetry: () => ref.invalidate(fundFeedProvider),
            data: (list) => list.isEmpty
                ? const Padding(
                    padding: EdgeInsets.all(32),
                    child: Text(
                      'Tu Caja está vacía. Registra tu fondo inicial con "Ingresar" o envía aquí el remanente de un período cerrado.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.muted),
                    ),
                  )
                : Column(children: [
                    _Reconciliation(groups: list, balance: balance.valueOrNull),
                    for (var i = 0; i < list.length; i++)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _GroupCard(group: list[i], initiallyExpanded: i == 0),
                      ),
                  ]),
          ),
        ]),
      ),
    );
  }
}

/// Comprueba que la suma de los grupos coincide con el saldo real de la Caja.
class _Reconciliation extends ConsumerWidget {
  const _Reconciliation({required this.groups, required this.balance});
  final List<FundGroup> groups;
  final double? balance;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (balance == null) return const SizedBox.shrink();
    final fmt = ref.watch(moneyProvider);
    final sum = groups.fold<double>(0, (s, g) => s + g.net);
    final ok = (sum * 100).round() == (balance! * 100).round();
    final color = ok ? AppColors.emerald : AppColors.danger;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(children: [
        Icon(ok ? Icons.verified_rounded : Icons.error_outline_rounded, size: 18, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            ok
                ? 'Cuadre correcto: la suma de los grupos (${fmt(sum)}) coincide con el saldo de la Caja.'
                : 'Diferencia detectada: grupos ${fmt(sum)} vs. saldo ${fmt(balance!)}. Desliza para actualizar.',
            style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ),
      ]),
    );
  }
}

class _GroupCard extends ConsumerWidget {
  const _GroupCard({required this.group, required this.initiallyExpanded});
  final FundGroup group;
  final bool initiallyExpanded;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fmt = ref.watch(moneyProvider);
    final g = group;
    final net = g.net;
    final radius = BorderRadius.circular(22);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: radius,
        border: Border.all(color: g.isTransition ? AppColors.amber.withValues(alpha: 0.6) : AppColors.border),
        boxShadow: const [BoxShadow(color: Color(0x120B3D2E), blurRadius: 14, offset: Offset(0, 5))],
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            key: PageStorageKey<String>('fund-${g.key}'),
            initiallyExpanded: initiallyExpanded,
            tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            shape: const Border(),
            collapsedShape: const Border(),
            title: Text(g.title, style: const TextStyle(fontWeight: FontWeight.w800)),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                Text('${dmy(g.start)} – ${dmy(g.end)}', style: const TextStyle(color: AppColors.muted, fontSize: 12)),
                if (g.isTransition) const Pill('Fuera de período', color: AppColors.amber),
              ]),
            ),
            trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(
                '${net >= 0 ? '+' : '-'}${fmt(net.abs())}',
                style: TextStyle(fontWeight: FontWeight.w800, color: net >= 0 ? AppColors.emerald : AppColors.forest),
              ),
              Text('${g.entries.length} mov.', style: const TextStyle(color: AppColors.muted, fontSize: 12)),
            ]),
            children: [
              if (g.isTransition)
                const Padding(
                  padding: EdgeInsets.only(bottom: 10),
                  child: Text(
                    'Dinero que se movió entre tus períodos, sin un ciclo activo en esas fechas. Se incluye para que la Caja cuadre al 100 %.',
                    style: TextStyle(color: AppColors.muted, fontSize: 12),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(children: [
                  Expanded(child: _Total(label: 'Ingresos', value: '+${fmt(g.income)}', color: AppColors.emerald)),
                  Expanded(child: _Total(label: 'Egresos', value: '-${fmt(g.outflow)}', color: AppColors.forest)),
                ]),
              ),
              for (final e in g.entries) _EntryTile(e),
            ],
          ),
        ),
      ),
    );
  }
}

class _Total extends StatelessWidget {
  const _Total({required this.label, required this.value, required this.color});
  final String label, value;
  final Color color;
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: const TextStyle(color: AppColors.muted, fontSize: 12)),
        Text(value, style: TextStyle(fontWeight: FontWeight.w800, color: color)),
      ]);
}

class _EntryTile extends ConsumerWidget {
  const _EntryTile(this.e);
  final FundEntry e;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fmt = ref.watch(moneyProvider);
    final (icon, color) = switch (e.kind) {
      FundEntryKind.remainderIn => (Icons.south_west_rounded, AppColors.emerald),
      FundEntryKind.deposit => (Icons.add_circle_outline_rounded, AppColors.emerald),
      FundEntryKind.replenishment => (Icons.north_east_rounded, AppColors.amber),
      FundEntryKind.expense => (Icons.shopping_bag_rounded, AppColors.danger),
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: AppCard(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        onTap: () => showFundEntrySheet(context, e),
        child: Row(children: [
          CircleAvatar(backgroundColor: color.withValues(alpha: 0.14), child: Icon(icon, color: color)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(e.title, style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                Text(longDate(e.date), style: const TextStyle(color: AppColors.muted, fontSize: 12)),
                if (e.isInternalTransfer) const Pill('Transferencia interna', color: AppColors.muted),
                if (e.depositKind != null) Pill(e.depositKind!.label, color: AppColors.emerald),
              ]),
            ]),
          ),
          Text(
            '${e.isIncome ? '+' : '-'}${fmt(e.amount)}',
            style: TextStyle(fontWeight: FontWeight.w800, color: e.isIncome ? AppColors.emerald : AppColors.forest),
          ),
        ]),
      ),
    );
  }
}