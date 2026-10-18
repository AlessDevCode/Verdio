import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/errors.dart';
import '../auth/auth_repository.dart';
import '../currency/currency.dart';

void showSettingsSheet(BuildContext context) => showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      builder: (_) => const _SettingsSheet(),
    );

class _SettingsSheet extends ConsumerWidget {
  const _SettingsSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final email = ref.watch(supabaseProvider).auth.currentUser?.email ?? '';
    final currencies = ref.watch(currenciesProvider).valueOrNull ?? const <Currency>[];
    final selected = ref.watch(currentCurrencyProvider).code;

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.8),
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const CircleAvatar(backgroundColor: AppColors.mint, child: Icon(Icons.person_rounded, color: AppColors.primary)),
            title: const Text('Mi cuenta', style: TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text(email),
          ),
          const Padding(
            padding: EdgeInsets.only(top: 12, bottom: 4),
            child: Text('Moneda', style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.forest)),
          ),
          for (final c in currencies)
            ListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              leading: SizedBox(
                width: 36,
                child: Text(c.symbol, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.primary)),
              ),
              title: Text('${c.code} · ${c.name}'),
              trailing: c.code == selected ? const Icon(Icons.check_circle_rounded, color: AppColors.emerald) : null,
              onTap: () async {
                try {
                  await ref.read(currencyCodeProvider.notifier).select(c.code);
                } catch (e) {
                  if (!context.mounted) return;
                  showSnack(context, friendlyError(e), error: true);
                }
              },
            ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(foregroundColor: AppColors.danger, side: const BorderSide(color: AppColors.danger)),
            icon: const Icon(Icons.logout_rounded),
            label: const Text('Cerrar sesión'),
            onPressed: () async {
              Navigator.pop(context);
              await ref.read(authRepositoryProvider).signOut();
            },
          ),
        ],
      ),
    );
  }
}