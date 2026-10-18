import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/common.dart';
import '../currency/currency.dart';
import '../home/settings_sheet.dart';
import 'stats_repository.dart';

class StatsPage extends ConsumerWidget {
  const StatsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final year = ref.watch(statsYearProvider);
    final data = ref.watch(annualProvider(year));
    return Scaffold(
      appBar: AppBar(
        title: const Text('Resumen anual'),
        actions: [IconButton(icon: const Icon(Icons.account_circle_outlined), onPressed: () => showSettingsSheet(context))],
      ),
      body: AsyncView<AnnualData>(
        value: data,
        onRetry: () => ref.invalidate(annualProvider),
        data: (d) => RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(annualProvider);
            await ref.read(annualProvider(year).future);
          },
          child: ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 32), children: [
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              IconButton(onPressed: () => ref.read(statsYearProvider.notifier).state = year - 1, icon: const Icon(Icons.chevron_left_rounded)),
              Text('$year', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.forest)),
              IconButton(onPressed: () => ref.read(statsYearProvider.notifier).state = year + 1, icon: const Icon(Icons.chevron_right_rounded)),
            ]),
            _Kpis(d),
            const SectionTitle('Gasto mensual'),
            const Padding(
              padding: EdgeInsets.only(left: 4, bottom: 8),
              child: Text('Cada barra suma los períodos que inician en ese mes.', style: TextStyle(color: AppColors.muted, fontSize: 12)),
            ),
            AppCard(child: SizedBox(height: 200, child: _MonthChart(d))),
            const SectionTitle('Por categoría'),
            if (d.categories.isEmpty)
              const Padding(padding: EdgeInsets.all(24), child: Text('Sin gastos registrados este año.', textAlign: TextAlign.center, style: TextStyle(color: AppColors.muted)))
            else
              AppCard(child: Column(children: [for (final c in d.categories) _CategoryRow(c, d.totalSpent)])),
          ]),
        ),
      ),
    );
  }
}

class _Kpis extends ConsumerWidget {
  const _Kpis(this.d);
  final AnnualData d;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fmt = ref.watch(moneyProvider);
    final peak = d.peakMonth;
    final tiles = [
      ('Total gastado', fmt(d.totalSpent), Icons.payments_rounded, AppColors.forest),
      ('Presupuestado', fmt(d.totalBudget), Icons.account_balance_wallet_rounded, AppColors.primary),
      (d.saved >= 0 ? 'Ahorro' : 'Déficit', fmt(d.saved.abs()), d.saved >= 0 ? Icons.trending_up_rounded : Icons.trending_down_rounded, d.saved >= 0 ? AppColors.emerald : AppColors.danger),
      ('Promedio mensual', fmt(d.monthlyAverage), Icons.calendar_month_rounded, AppColors.primary),
    ];
    return Column(children: [
      GridView.count(
        crossAxisCount: 2, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
        crossAxisSpacing: 12, mainAxisSpacing: 12, childAspectRatio: 1.55,
        children: [
          for (final t in tiles)
            AppCard(
              padding: const EdgeInsets.all(14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Icon(t.$3, color: t.$4),
                FittedBox(fit: BoxFit.scaleDown, child: Text(t.$2, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: t.$4))),
                Text(t.$1, style: const TextStyle(color: AppColors.muted, fontSize: 12)),
              ]),
            ),
        ],
      ),
      if (peak != null)
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: AppCard(
            child: Row(children: [
              const Icon(Icons.local_fire_department_rounded, color: AppColors.amber),
              const SizedBox(width: 10),
              Expanded(child: Text('Mes de mayor gasto: ${capitalize(DateFormat('MMMM', 'es').format(DateTime(2000, peak.month)))} (${fmt(peak.spent)})')),
            ]),
          ),
        ),
      if (d.fundSpent > 0)
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: AppCard(
            child: Row(children: [
              const Icon(Icons.savings_rounded, color: AppColors.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Text('Además, ${fmt(d.fundSpent)} en gastos directos de la Caja General (no incluidos arriba).'),
              ),
            ]),
          ),
        ),
    ]);
  }
}

class _MonthChart extends ConsumerWidget {
  const _MonthChart(this.d);
  final AnnualData d;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fmt = ref.watch(moneyProvider);
    final peak = d.months.fold<double>(0, (m, e) => e.spent > m ? e.spent : m);
    final current = DateTime.now().month;
    return BarChart(BarChartData(
      maxY: peak == 0 ? 1 : peak * 1.15,
      gridData: const FlGridData(show: false),
      borderData: FlBorderData(show: false),
      titlesData: FlTitlesData(
        leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 24,
            getTitlesWidget: (v, meta) => SideTitleWidget(
              axisSide: meta.axisSide,
              child: Text(DateFormat('MMM', 'es').format(DateTime(2000, v.toInt() + 1))[0].toUpperCase(),
                  style: const TextStyle(fontSize: 12, color: AppColors.muted, fontWeight: FontWeight.w600)),
            ),
          ),
        ),
      ),
      barTouchData: BarTouchData(
        touchTooltipData: BarTouchTooltipData(
          getTooltipItem: (group, _, rod, __) => BarTooltipItem(
            '${capitalize(DateFormat('MMM', 'es').format(DateTime(2000, group.x + 1)))}\n${fmt(rod.toY)}',
            const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12),
          ),
        ),
      ),
      barGroups: [
        for (final m in d.months)
          BarChartGroupData(x: m.month - 1, barRods: [
            BarChartRodData(
              toY: m.spent,
              width: 14,
              color: m.month == current ? AppColors.emerald : AppColors.primary.withValues(alpha: 0.55),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
            ),
          ]),
      ],
    ));
  }
}

class _CategoryRow extends ConsumerWidget {
  const _CategoryRow(this.c, this.total);
  final CategoryStat c;
  final double total;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fmt = ref.watch(moneyProvider);
    final pct = total == 0 ? 0.0 : c.total / total;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(children: [
        Row(children: [
          Container(width: 10, height: 10, decoration: BoxDecoration(color: c.color, shape: BoxShape.circle)),
          const SizedBox(width: 8),
          Expanded(child: Text(c.name, style: const TextStyle(fontWeight: FontWeight.w600))),
          Text('${(pct * 100).toStringAsFixed(0)}%  ·  ${fmt(c.total)}', style: const TextStyle(color: AppColors.muted, fontSize: 13)),
        ]),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: pct),
            duration: const Duration(milliseconds: 600),
            builder: (_, v, __) => LinearProgressIndicator(value: v, minHeight: 6, backgroundColor: AppColors.mint, color: c.color),
          ),
        ),
      ]),
    );
  }
}
