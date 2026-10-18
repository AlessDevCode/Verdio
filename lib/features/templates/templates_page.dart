import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/errors.dart';
import '../../core/widgets/common.dart';
import '../currency/currency.dart';
import '../home/settings_sheet.dart';
import 'template_editor_page.dart';
import 'template_repository.dart';

class TemplatesPage extends ConsumerWidget {
  const TemplatesPage({super.key});

  void _open(BuildContext context, [ExpenseTemplate? t]) =>
      Navigator.push(context, MaterialPageRoute(builder: (_) => TemplateEditorPage(template: t)));

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fmt = ref.watch(moneyProvider);
    final templates = ref.watch(templatesProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Plantillas'),
        actions: [IconButton(icon: const Icon(Icons.account_circle_outlined), onPressed: () => showSettingsSheet(context))],
      ),
      floatingActionButton: FloatingActionButton.extended(
          icon: const Icon(Icons.add_rounded), label: const Text('Plantilla'), onPressed: () => _open(context)),
      body: AsyncView<List<ExpenseTemplate>>(
        value: templates,
        onRetry: () => ref.invalidate(templatesProvider),
        data: (list) => list.isEmpty
            ? EmptyState(
                icon: Icons.copy_all_rounded,
                title: 'Organiza tus gastos habituales',
                message: 'Crea una plantilla (alquiler, servicios, mercado…) y aplícala al crear cada período.',
                actionLabel: 'Crear plantilla',
                onAction: () => _open(context))
            : ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
                itemCount: list.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (_, i) {
                  final t = list[i];
                  return Dismissible(
                    key: ValueKey(t.id),
                    direction: DismissDirection.endToStart,
                    background: Container(
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.only(right: 20),
                      decoration: BoxDecoration(color: AppColors.danger, borderRadius: BorderRadius.circular(22)),
                      child: const Icon(Icons.delete_outline_rounded, color: Colors.white),
                    ),
                    confirmDismiss: (_) async {
                      final ok = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: Text('¿Eliminar "${t.name}"?'),
                          content: const Text('Los períodos ya creados con esta plantilla no se verán afectados.'),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
                            FilledButton(
                                style: FilledButton.styleFrom(minimumSize: const Size(0, 44), backgroundColor: AppColors.danger),
                                onPressed: () => Navigator.pop(ctx, true),
                                child: const Text('Eliminar')),
                          ],
                        ),
                      );
                      if (ok == true) {
                        try {
                          await ref.read(templateRepositoryProvider).delete(t.id);
                          ref.invalidate(templatesProvider);
                        } catch (e) {
                          if (context.mounted) showSnack(context, friendlyError(e), error: true);
                        }
                      }
                      return false;
                    },
                    child: AppCard(
                      onTap: () => _open(context, t),
                      child: Row(children: [
                        const CircleAvatar(backgroundColor: AppColors.mint, child: Icon(Icons.copy_all_rounded, color: AppColors.primary)),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(t.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                            Text('${t.items.length} partidas · ${fmt(t.total)}', style: const TextStyle(color: AppColors.muted)),
                          ]),
                        ),
                        const Icon(Icons.chevron_right_rounded, color: AppColors.muted),
                      ]),
                    ),
                  );
                },
              ),
      ),
    );
  }
}
