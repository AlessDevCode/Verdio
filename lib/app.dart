import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:verdio/core/providers.dart';
import 'package:verdio/core/theme/app_theme.dart';
import 'package:verdio/features/auth/login_page.dart';
import 'package:verdio/features/home/home_shell.dart';

/// Widget raíz de la aplicación.
class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Verdio',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        locale: const Locale('es'),
        supportedLocales: const [Locale('es'), Locale('en')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: const _AuthGate(),
      );
}

/// Muestra el login o la app según exista sesión.
class _AuthGate extends ConsumerWidget {
  const _AuthGate();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      child: session.when(
        data: (s) => s == null
            ? const LoginPage(key: ValueKey('login'))
            : const HomeShell(key: ValueKey('home')),
        loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
        error: (_, __) => const LoginPage(key: ValueKey('login-error')),
      ),
    );
  }
}