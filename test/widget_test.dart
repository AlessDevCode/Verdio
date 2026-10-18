import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:verdio/core/providers.dart';
import 'package:verdio/main.dart';

void main() {
  testWidgets('Sin sesión se muestra la pantalla de login', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        // Evita depender de Supabase.initialize() en el test.
        overrides: [
          sessionProvider.overrideWith((ref) => Stream<Session?>.value(null)),
        ],
        child: const App(),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Verde Finanzas'), findsOneWidget);
    expect(find.text('Iniciar sesión'), findsOneWidget);
  });
}