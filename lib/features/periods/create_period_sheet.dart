import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/refresh.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/errors.dart';
import '../../core/utils/formatters.dart';
import '../currency/currency.dart';
import '../templates/template_repository.dart';
import 'models.dart';
import 'period_repository.dart';

Future<void> showCreatePeriodSheet(BuildContext context) => showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => const _CreatePeriodSheet(),
    );

class _CreatePeriodSheet extends ConsumerStatefulWidget {
  const _CreatePeriodSheet();
  @override
  ConsumerState<_CreatePeriodSheet> createState() => _State();
}

class _State extends ConsumerState<_CreatePeriodSheet> {
  final _name = TextEditingController();
  final _budget = TextEditingController();
  PeriodKind _kind = PeriodKind.monthly;
  late DateTimeRange _range;
  String? _templateId;
  bool _busy = false, _nameTouched = false;

  @override
  void initState() {
    super.initState();
    _applyKind(PeriodKind.monthly);
  }

  @override
  void dispose() {
    _name.dispose();
    _budget.dispose();
    super.dispose();
  }

  void _applyKind(PeriodKind k) {
    final n = DateTime.now();
    final lastDay = DateTime(n.year, n.month + 1, 0).day;
    final month = capitalize(DateFormat('MMMM y', 'es').format(n));
    switch (k) {
      case PeriodKind.monthly:
        _range = DateTimeRange(start: DateTime(n.year, n.month, 1), end: DateTime(n.year, n.month, lastDay));
        _setName(month);
      case PeriodKind.biweekly:
        final first = n.day <= 15;
        _range = DateTimeRange(
          start: DateTime(n.year, n.month, first ? 1 : 16),
          end: DateTime(n.year, n.month, first ? 15 : lastDay),
        );
        _setName('${first ? '1ª' : '2ª'} quincena · ${capitalize(DateFormat('MMMM', 'es').format(n))}');
      case PeriodKind.custom:
        _range = DateTimeRange(start: today(), end: today().add(const Duration(days: 6)));
        _setName('Período personalizado');
    }
    _kind = k;
  }

  void _setName(String v) {
    if (!_nameTouched) _name.text = v;
  }

  Future<void> _pickRange() async {
    final r = await showDateRangePicker(
      context: context,
      initialDateRange: _range,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      helpText: 'Fechas del período',
      saveText: 'Aplicar',
    );
    if (!mounted) return;
    if (r != null) setState(() => _range = r);
  }

  Future<void> _save() async {
    final budget = _budget.text.trim().isEmpty ? 0.0 : parseAmount(_budget.text);
    if (_name.text.trim().isEmpty) return showSnack(context, 'Ponle un nombre al período', error: true);
    if (budget == null || budget < 0) return showSnack(context, 'Presupuesto no válido', error: true);
    setState(() => _busy = true);
    try {
      await ref.read(periodRepositoryProvider).create(
            name: _name.text.trim(),
            kind: _kind,
            start: _range.start,
            end: _range.end,
            budget: budget,
            templateId: _templateId,
          );
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      invalidateFinance(ref);
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      showSnack(context, friendlyError(e), error: true);
      setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final templates = ref.watch(templatesProvider).valueOrNull ?? const <ExpenseTemplate>[];
    final symbol = ref.watch(currentCurrencyProvider).symbol;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          Text('Nuevo período', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800, color: AppColors.forest)),
          const SizedBox(height: 16),
          SegmentedButton<PeriodKind>(
            showSelectedIcon: false,
            segments: [for (final k in PeriodKind.values) ButtonSegment(value: k, label: Text(k.label))],
            selected: {_kind},
            onSelectionChanged: (s) {
              HapticFeedback.selectionClick();
              setState(() => _applyKind(s.first));
              if (s.first == PeriodKind.custom) _pickRange();
            },
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _name,
            onChanged: (_) => _nameTouched = true,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Nombre'),
          ),
          const SizedBox(height: 12),
          InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: _pickRange,
            child: InputDecorator(
              decoration: const InputDecoration(labelText: 'Fechas', suffixIcon: Icon(Icons.date_range_rounded)),
              child: Text(rangeLabel(_range.start, _range.end)),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _budget,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
            decoration: InputDecoration(labelText: 'Presupuesto / ingreso del período', prefixText: '$symbol '),
          ),
          if (templates.isNotEmpty) ...[
            const SizedBox(height: 12),
            DropdownButtonFormField<String?>(
              key: ValueKey('tpl-${templates.length}'),
              initialValue: _templateId,
              decoration: const InputDecoration(labelText: 'Plantilla de gastos (opcional)'),
              items: [
                const DropdownMenuItem(value: null, child: Text('Sin plantilla')),
                for (final t in templates) DropdownMenuItem(value: t.id, child: Text(t.name)),
              ],
              onChanged: (v) => setState(() => _templateId = v),
            ),
          ],
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _busy ? null : _save,
            child: _busy
                ? const SizedBox(height: 22, width: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                : const Text('Crear período'),
          ),
        ]),
      ),
    );
  }
}