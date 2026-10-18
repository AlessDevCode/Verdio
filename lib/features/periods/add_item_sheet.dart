import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/refresh.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/errors.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/common.dart';
import '../currency/currency.dart';
import '../expenses/expense_repository.dart';
import 'models.dart';
import 'period_repository.dart';

/// Agrega una partida nueva a un período abierto (p. ej. un gasto imprevisto a mitad de mes).
Future<void> showAddItemSheet(BuildContext context, {required Period period}) => showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => AddItemSheet(period: period),
    );

class AddItemSheet extends ConsumerStatefulWidget {
  const AddItemSheet({super.key, required this.period});
  final Period period;
  @override
  ConsumerState<AddItemSheet> createState() => _State();
}

class _State extends ConsumerState<AddItemSheet> {
  final _name = TextEditingController();
  final _planned = TextEditingController();
  String? _categoryId;
  bool _increaseBudget = false, _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _planned.dispose();
    super.dispose();
  }

  Future<void> _submit(String name, double planned) async {
    // El container se captura antes del await: los datos se refrescan aunque la pantalla ya no esté montada.
    final container = ProviderScope.containerOf(context);
    final increase = _increaseBudget && planned > 0;
    setState(() => _busy = true);
    try {
      await ref.read(periodRepositoryProvider).addItem(
            widget.period.id,
            name: name,
            categoryId: _categoryId,
            planned: planned,
            increaseBudget: increase,
          );
      invalidateFinanceIn(container); // lista de partidas, presupuesto, Períodos, Caja y Resumen anual
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      showSnack(context, 'Partida "$name" agregada');
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ref.invalidate(periodProvider(widget.period.id)); // el estado del período pudo cambiar
      ref.invalidate(periodItemsProvider(widget.period.id));
      showSnack(context, friendlyError(e), error: true);
      setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final fmt = ref.watch(moneyProvider);
    final symbol = ref.watch(currentCurrencyProvider).symbol;
    // Estado fresco: si el período se cerró mientras el modal estaba abierto, no se ofrece el formulario.
    final period = ref.watch(periodProvider(widget.period.id)).valueOrNull ?? widget.period;
    final items = ref.watch(periodItemsProvider(period.id)).valueOrNull ?? const <PeriodItem>[];
    final cats = ref.watch(categoriesProvider).valueOrNull ?? const <Category>[];

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
          const Text('Reabre el período para agregar partidas.', textAlign: TextAlign.center, style: TextStyle(color: AppColors.muted)),
          const SizedBox(height: 18),
          FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Entendido')),
        ]),
      );
    }

    // ---- Validación en vivo ----
    final name = _name.text.trim();
    final amountText = _planned.text.trim();
    final planned = amountText.isEmpty ? 0.0 : parseAmount(amountText); // vacío = sin monto planificado
    final duplicate = name.isNotEmpty && items.any((i) => i.name.trim().toLowerCase() == name.toLowerCase());
    final valid = name.isNotEmpty && !duplicate && planned != null && planned >= 0;
    final value = planned ?? 0.0;

    // ---- Efecto sobre los totales del período ----
    final plannedNow = items.fold<double>(0, (s, i) => s + i.planned);
    final plannedAfter = plannedNow + value;
    final addsBudget = _increaseBudget && value > 0;
    final availableAfter = period.available + (addsBudget ? value : 0);
    final unassignedAfter = availableAfter - plannedAfter;

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          Text('Nueva partida',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800, color: AppColors.forest)),
          Text('en ${period.name}', style: const TextStyle(color: AppColors.muted)),
          const SizedBox(height: 14),
          TextField(
            controller: _name,
            autofocus: true,
            maxLength: 60,
            textCapitalization: TextCapitalization.sentences,
            textInputAction: TextInputAction.next,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: 'Nombre de la partida',
              hintText: 'Ej. Reparación del auto',
              counterText: '',
              errorText: duplicate ? 'Ya existe una partida con ese nombre' : null,
            ),
          ),
          if (cats.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Text('Categoría (opcional)', style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.forest)),
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
                    setState(() {
                      _categoryId = s ? c.id : null;
                      if (s && _name.text.trim().isEmpty) _name.text = c.name; // atajo: nombre = categoría
                    });
                  },
                ),
            ]),
          ],
          const SizedBox(height: 14),
          TextField(
            controller: _planned,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*[.,]?\d{0,2}'))],
            textInputAction: TextInputAction.done,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: 'Monto planificado (opcional)',
              prefixText: '$symbol ',
              errorText: planned == null ? 'Monto no válido' : null,
            ),
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _increaseBudget,
            onChanged: value > 0
                ? (v) {
                    HapticFeedback.selectionClick();
                    setState(() => _increaseBudget = v);
                  }
                : null,
            title: const Text('Sumar al presupuesto del período', style: TextStyle(fontWeight: FontWeight.w600)),
            subtitle: const Text(
              'Actívalo si el gasto imprevisto se financia con dinero adicional.',
              style: TextStyle(fontSize: 12),
            ),
          ),
          AppCard(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Column(children: [
              _Row('Planificado', '${fmt(plannedNow)}  →  ${fmt(plannedAfter)}'),
              _Row('Presupuesto del período', addsBudget ? '${fmt(period.available)}  →  ${fmt(availableAfter)}' : fmt(period.available)),
              _Row(
                unassignedAfter >= 0 ? 'Sin asignar' : 'Excedido',
                fmt(unassignedAfter.abs()),
                color: unassignedAfter >= 0 ? AppColors.emerald : AppColors.danger,
                bold: true,
              ),
            ]),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: valid && !_busy ? () => _submit(name, value) : null,
            icon: _busy
                ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                : const Icon(Icons.add_rounded),
            label: const Text('Agregar partida'),
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