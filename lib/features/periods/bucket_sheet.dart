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
import 'edit_item_sheet.dart';
import 'models.dart';
import 'period_repository.dart';

/// BottomSheet unificado: acumulador + historial (+ edición de la partida).
/// [item] == null  =>  "Otros gastos" (gastos sueltos, sin límite presupuestal).
Future<void> showBucketSheet(BuildContext context, {required Period period, PeriodItem? item}) =>
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => BucketSheet(period: period, item: item),
    );

class BucketSheet extends ConsumerStatefulWidget {
  const BucketSheet({super.key, required this.period, this.item});
  final Period period;
  final PeriodItem? item;
  @override
  ConsumerState<BucketSheet> createState() => _State();
}

class _State extends ConsumerState<BucketSheet> {
  final _input = TextEditingController();
  final _note = TextEditingController();
  late DateTime _date;
  String? _categoryId;
  bool _editMode = false, _busy = false, _showHistory = false;

  /// El id de la partida no cambia al editarla; nombre, categoría y monto salen del estado fresco (ver build).
  String? get _itemId => widget.item?.id;

  @override
  void initState() {
    super.initState();
    final t = today();
    final p = widget.period;
    _date = t.isBefore(p.start) ? p.start : (t.isAfter(p.end) ? p.end : t);
  }

  @override
  void dispose() {
    _input.dispose();
    _note.dispose();
    super.dispose();
  }

  double? get _value => parseAmount(_input.text);

  void _setMode(bool edit, double total) {
    HapticFeedback.selectionClick();
    setState(() {
      _editMode = edit;
      _input.text = edit ? total.toStringAsFixed(2) : '';
      if (edit) _input.selection = TextSelection(baseOffset: 0, extentOffset: _input.text.length);
    });
  }

