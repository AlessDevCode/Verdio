import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/refresh.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/errors.dart';
import '../../core/utils/formatters.dart';
import '../currency/currency.dart';
import '../periods/models.dart';
import 'expense_repository.dart';

/// - [period] != null: gasto dentro de ese período (fecha acotada a su rango).
/// - [fromFund]: gasto directo de la Caja General.
/// - [editing] != null: modo edición del gasto indicado.
Future<void> showAddExpenseSheet(
  BuildContext context, {
  Period? period,
  bool fromFund = false,
  Expense? editing,
}) =>
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => AddExpenseSheet(period: period, fromFund: fromFund, editing: editing),
    );

class AddExpenseSheet extends ConsumerStatefulWidget {
  const AddExpenseSheet({super.key, this.period, this.fromFund = false, this.editing});
  final Period? period;
  final bool fromFund;
  final Expense? editing;
  @override
  ConsumerState<AddExpenseSheet> createState() => _State();
}

class _State extends ConsumerState<AddExpenseSheet> {
  final _amount = TextEditingController();
  final _desc = TextEditingController();
  String? _categoryId;
  late DateTime _date;
  bool _busy = false;

  bool get _isEdit => widget.editing != null;

  @override
  void initState() {
    super.initState();
    final ex = widget.editing;
    if (ex != null) {
      _amount.text = ex.amount.toStringAsFixed(2);
      _desc.text = ex.description;
      _categoryId = ex.categoryId;
      _date = ex.date;
    } else {
      final t = today();
      final p = widget.period;
      _date = p == null ? t : (t.isBefore(p.start) ? p.start : (t.isAfter(p.end) ? p.end : t));
    }
  }

  @override
  void dispose() {
    _amount.dispose();
    _desc.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final p = widget.period;
    final d = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: p?.start ?? DateTime(2020),
      lastDate: p?.end ?? DateTime.now().add(const Duration(days: 365)),
      locale: const Locale('es'),
    );
    if (!mounted) return;
    if (d != null) setState(() => _date = d);
  }

  Future<void> _save() async {
    final amount = parseAmount(_amount.text);
    if (amount == null || amount <= 0) {
      HapticFeedback.heavyImpact();
      return showSnack(context, 'Ingresa un monto mayor a 0', error: true);
    }
    setState(() => _busy = true);
    try {
      final repo = ref.read(expenseRepositoryProvider);
      if (_isEdit) {
        await repo.update(
          widget.editing!.id,
          amount: amount,
          description: _desc.text.trim(),
          date: _date,
          categoryId: _categoryId,
        );
      } else {
        await repo.add(
          amount: amount,
          description: _desc.text.trim(),
          date: _date,
          categoryId: _categoryId,
          periodId: widget.period?.id,
          fromFund: widget.fromFund,
        );
      }
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
    final cats = ref.watch(categoriesProvider).valueOrNull ?? const <Category>[];
    final symbol = ref.watch(currentCurrencyProvider).symbol;
    final title = _isEdit
        ? 'Editar gasto'
        : widget.fromFund
            ? 'Gasto desde la Caja General'
            : (widget.period != null ? 'Nuevo gasto · ${widget.period!.name}' : 'Nuevo gasto');

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800, color: AppColors.forest)),
          const SizedBox(height: 8),
          TextField(
            controller: _amount,
            autofocus: !_isEdit,
            textAlign: TextAlign.center,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
            style: const TextStyle(fontSize: 40, fontWeight: FontWeight.w800, color: AppColors.forest),
            decoration: InputDecoration(
              hintText: '0.00',
              prefixText: '$symbol ',
              prefixStyle: const TextStyle(fontSize: 28, color: AppColors.muted),
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              filled: false,
            ),
          ),
          TextField(
            controller: _desc,
            maxLength: 140,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Descripción (opcional)', counterText: ''),
          ),
          const SizedBox(height: 14),
          Wrap(spacing: 8, runSpacing: 4, children: [
            for (final c in cats)
              ChoiceChip(
                avatar: Icon(c.icon, size: 18, color: _categoryId == c.id ? Colors.white : c.color),
                label: Text(c.name),
                selected: _categoryId == c.id,
                selectedColor: c.color,
                labelStyle: TextStyle(color: _categoryId == c.id ? Colors.white : null, fontWeight: FontWeight.w600),
                showCheckmark: false,
                onSelected: (s) {
                  HapticFeedback.selectionClick();
                  setState(() => _categoryId = s ? c.id : null);
                },
              ),
          ]),
          const SizedBox(height: 12),
          InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: _pickDate,
            child: InputDecorator(
              decoration: const InputDecoration(labelText: 'Fecha real del gasto', suffixIcon: Icon(Icons.calendar_today_rounded)),
              child: Text(longDate(_date)),
            ),
          ),
          if (!_isEdit && widget.period == null && !widget.fromFund)
            const Padding(
              padding: EdgeInsets.only(top: 6, left: 4),
              child: Text('Se asignará al período que contenga esta fecha.', style: TextStyle(fontSize: 12, color: AppColors.muted)),
            ),
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: _busy ? null : _save,
            icon: _busy
                ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                : const Icon(Icons.check_rounded),
            label: Text(_isEdit ? 'Guardar cambios' : 'Guardar gasto'),
          ),
        ]),
      ),
    );
  }
}