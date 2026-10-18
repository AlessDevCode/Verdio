import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/refresh.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/errors.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/common.dart';
import '../currency/currency.dart';
import 'models.dart';
import 'period_repository.dart';

/// Modal de reposición desde la Caja.
/// El monto sugerido es el máximo posible, min(déficit, saldo de la Caja), y es editable hacia abajo.
Future<void> showReplenishSheet(BuildContext context, {required Period period}) => showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => ReplenishSheet(period: period),
    );

class ReplenishSheet extends ConsumerWidget {
  const ReplenishSheet({super.key, required this.period});
  final Period period;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final limits = ref.watch(replenishLimitsProvider(period.id));
    return limits.when(
      loading: () => const SizedBox(height: 240, child: Center(child: CircularProgressIndicator())),
      error: (e, _) => SizedBox(
        height: 300,
        child: EmptyState(
          icon: Icons.cloud_off_rounded,
          title: 'No se pudieron calcular los topes',
          message: friendlyError(e),
          actionLabel: 'Reintentar',
          onAction: () => ref.invalidate(replenishLimitsProvider(period.id)),
        ),
      ),
      data: (l) => _Form(period: period, limits: l),
    );
  }
}

class _Form extends ConsumerStatefulWidget {
  const _Form({required this.period, required this.limits});
  final Period period;
  final ReplenishLimits limits;
  @override
  ConsumerState<_Form> createState() => _FormState();
}

class _FormState extends ConsumerState<_Form> {
  late final _amount = TextEditingController(text: widget.limits.max > 0 ? widget.limits.max.toStringAsFixed(2) : '');
  bool _busy = false;

  ReplenishLimits get l => widget.limits;

  // Se compara en céntimos enteros para evitar errores de coma flotante.
  int get _deficitCents => (l.deficit * 100).round();
  int get _fundCents => (l.fund * 100).round();
  int get _maxCents => (l.max * 100).round();

  int? get _cents {
    final v = parseAmount(_amount.text);
    return v == null ? null : (v * 100).round();
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  /// Mensaje de error de validación, o null si el monto es válido.
  String? _error(String Function(num) fmt) {
    final c = _cents;
    if (c == null || c <= 0) return 'Ingresa un monto mayor a 0';
    if (c > _deficitCents) return 'No puede superar el déficit del período (${fmt(l.deficit)})';
    if (c > _fundCents) return 'No puede superar el saldo de la Caja (${fmt(l.fund)})';
    return null;
  }

  void _set(double v) {
    HapticFeedback.selectionClick();
    setState(() => _amount.text = v.toStringAsFixed(2));
  }

  Future<void> _submit() async {
    final c = _cents;
    if (c == null || c <= 0) return;
    final amount = c / 100;
    final container = ProviderScope.containerOf(context);
    setState(() => _busy = true);
    try {
      await ref.read(periodRepositoryProvider).replenish(widget.period.id, amount);
      invalidateFinanceIn(container); // Períodos, Caja y Resumen anual se refrescan juntos
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      showSnack(context, amount * 100 >= _deficitCents ? 'Déficit cubierto' : 'Reposición parcial realizada');
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      showSnack(context, friendlyError(e), error: true);
      ref.invalidate(replenishLimitsProvider(widget.period.id)); // los topes pudieron cambiar
      setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final fmt = ref.watch(moneyProvider);
    final symbol = ref.watch(currentCurrencyProvider).symbol;

    // Sin déficit o sin saldo: no hay nada que ofrecer; se explica por qué.
    if (_deficitCents <= 0) {
      return _Notice(
        icon: Icons.check_circle_outline_rounded,
        title: 'Sin déficit',
        message: '"${widget.period.name}" no tiene déficit: no hay nada que reponer desde la Caja.',
      );
    }
    if (_fundCents <= 0) {
      return _Notice(
        icon: Icons.savings_outlined,
        title: 'Caja General sin saldo',
        message:
            'La Caja no tiene saldo disponible (${fmt(l.fund)}). Necesitas ${fmt(l.deficit)} para cubrir el déficit total. Ingresa dinero en la Caja o envía el remanente de otro período.',
      );
    }

    final err = _error(fmt);
    final cents = _cents;
    final valid = err == null && cents != null;
    final value = valid ? cents / 100 : 0.0;
    final isPartial = valid && cents < _deficitCents;

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          Text('Reponer desde la Caja',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800, color: AppColors.forest)),
          const SizedBox(height: 2),
          const Text('Es una transferencia interna: no cuenta como gasto.', style: TextStyle(color: AppColors.muted, fontSize: 13)),
          const SizedBox(height: 12),
          AppCard(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Column(children: [
              _InfoRow('Déficit del período', fmt(l.deficit), color: AppColors.danger),
              _InfoRow('Saldo en la Caja', fmt(l.fund)),
              _InfoRow('Máximo reponible', fmt(l.max), bold: true),
            ]),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _amount,
            autofocus: true,
            textAlign: TextAlign.center,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            // Hasta 2 decimales, solo dígitos y separador.
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*[.,]?\d{0,2}'))],
            onChanged: (_) => setState(() {}),
            style: const TextStyle(fontSize: 36, fontWeight: FontWeight.w800, color: AppColors.forest),
            decoration: InputDecoration(
              hintText: '0.00',
              prefixText: '$symbol ',
              prefixStyle: const TextStyle(fontSize: 26, color: AppColors.muted),
              errorText: err,
              errorMaxLines: 2,
            ),
          ),
          const SizedBox(height: 8),
          Row(children: [
            ActionChip(label: Text('Máximo (${fmt(l.max)})'), onPressed: () => _set(l.max)),
            const SizedBox(width: 8),
            ActionChip(label: const Text('50 %'), onPressed: () => _set((_maxCents ~/ 2) / 100)),
          ]),
          if (valid)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                isPartial
                    ? 'Reposición parcial: seguirán faltando ${fmt(l.deficit - value)} en el período. La Caja quedará con ${fmt(l.fund - value)}.'
                    : 'Cubrirás todo el déficit. La Caja quedará con ${fmt(l.fund - value)}.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.muted, fontSize: 13),
              ),
            ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: valid && !_busy ? _submit : null,
            child: _busy
                ? const SizedBox(height: 22, width: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                : Text(valid ? 'Reponer ${fmt(value)}' : 'Reponer'),
          ),
        ]),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow(this.label, this.value, {this.color, this.bold = false});
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

class _Notice extends StatelessWidget {
  const _Notice({required this.icon, required this.title, required this.message});
  final IconData icon;
  final String title, message;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Icon(icon, size: 44, color: AppColors.primary),
          const SizedBox(height: 10),
          Text(title,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800, color: AppColors.forest)),
          const SizedBox(height: 6),
          Text(message, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.muted)),
          const SizedBox(height: 18),
          FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Entendido')),
        ]),
      );
}