  Future<void> _pickDate() async {
    final p = widget.period;
    final d = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: p.start,
      lastDate: p.end,
      locale: const Locale('es'),
    );
    if (!mounted) return;
    if (d != null) setState(() => _date = d);
  }

  Future<void> _apply() async {
    final v = _value;
    if (v == null || (_editMode ? v < 0 : v <= 0)) {
      HapticFeedback.heavyImpact();
      showSnack(context, _editMode ? 'Ingresa un total válido' : 'Ingresa un monto mayor a 0', error: true);
      return;
    }
    setState(() => _busy = true);
    try {
      final repo = ref.read(periodRepositoryProvider);
      if (_editMode) {
        await repo.setBucketTotal(widget.period.id, itemId: _itemId, total: v, date: _date);
      } else {
        final note = _note.text.trim();
        await repo.addBucketExpense(
          widget.period.id,
          itemId: _itemId,
          amount: v,
          note: note.isEmpty ? null : note,
          date: _date,
          categoryId: _itemId == null ? _categoryId : null,
        );
      }
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      invalidateFinance(ref);
      setState(() {
        _busy = false;
        _editMode = false;
        _input.clear();
        _note.clear();
      });
    } catch (e) {
      if (!mounted) return;
      showSnack(context, friendlyError(e), error: true);
      setState(() => _busy = false);
    }
  }

  Future<void> _deleteEntry(Expense e) async {
    final fmt = ref.read(moneyProvider);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar movimiento'),
        content: Text('Se quitarán ${fmt(e.amount)} del ${longDate(e.date)}.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(0, 44), backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await ref.read(expenseRepositoryProvider).delete(e.id);
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      invalidateFinance(ref);
      showSnack(context, 'Movimiento eliminado');
    } catch (err) {
      if (!mounted) return;
      showSnack(context, friendlyError(err), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final fmt = ref.watch(moneyProvider);
    final symbol = ref.watch(currentCurrencyProvider).symbol;
    // Estado fresco del período (por si se cierra/reabre mientras el modal está abierto).
    final period = ref.watch(periodProvider(widget.period.id)).valueOrNull ?? widget.period;
    final readOnly = period.isClosed;
    final all = ref.watch(periodExpensesProvider(period.id)).valueOrNull ?? const <Expense>[];
    final cats = ref.watch(categoriesProvider).valueOrNull ?? const <Category>[];
    final catById = {for (final c in cats) c.id: c};

    // La partida se resuelve contra el estado fresco: al editarla, el modal se actualiza al instante.
    final freshItems = ref.watch(periodItemsProvider(period.id)).valueOrNull;
    final PeriodItem? item = widget.item == null
        ? null
        : (freshItems?.where((i) => i.id == widget.item!.id).firstOrNull ?? widget.item);

    // El total del cubo es SIEMPRE la suma de sus movimientos.
    final entries = all.where((e) => e.plannedItemId == _itemId && e.amount > 0).toList();
    final total = entries.fold<double>(0, (s, e) => s + e.amount);

    final isLoose = item == null;
    final canEditItem = !isLoose && !readOnly;
    final planned = item?.planned ?? 0;
    final itemCategory = item?.categoryId == null ? null : catById[item!.categoryId];
    final v = _value;
    final preview = (!_editMode && v != null && v > 0) ? v : null;
    final historyOpen = readOnly || _showHistory;

    void openEdit() => showEditItemSheet(context, period: period, item: item!);

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          // ---- Encabezado: nombre (+ categoría) y botón de edición ----
          Row(children: [
            if (canEditItem) const SizedBox(width: 48), // equilibra el botón para mantener el título centrado
            Expanded(
              child: Column(children: [
                Text(
                  item?.name ?? 'Otros gastos',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800, color: AppColors.forest),
                ),
                if (itemCategory != null)
                  Padding(padding: const EdgeInsets.only(top: 6), child: Pill(itemCategory.name, color: itemCategory.color)),
              ]),
            ),
            if (canEditItem)
              IconButton(
                tooltip: 'Editar partida',
                icon: const Icon(Icons.edit_outlined, color: AppColors.primary),
                onPressed: openEdit,
              ),
          ]),
          if (readOnly)
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Center(child: Pill('Período cerrado · solo lectura', color: AppColors.muted)),
            ),
          const SizedBox(height: 10),
          Center(
            child: TweenAnimationBuilder<double>(
              tween: Tween(end: total),
              duration: const Duration(milliseconds: 350),
              curve: Curves.easeOutCubic,
              builder: (_, value, __) =>
                  Text(fmt(value), style: const TextStyle(fontSize: 40, fontWeight: FontWeight.w800, color: AppColors.forest)),
            ),
          ),
          Center(
            child: isLoose
                ? Text(
                    'Gastos sin partida · ${entries.length} movimiento${entries.length == 1 ? '' : 's'}',
                    style: const TextStyle(color: AppColors.muted),
                  )
                : (planned > 0
                    ? Text('de ${fmt(planned)} planificado', style: const TextStyle(color: AppColors.muted))
                    : (canEditItem
                        // Atajo: una partida de plantilla sin monto invita a definirlo.
                        ? InkWell(
                            borderRadius: BorderRadius.circular(8),
                            onTap: openEdit,
                            child: const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              child: Text(
                                'Sin monto planificado · Definir',
                                style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700, decoration: TextDecoration.underline),
                              ),
                            ),
                          )
                        : const Text('Sin monto planificado', style: TextStyle(color: AppColors.muted)))),
          ),
          if (!isLoose) ...[
            const SizedBox(height: 12),
            MoneyProgressBar(value: planned <= 0 ? (total > 0 ? 1 : 0) : total / planned),
          ],
          if (!readOnly) ...[
            const SizedBox(height: 16),
            SegmentedButton<bool>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: false, icon: Icon(Icons.add_rounded), label: Text('Sumar')),
                ButtonSegment(value: true, icon: Icon(Icons.edit_rounded), label: Text('Editar total')),
              ],
              selected: {_editMode},
              onSelectionChanged: (s) => _setMode(s.first, total),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _input,
              autofocus: true,
              textAlign: TextAlign.center,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
              textInputAction: _editMode ? TextInputAction.done : TextInputAction.next,
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => _editMode && !_busy ? _apply() : null,
              style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
              decoration: InputDecoration(hintText: _editMode ? 'Nuevo total' : 'Monto a sumar', prefixText: '$symbol '),
            ),
            if (!_editMode) ...[
              const SizedBox(height: 10),
              TextField(
                controller: _note,
                maxLength: 140,
                textCapitalization: TextCapitalization.sentences,
                textInputAction: TextInputAction.done,
                decoration: const InputDecoration(
                  labelText: 'Descripción / detalle (opcional)',
                  counterText: '',
                  prefixIcon: Icon(Icons.notes_rounded),
                ),
              ),
              if (isLoose && cats.isNotEmpty) ...[
                const SizedBox(height: 10),
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
              ],
            ],
            const SizedBox(height: 10),
            InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: _pickDate,
              child: InputDecorator(
                decoration: InputDecoration(
                  labelText: _editMode ? 'Fecha del ajuste' : 'Fecha del gasto',
                  suffixIcon: const Icon(Icons.calendar_today_rounded),
                ),
                child: Text(longDate(_date)),
              ),
            ),
            if (preview != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text('Nuevo total: ${fmt(total + preview)}', textAlign: TextAlign.center, style: const TextStyle(color: AppColors.muted)),
              ),
            if (_editMode)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  'Si subes el total se agrega un "Ajuste". Si lo bajas, se recortan primero los movimientos más recientes.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.muted, fontSize: 12),
                ),
              ),
            const SizedBox(height: 14),
            FilledButton(
              onPressed: _busy ? null : _apply,
              child: _busy
                  ? const SizedBox(height: 22, width: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                  : Text(_editMode ? 'Guardar total' : (preview != null ? '+ ${fmt(preview)}' : 'Sumar')),
            ),
            const SizedBox(height: 4),
            TextButton.icon(
              onPressed: () => setState(() => _showHistory = !_showHistory),
              icon: Icon(_showHistory ? Icons.expand_less_rounded : Icons.history_rounded),
              label: Text(_showHistory ? 'Ocultar historial' : 'Ver historial (${entries.length})'),
            ),
          ] else
            const SizedBox(height: 14),
          AnimatedSize(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: historyOpen
                ? _History(
                    entries: entries,
                    categories: catById,
                    onEdit: readOnly ? null : (e) => showAddExpenseSheet(context, period: period, editing: e),
                    onDelete: readOnly ? null : _deleteEntry,
                  )
                : const SizedBox(width: double.infinity),
          ),
        ]),
      ),
    );
  }
}

