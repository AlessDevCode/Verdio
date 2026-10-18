import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/refresh.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/errors.dart';
import '../../core/widgets/common.dart';
import '../currency/currency.dart';
import '../expenses/expense_repository.dart';
import 'models.dart';
import 'period_repository.dart';
import '../../core/utils/formatters.dart';

/// Edita los metadatos de una partida: nombre, categoría y monto planificado.
Future<void> showEditItemSheet(BuildContext context, {required Period period, required PeriodItem item}) =>
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => EditItemSheet(period: period, item: item),
    );

int _cents(double v) => (v * 100).round();

class EditItemSheet extends ConsumerStatefulWidget {
  const EditItemSheet({super.key, required this.period, required this.item});
  final Period period;
  final PeriodItem item;
  @override
  ConsumerState<EditItemSheet> createState() => _State();
}

class _State extends ConsumerState<EditItemSheet> {
  late final _name = TextEditingController(text: widget.item.name);
  late final _planned = TextEditingController(
    text: widget.item.planned > 0 ? widget.item.planned.toStringAsFixed(2) : '',
  );
  late String? _categoryId = widget.item.categoryId;
  bool _adjustBudget = false, _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _planned.dispose();
    super.dispose();
  }

  Future<void> _submit({required String name, required double planned, required bool adjust}) async {
    // El container se captura antes del await: los datos se refrescan aunque la pantalla ya no esté montada.
    final container = ProviderScope.containerOf(context);
    setState(() => _busy = true);
    try {
      await ref.read(periodRepositoryProvider).updateItem(
            widget.item.id,
            name: name,
            categoryId: _categoryId,
            planned: planned,
            adjustBudget: adjust,
          );
      invalidateFinanceIn(container); // partidas, historial, presupuesto, Períodos, Caja y Resumen anual
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      showSnack(context, 'Partida actualizada');
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ref.invalidate(periodProvider(widget.period.id)); // el estado pudo cambiar (p. ej. se cerró el período)
      ref.invalidate(periodItemsProvider(widget.period.id));
      showSnack(context, friendlyError(e), error: true);
      setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final fmt = ref.watch(moneyProvider);
    final symbol = ref.watch(currentCurrencyProvider).symbol;
    // Estado fresco: si el período se cerró o la partida cambió mientras el panel estaba abierto.
    final period = ref.watch(periodProvider(widget.period.id)).valueOrNull ?? widget.period;
    final items = ref.watch(periodItemsProvider(period.id)).valueOrNull ?? [widget.item];
    final current = items.where((i) => i.id == widget.item.id).firstOrNull ?? widget.item;
    final others = items.where((i) => i.id != current.id);
    final cats = ref.watch(categoriesProvider).valueOrNull ?? const <Category>[];
    final expenses = ref.watch(periodExpensesProvider(period.id)).valueOrNull ?? const <Expense>[];
    final spent = expenses.where((e) => e.plannedItemId == current.id).fold<double>(0, (s, e) => s + e.amount);

    if (period.isClosed) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Icon(Icons.lock_outline_rounded, size: 44, color: AppColors.primary),
          const SizedBox(height: 10),
          Text('Período cerrado',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800, color: AppColors.forest)),
          const SizedBox(height: 6),
          const Text('Reabre el período para editar sus partidas.', textAlign: TextAlign.center, style: TextStyle(color: AppColors.muted)),
          const SizedBox(height: 18),
          FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Entendido')),
        ]),
      );
    }

    // ---- Validación en vivo ----
    final name = _name.text.trim();
    final amountText = _planned.text.trim();
    final planned = amountText.isEmpty ? 0.0 : parseAmount(amountText); // vacío = sin monto planificado
    final duplicate = name.isNotEmpty && others.any((i) => i.name.trim().toLowerCase() == name.toLowerCase());
    final value = planned ?? 0.0;

    // ---- Efecto sobre los totales del período (en céntimos para evitar errores de coma flotante) ----
    final deltaC = _cents(value) - _cents(current.planned);
    final delta = deltaC / 100;
    final adjust = _adjustBudget && deltaC != 0;
    final budgetAfterC = _cents(period.budget) + (adjust ? deltaC : 0);
    final budgetError = adjust && budgetAfterC < 0;

    final valid = name.isNotEmpty && !duplicate && planned != null && planned >= 0 && !budgetError;
    final dirty = name != current.name || _categoryId != current.categoryId || _cents(value) != _cents(current.planned);

    final plannedNow = items.fold<double>(0, (s, i) => s + i.planned);
    final plannedAfter = plannedNow - current.planned + value;
    final availableAfter = period.available + (adjust ? delta : 0);
    final unassigned = availableAfter - plannedAfter;

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          Text('Editar partida',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800, color: AppColors.forest)),
          Text('en ${period.name}', style: const TextStyle(color: AppColors.muted)),
          const SizedBox(height: 14),
          TextField(
            controller: _name,
            maxLength: 60,
            textCapitalization: TextCapitalization.sentences,
            textInputAction: TextInputAction.next,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: 'Nombre de la partida',
              counterText: '',
              errorText: duplicate ? 'Ya existe una partida con ese nombre' : null,
            ),
          ),
          if (cats.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Text('Categoría', style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.forest)),
            const SizedBox(height: 6),
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
                    setState(() => _categoryId = s ? c.id : null); // tocar la elegida la quita
                  },
                ),
            ]),
            if (_categoryId != current.categoryId && spent > 0)
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: Text(
                  'Los movimientos ya registrados en esta partida pasarán a la nueva categoría.',
                  style: TextStyle(color: AppColors.muted, fontSize: 12),
                ),
              ),
          ],
          const SizedBox(height: 14),
          TextField(
            controller: _planned,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*[.,]?\d{0,2}'))],
            textInputAction: TextInputAction.done,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: 'Monto planificado',
              hintText: 'Sin monto planificado',
              prefixText: '$symbol ',
              errorText: planned == null ? 'Monto no válido' : null,
            ),
          ),
          if (planned != null && value > 0 && spent > value)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'Ya gastaste ${fmt(spent)} en esta partida: supera el nuevo monto planificado.',
                style: const TextStyle(color: AppColors.amber, fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: adjust,
            onChanged: deltaC != 0
                ? (v) {
                    HapticFeedback.selectionClick();
                    setState(() => _adjustBudget = v);
                  }
                : null,
            title: Text(
              deltaC > 0
                  ? 'Sumar ${fmt(delta)} al presupuesto del período'
                  : deltaC < 0
                      ? 'Restar ${fmt(-delta)} del presupuesto del período'
                      : 'Ajustar el presupuesto del período',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            subtitle: Text(
              budgetError
                  ? 'El presupuesto del período no puede quedar negativo.'
                  : 'Actívalo si cambió el dinero disponible, no solo cómo lo repartes.',
              style: TextStyle(fontSize: 12, color: budgetError ? AppColors.danger : null),
            ),
          ),
          AppCard(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Column(children: [
              _Row('Planificado en partidas', '${fmt(plannedNow)}  →  ${fmt(plannedAfter)}'),
              _Row('Presupuesto del período',
                  adjust ? '${fmt(period.available)}  →  ${fmt(availableAfter)}' : fmt(period.available)),
              _Row(
                unassigned >= 0 ? 'Sin asignar' : 'Excedido',
                fmt(unassigned.abs()),
                color: unassigned >= 0 ? AppColors.emerald : AppColors.danger,
                bold: true,
              ),
            ]),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: valid && dirty && !_busy ? () => _submit(name: name, planned: value, adjust: adjust) : null,
            icon: _busy
                ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                : const Icon(Icons.check_rounded),
            label: const Text('Guardar cambios'),
          ),
        ]),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row(this.label, this.value, {this.color, this.bold = false});
  final String label, value;
  final Color? color;
  final bool bold;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(children: [
          Expanded(child: Text(label, style: const TextStyle(color: AppColors.muted))),
          Text(value, style: TextStyle(fontWeight: bold ? FontWeight.w800 : FontWeight.w600, color: color ?? AppColors.forest)),
        ]),
      );
}