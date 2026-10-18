import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/common.dart';
import '../currency/currency.dart';
import '../home/settings_sheet.dart';
import 'create_period_sheet.dart';
import 'models.dart';
import 'period_detail_page.dart';
import 'period_repository.dart';

class PeriodsPage extends ConsumerWidget {
  const PeriodsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final periods = ref.watch(periodsProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mis períodos'),
        actions: [
          IconButton(tooltip: 'Nuevo período', icon: const Icon(Icons.add_circle_outline_rounded), onPressed: () => showCreatePeriodSheet(context)),
          IconButton(tooltip: 'Ajustes', icon: const Icon(Icons.account_circle_outlined), onPressed: () => showSettingsSheet(context)),
        ],
      ),

      body: AsyncView<List<Period>>(
        value: periods,
        onRetry: () => ref.invalidate(periodsProvider),
        data: (list) {
          if (list.isEmpty) {
            return EmptyState(
              icon: Icons.event_available_rounded,
              title: 'Crea tu primer período',
              message: 'Mensual, quincenal o con las fechas que prefieras.',
              actionLabel: 'Nuevo período',
              onAction: () => showCreatePeriodSheet(context),
            );
          }
          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(periodsProvider);
              await ref.read(periodsProvider.future);
            },
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
              itemCount: list.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (_, i) => _PeriodCard(list[i]),
            ),
          );
        },
      ),
    );
  }
}

class _PeriodCard extends ConsumerWidget {
  const _PeriodCard(this.p);
  final Period p;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fmt = ref.watch(moneyProvider);
    final over = p.balance < 0;
    return AppCard(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => PeriodDetailPage(periodId: p.id))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(p.name, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800))),
          _status(),
        ]),
        const SizedBox(height: 2),
        Text(rangeLabel(p.start, p.end), style: const TextStyle(color: AppColors.muted)),
        const SizedBox(height: 16),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, crossAxisAlignment: CrossAxisAlignment.end, children: [
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Disponible', style: TextStyle(color: AppColors.muted, fontSize: 12)),
            Text(fmt(p.balance), style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: over ? AppColors.danger : AppColors.forest)),
          ]),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            const Text('Gastado', style: TextStyle(color: AppColors.muted, fontSize: 12)),
            Text(fmt(p.spent), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          ]),
        ]),
        const SizedBox(height: 12),
        MoneyProgressBar(value: p.progress),
      ]),
    );
  }

  Widget _status() {
    if (p.canSendRemainder) return const Pill('Remanente pendiente', color: AppColors.amber);
    if (p.isClosed && p.balance < 0) return const Pill('Cerrado · déficit', color: AppColors.danger);
    if (p.isClosed) return const Pill('Cerrado', color: AppColors.muted);
    if (p.isCurrent) return const Pill('En curso', color: AppColors.emerald, filled: true);
    return const Pill('Abierto');
  }
}