class _History extends ConsumerWidget {
  const _History({required this.entries, required this.categories, this.onEdit, this.onDelete});
  final List<Expense> entries;
  final Map<String, Category> categories;
  final void Function(Expense)? onEdit;
  final void Function(Expense)? onDelete;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fmt = ref.watch(moneyProvider);
    if (entries.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Text('Aún no hay movimientos.', textAlign: TextAlign.center, style: TextStyle(color: AppColors.muted)),
      );
    }
    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Column(children: [
        for (var i = 0; i < entries.length; i++) ...[
          if (i > 0) const Divider(height: 1),
          InkWell(
            onTap: onEdit == null ? null : () => onEdit!(entries[i]),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(children: [
                SizedBox(
                  width: 56,
                  child: Text(shortDate(entries[i].date), style: const TextStyle(color: AppColors.muted, fontSize: 12, fontWeight: FontWeight.w600)),
                ),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(
                      entries[i].description.isEmpty ? 'Sin detalle' : entries[i].description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: entries[i].description.isEmpty ? AppColors.muted : AppColors.forest,
                      ),
                    ),
                    if (categories[entries[i].categoryId] != null)
                      Text(categories[entries[i].categoryId]!.name, style: const TextStyle(color: AppColors.muted, fontSize: 12)),
                  ]),
                ),
                Text('+ ${fmt(entries[i].amount)}', style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.forest)),
                if (onDelete != null)
                  IconButton(
                    tooltip: 'Eliminar movimiento',
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.delete_outline_rounded, color: AppColors.danger, size: 20),
                    onPressed: () => onDelete!(entries[i]),
                  ),
              ]),
            ),
          ),
        ],
      ]),
    );
  }
}