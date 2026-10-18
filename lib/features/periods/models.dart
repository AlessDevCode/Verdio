enum PeriodKind { monthly, biweekly, custom }

extension PeriodKindX on PeriodKind {
  String get label => switch (this) {
        PeriodKind.monthly => 'Mensual',
        PeriodKind.biweekly => 'Quincenal',
        PeriodKind.custom => 'Personalizado',
      };
}

double num0(dynamic v) => (v as num?)?.toDouble() ?? 0;

class Period {
  const Period({
    required this.id, required this.name, required this.kind, required this.start, required this.end,
    required this.budget, required this.spent, required this.transfersIn, required this.isClosed,
    this.remainderAmount, this.remainderSentAt,
  });

  final String id, name;
  final PeriodKind kind;
  final DateTime start, end;
  final double budget, spent, transfersIn;
  final bool isClosed;
  final double? remainderAmount;
  final DateTime? remainderSentAt;

  /// Presupuesto + reposiciones recibidas de la Caja (transferencias NO son ingreso ni gasto).
  double get available => budget + transfersIn;
  double get balance => available - spent;
  double get progress => available <= 0 ? (spent > 0 ? 1 : 0) : spent / available;
  bool get remainderSent => remainderSentAt != null;
  bool get canSendRemainder => isClosed && !remainderSent && balance > 0;
  bool get isCurrent {
    final n = DateTime.now();
    final d = DateTime(n.year, n.month, n.day);
    return !isClosed && !d.isBefore(start) && !d.isAfter(end);
  }

  factory Period.fromMap(Map<String, dynamic> m) => Period(
        id: m['id'] as String,
        name: m['name'] as String,
        kind: PeriodKind.values.byName(m['kind'] as String),
        start: DateTime.parse(m['start_date'] as String),
        end: DateTime.parse(m['end_date'] as String),
        budget: num0(m['budget']),
        spent: num0(m['spent']),
        transfersIn: num0(m['transfers_in']),
        isClosed: m['status'] == 'closed',
        remainderAmount: m['remainder_amount'] == null ? null : num0(m['remainder_amount']),
        remainderSentAt: m['remainder_sent_at'] == null ? null : DateTime.parse(m['remainder_sent_at'] as String),
      );
}

class PeriodItem {
  const PeriodItem({required this.id, required this.name, required this.planned, this.categoryId});
  final String id, name;
  final String? categoryId;
  final double planned;

  factory PeriodItem.fromMap(Map<String, dynamic> m) => PeriodItem(
        id: m['id'] as String,
        name: m['name'] as String,
        categoryId: m['category_id'] as String?,
        planned: num0(m['planned_amount']),
      );
}
