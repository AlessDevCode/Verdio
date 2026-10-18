import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:verdio/app.dart';
import 'package:verdio/core/config/env.dart';

// Permite que los tests importen `main.dart` y encuentren `App`.
export 'package:verdio/app.dart' show App;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Si olvidaste los --dart-define, mostramos un aviso claro en vez de un crash.
  if (Env.isMissingSupabaseConfig) {
    runApp(const _MissingConfigApp());
    return;
  }

  // App exclusiva para móvil en vertical.
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  await initializeDateFormatting('es');
  await Supabase.initialize(
    url: Env.supabaseUrl,
    publishableKey: Env.supabaseAnonKey,
  );

  runApp(const ProviderScope(child: App()));
}

class _MissingConfigApp extends StatelessWidget {
  const _MissingConfigApp();

  @override
  Widget build(BuildContext context) => const MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          body: Padding(
            padding: EdgeInsets.all(24),
            child: Center(
              child: Text(
                'Faltan credenciales de Supabase.\n\n'
                'Ejecuta la app con:\n'
                '--dart-define=SUPABASE_URL=...\n'
                '--dart-define=SUPABASE_ANON_KEY=...',
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
      );
}