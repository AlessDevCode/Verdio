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
import 'fund_repository.dart';

/// [context] debe ser el de la página (se usa para reabrir el formulario de edición).
Future<void> showFundEntrySheet(BuildContext context, FundEntry entry) => showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => FundEntrySheet(entry: entry, pageContext: context),
    );

class FundEntrySheet extends ConsumerStatefulWidget {
  const FundEntrySheet({super.key, required this.entry, required this.pageContext});
  final FundEntry entry;
  final BuildContext pageContext;
  @override
  ConsumerState<FundEntrySheet> createState() => _State();
}

class _State extends ConsumerState<FundEntrySheet> {
  late final _amount = TextEditingController(text: widget.entry.amount.toStringAsFixed(2));
  late final _note = TextEditingController(text: widget.entry.title);
  bool _busy = false;

  FundEntry get e => widget.entry;

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action, String okMessage) async {
    setState(() => _busy = true);
    try {
      await action();
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      invalidateFinance(ref);
      showSnack(context, okMessage);
      Navigator.pop(context);
    } catch (err) {
      if (!mounted) return;
      showSnack(context, friendlyError(err), error: true);
      setState(() => _busy = false);
    }
  }

  Future<void> _saveMovement() async {
    final v = parseAmount(_amount.text);
    if (v == null || v <= 0) {
      HapticFeedback.heavyImpact();
      showSnack(context, 'Ingresa un monto mayor a 0', error: true);
      return;
    }
    await _run(() => ref.read(fundRepositoryProvider).updateMovement(e.id, v, _note.text.trim()), 'Movimiento actualizado');
  }

  Future<void> _delete() async {
    final isRemainder = e.kind == FundEntryKind.remainderIn;
    final message = switch (e.kind) {
      FundEntryKind.expense => 'Se eliminará este gasto y el monto volverá al saldo de la Caja.',
      FundEntryKind.replenishment => 'Se revertirá la transferencia: el monto volverá a la Caja y el período recibirá menos presupuesto.',
      FundEntryKind.deposit => 'Se eliminará este ingreso y bajará el saldo de la Caja. Solo es posible si el saldo no queda negativo.',
      FundEntryKind.remainderIn => 'Se revertirá el envío: el remanente saldrá de la Caja y el período volverá a mostrar "remanente pendiente".',
    };
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isRemainder ? 'Revertir envío' : 'Eliminar movimiento'),
        content: Text(message),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(0, 44), backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(isRemainder ? 'Revertir' : 'Eliminar'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await _run(() async {
      if (e.kind == FundEntryKind.expense) {
        await ref.read(expenseRepositoryProvider).delete(e.id);
      } else {
        await ref.read(fundRepositoryProvider).deleteMovement(e.id);
      }
    }, isRemainder ? 'Envío revertido' : 'Movimiento eliminado');
  }

  @override
  Widget build(BuildContext context) {
    final fmt = ref.watch(moneyProvider);
    final symbol = ref.watch(currentCurrencyProvider).symbol;
    final (label, color) = switch (e.kind) {
      FundEntryKind.remainderIn => ('Remanente recibido', AppColors.emerald),
      FundEntryKind.replenishment => ('Reposición a un período', AppColors.amber),
      FundEntryKind.deposit => (e.depositKind?.label ?? 'Ingreso a la Caja', AppColors.emerald),
      FundEntryKind.expense => ('Gasto directo', AppColors.danger),
    };

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          Align(alignment: Alignment.centerLeft, child: Pill(label, color: color)),
          const SizedBox(height: 12),
          Text(e.title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800, color: AppColors.forest)),
          Text(longDate(e.date), style: const TextStyle(color: AppColors.muted)),
          const SizedBox(height: 12),
          if (!e.isEditableMovement)
            Text(
              '${e.isIncome ? '+' : '-'}${fmt(e.amount)}',
              style: TextStyle(fontSize: 34, fontWeight: FontWeight.w800, color: e.isIncome ? AppColors.emerald : AppColors.forest),
            ),
          const SizedBox(height: 12),
          if (e.isEditableMovement) ...[
            TextField(
              controller: _amount,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
              decoration: InputDecoration(
                labelText: e.kind == FundEntryKind.deposit ? 'Monto ingresado' : 'Monto transferido',
                prefixText: '$symbol ',
              ),
            ),
            const SizedBox(height: 12),
            TextField(controller: _note, decoration: const InputDecoration(labelText: 'Nota')),
            const SizedBox(height: 16),
            FilledButton(onPressed: _busy ? null : _saveMovement, child: const Text('Guardar cambios')),
          ] else if (e.kind == FundEntryKind.expense) ...[
            FilledButton.icon(
              onPressed: _busy
                  ? null
                  : () {
                      Navigator.pop(context);
                      showAddExpenseSheet(widget.pageContext, fromFund: true, editing: e.expense);
                    },
              icon: const Icon(Icons.edit_rounded),
              label: const Text('Editar gasto'),
            ),
          ] else
            const AppCard(
              child: Row(children: [
                Icon(Icons.info_outline_rounded, color: AppColors.muted),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Este monto proviene del cierre del período, por eso no se edita aquí. Puedes revertir el envío si fue un error.',
                    style: TextStyle(color: AppColors.muted),
                  ),
                ),
              ]),
            ),
          
          if (e.isInitialFund)
            const Padding(
              padding: EdgeInsets.only(top: 12),
              child: Text(
                'El fondo inicial es único: puedes editar su monto o su nota, pero no eliminarlo.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.muted, fontSize: 12),
              ),
            )
          else ...[
            const SizedBox(height: 10),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.danger,
                side: const BorderSide(color: AppColors.danger),
              ),
              onPressed: _busy ? null : _delete,
              icon: Icon(e.kind == FundEntryKind.remainderIn ? Icons.undo_rounded : Icons.delete_outline_rounded),
              label: Text(e.kind == FundEntryKind.remainderIn ? 'Revertir envío' : 'Eliminar'),
            ),
          ],
        ]),
      ),
    );
  }
}