import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/refresh.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/errors.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/common.dart';
import '../currency/currency.dart';
import 'fund_repository.dart';

/// Registra un ingreso en la Caja General.
/// Los tipos disponibles dependen del estado de la Caja (ver [FundStatus.availableKinds]).
Future<void> showFundDepositSheet(BuildContext context) => showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => const FundDepositSheet(),
    );

class FundDepositSheet extends ConsumerWidget {
  const FundDepositSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Se espera al historial: sin él no se sabe qué tipos de ingreso ofrecer.
    final status = ref.watch(fundStatusProvider);
    return status.when(
      loading: () => const SizedBox(height: 220, child: Center(child: CircularProgressIndicator())),
      error: (e, _) => SizedBox(
        height: 280,
        child: EmptyState(
          icon: Icons.cloud_off_rounded,
          title: 'No se pudo cargar la Caja',
          message: friendlyError(e),
          actionLabel: 'Reintentar',
          onAction: () => ref.invalidate(fundFeedProvider),
        ),
      ),
      data: (s) => _DepositForm(status: s),
    );
  }
}

class _DepositForm extends ConsumerStatefulWidget {
  const _DepositForm({required this.status});
  final FundStatus status;
  @override
  ConsumerState<_DepositForm> createState() => _State();
}

class _State extends ConsumerState<_DepositForm> {
  final _amount = TextEditingController();
  final _note = TextEditingController();
  late DepositKind _kind = widget.status.availableKinds.first; // fondo inicial preseleccionado si existe
  bool _busy = false;

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final v = parseAmount(_amount.text);
    if (v == null || v <= 0) {
      HapticFeedback.heavyImpact();
      showSnack(context, 'Ingresa un monto mayor a 0', error: true);
      return;
    }
    if (_kind == DepositKind.initial) {
      final fmt = ref.read(moneyProvider);
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Registrar fondo inicial'),
          content: Text('Vas a registrar ${fmt(v)} como tu fondo inicial. Solo puede existir uno: después podrás editar su monto, pero no duplicarlo ni eliminarlo.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Revisar')),
            FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Registrar'),
            ),
          ],
        ),
      );
      if (ok != true || !mounted) return;
    }

    final container = ProviderScope.containerOf(context);
    setState(() => _busy = true);
    try {
      final note = _note.text.trim();
      await ref.read(fundRepositoryProvider).deposit(v, _kind, note.isEmpty ? null : note);
      invalidateFinanceIn(container);
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      showSnack(context, '${_kind.label} registrado en la Caja General');
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      // El servidor puede rechazar por un estado más nuevo (p. ej. el fondo inicial ya existe): se refresca.
      invalidateFinanceIn(container);
      showSnack(context, friendlyError(e), error: true);
      setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final symbol = ref.watch(currentCurrencyProvider).symbol;
    final kinds = widget.status.availableKinds;
    final locked = kinds.length == 1;

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          Text('Ingresar dinero a la Caja',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800, color: AppColors.forest)),
          const SizedBox(height: 4),
          Text(
            locked
                ? 'Tu Caja está vacía: el primer ingreso es tu fondo inicial. No pertenece a ningún período ni cuenta como gasto.'
                : 'No pertenece a ningún período ni cuenta como gasto.',
            style: const TextStyle(color: AppColors.muted, fontSize: 13),
          ),
          const SizedBox(height: 14),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final k in kinds)
              ChoiceChip(
                avatar: locked ? const Icon(Icons.lock_rounded, size: 16) : null,
                label: Text(k.label),
                selected: _kind == k,
                showCheckmark: false,
                // Con una sola opción disponible el chip queda fijo (no se puede deseleccionar).
                onSelected: locked
                    ? null
                    : (_) {
                        HapticFeedback.selectionClick();
                        setState(() => _kind = k);
                      },
              ),
          ]),
          if (!widget.status.hasInitial && !locked)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                'Aún no registraste tu fondo inicial. Solo puede registrarse una vez.',
                style: TextStyle(color: AppColors.muted, fontSize: 12),
              ),
            ),
          const SizedBox(height: 8),
          TextField(
            controller: _amount,
            autofocus: true,
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
            controller: _note,
            maxLength: 140,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(labelText: 'Nota (opcional)', hintText: _kind.label, counterText: ''),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _busy ? null : _save,
            icon: _busy
                ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                : const Icon(Icons.add_rounded),
            label: Text('Registrar ${_kind.label.toLowerCase()}'),
          ),
        ]),
      ),
    );
  }
}