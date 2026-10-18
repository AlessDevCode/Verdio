import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/utils/formatters.dart';
import '../periods/models.dart';
import '../periods/period_repository.dart';
import 'fund_repository.dart';

/// Cómo se agrupan los movimientos de la Caja.
enum FundGrouping { months, fortnights, periods }

extension FundGroupingX on FundGrouping {
  String get label => switch (this) {
        FundGrouping.months => 'Meses',
        FundGrouping.fortnights => 'Quincenas',
        FundGrouping.periods => 'Períodos',
      };
}

DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);
DateTime _nextDay(DateTime d) => DateTime(d.year, d.month, d.day + 1);
DateTime _prevDay(DateTime d) => DateTime(d.year, d.month, d.day - 1);

/// dd/MM/yyyy
String dmy(DateTime d) => DateFormat('dd/MM/yyyy').format(d);

const transitionTitle = 'Gastos de transición / Fuera de período';

class FundGroup {
  const FundGroup({
    required this.key,
    required this.title,
    required this.start,
    required this.end,
    required this.entries,
    this.isTransition = false,
  });

  final String key;
  final String title;
  final DateTime start, end;
  final List<FundEntry> entries;
  final bool isTransition;

  double get income => entries.where((e) => e.isIncome).fold<double>(0, (s, e) => s + e.amount);
  double get outflow => entries.where((e) => !e.isIncome).fold<double>(0, (s, e) => s + e.amount);
  double get net => income - outflow;
}

/// Parte TODOS los movimientos en grupos disjuntos: la suma de los netos de los grupos
/// es exactamente el saldo de la Caja, sea cual sea el filtro.
List<FundGroup> buildFundGroups(FundGrouping mode, List<FundEntry> entries, List<Period> periods) =>
    switch (mode) {
      FundGrouping.months => _byCalendar(entries, fortnights: false),
      FundGrouping.fortnights => _byCalendar(entries, fortnights: true),
      FundGrouping.periods => _byPeriods(entries, periods),
    };

List<FundGroup> _byCalendar(List<FundEntry> entries, {required bool fortnights}) {
  final buckets = <DateTime, List<FundEntry>>{};
  for (final e in entries) {
    final d = _day(e.date);
    final start = DateTime(d.year, d.month, fortnights && d.day > 15 ? 16 : 1);
    (buckets[start] ??= []).add(e);
  }
  final starts = buckets.keys.toList()..sort((a, b) => b.compareTo(a));
  final monthLabel = (DateTime s) => capitalize(DateFormat('MMMM y', 'es').format(s));
  return [
    for (final s in starts)
      FundGroup(
        key: '${fortnights ? 'q' : 'm'}-${dbDate(s)}',
        title: fortnights ? '${s.day == 1 ? '1ª' : '2ª'} quincena · ${monthLabel(s)}' : monthLabel(s),
        start: s,
        end: fortnights && s.day == 1 ? DateTime(s.year, s.month, 15) : DateTime(s.year, s.month + 1, 0),
        entries: buckets[s]!,
      ),
  ];
}

List<FundGroup> _byPeriods(List<FundEntry> entries, List<Period> periods) {
  // Los períodos no se solapan (restricción en BD): ordenados por inicio, también quedan ordenados por fin.
  final sorted = [...periods]..sort((a, b) => a.start.compareTo(b.start));
  final byId = {for (final p in sorted) p.id: p};
  final inPeriod = <String, List<FundEntry>>{};
  final gaps = <int, List<FundEntry>>{}; // índice del hueco -> movimientos

  for (final e in entries) {
    final d = _day(e.date);
    // Remanentes y reposiciones pertenecen a "su" período; el resto se ubica por fecha.
    Period? target = e.periodId == null ? null : byId[e.periodId];
    if (target == null) {
      for (final p in sorted) {
        if (!d.isBefore(p.start) && !d.isAfter(p.end)) {
          target = p;
          break;
        }
      }
    }
    if (target != null) {
      (inPeriod[target.id] ??= []).add(e);
    } else {
      // Hueco i = entre sorted[i-1] y sorted[i] (0 = antes del primero, n = después del último).
      final idx = sorted.where((p) => p.end.isBefore(d)).length;
      (gaps[idx] ??= []).add(e);
    }
  }

  final groups = <FundGroup>[
    for (final p in sorted)
      if (inPeriod[p.id] != null)
        FundGroup(key: 'p-${p.id}', title: p.name, start: p.start, end: p.end, entries: inPeriod[p.id]!),
  ];

  for (final gap in gaps.entries) {
    final idx = gap.key;
    final dates = gap.value.map((e) => _day(e.date)).toList()..sort();
    // Rango exacto del hueco; en los extremos abiertos se usa el primer/último movimiento.
    final start = idx == 0 ? dates.first : _nextDay(sorted[idx - 1].end);
    final end = idx == sorted.length ? dates.last : _prevDay(sorted[idx].start);
    groups.add(FundGroup(
      key: 'gap-$idx',
      title: transitionTitle,
      start: start,
      end: end,
      entries: gap.value,
      isTransition: true,
    ));
  }

  groups.sort((a, b) => b.start.compareTo(a.start));
  return groups;
}

final fundGroupingProvider = StateProvider<FundGrouping>((_) => FundGrouping.months);

/// Historial agrupado según el filtro elegido. Se recalcula solo cuando cambia
/// el historial, los períodos o el filtro.
final fundGroupsProvider = Provider<AsyncValue<List<FundGroup>>>((ref) {
  final mode = ref.watch(fundGroupingProvider);
  final feed = ref.watch(fundFeedProvider);
  final periods = ref.watch(periodsProvider);
  final needPeriods = mode == FundGrouping.periods;

  if (feed.hasError) return AsyncError(feed.error!, feed.stackTrace ?? StackTrace.current);
  if (needPeriods && periods.hasError) return AsyncError(periods.error!, periods.stackTrace ?? StackTrace.current);
  if (!feed.hasValue || (needPeriods && !periods.hasValue)) return const AsyncLoading();

  return AsyncData(buildFundGroups(mode, feed.requireValue, periods.valueOrNull ?? const <Period>[]));
});