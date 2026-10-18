import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/errors.dart';
import '../../core/utils/formatters.dart';
import '../currency/currency.dart';
import '../expenses/expense_repository.dart';
import 'template_repository.dart';

class _Row {
  _Row({String name = '', double planned = 0, this.categoryId})
      : name = TextEditingController(text: name),
        planned = TextEditingController(text: planned == 0 ? '' : planned.toString());
  final TextEditingController name, planned;
  String? categoryId;
}

class TemplateEditorPage extends ConsumerStatefulWidget {
  const TemplateEditorPage({super.key, this.template});
  final ExpenseTemplate? template;
  @override
  ConsumerState<TemplateEditorPage> createState() => _State();
}

class _State extends ConsumerState<TemplateEditorPage> {
  late final TextEditingController _name = TextEditingController(text: widget.template?.name ?? '');
  late final List<_Row> _rows = [
    for (final i in widget.template?.items ?? <TemplateItem>[])
      _Row(name: i.name, planned: i.planned, categoryId: i.categoryId),
  ];
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    for (final r in _rows) {
      r.name.dispose();
      r.planned.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) return showSnack(context, 'Ponle un nombre a la plantilla', error: true);
    final items = <TemplateItem>[];
    for (final r in _rows) {
      if (r.name.text.trim().isEmpty) continue;
      items.add(TemplateItem(name: r.name.text.trim(), categoryId: r.categoryId, planned: parseAmount(r.planned.text) ?? 0));
    }
    setState(() => _busy = true);
    try {
      await ref.read(templateRepositoryProvider).save(id: widget.template?.id, name: _name.text.trim(), items: items);
      if (!mounted) return;
      ref.invalidate(templatesProvider);
      HapticFeedback.mediumImpact();
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
    return Scaffold(
      appBar: AppBar(title: Text(widget.template == null ? 'Nueva plantilla' : 'Editar plantilla')),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton(
            onPressed: _busy ? null : _save,
            child: _busy
                ? const SizedBox(height: 22, width: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                : const Text('Guardar plantilla'),
          ),
        ),
      ),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 24), children: [
        TextField(
          controller: _name,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(labelText: 'Nombre de la plantilla'),
        ),
        const SizedBox(height: 20),
        Text('Partidas', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800, color: AppColors.forest)),
        const SizedBox(height: 10),
        for (var i = 0; i < _rows.length; i++)
          Padding(
            key: ObjectKey(_rows[i]),
            padding: const EdgeInsets.only(bottom: 12),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(children: [
                Row(children: [
                  Expanded(child: TextField(controller: _rows[i].name, decoration: const InputDecoration(labelText: 'Concepto'))),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: AppColors.muted),
                    onPressed: () => setState(() => _rows.removeAt(i)),
                  ),
                ]),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(
                    child: TextField(
                      controller: _rows[i].planned,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
                      decoration: InputDecoration(labelText: 'Monto', prefixText: '$symbol '),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: DropdownButtonFormField<String?>(
                      // initialValue solo se lee al crear el campo: la key lo reconstruye cuando cargan las categorías.
                      key: ValueKey('cat-${identityHashCode(_rows[i])}-${cats.length}'),
                      isExpanded: true,
                      initialValue: cats.any((c) => c.id == _rows[i].categoryId) ? _rows[i].categoryId : null,
                      decoration: const InputDecoration(labelText: 'Categoría'),
                      items: [
                        const DropdownMenuItem(value: null, child: Text('—')),
                        for (final c in cats) DropdownMenuItem(value: c.id, child: Text(c.name, overflow: TextOverflow.ellipsis)),
                      ],
                      onChanged: (v) => setState(() => _rows[i].categoryId = v),
                    ),
                  ),
                ]),
              ]),
            ),
          ),
        OutlinedButton.icon(
          onPressed: () {
            HapticFeedback.selectionClick();
            setState(() => _rows.add(_Row()));
          },
          icon: const Icon(Icons.add_rounded),
          label: const Text('Agregar partida'),
        ),
      ]),
    );
  }
}