import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final supabaseProvider = Provider<SupabaseClient>((_) => Supabase.instance.client);

/// Sesión reactiva (emite la actual al suscribirse y luego cada cambio).
final sessionProvider = StreamProvider<Session?>((ref) async* {
  final c = ref.watch(supabaseProvider);
  yield c.auth.currentSession;
  await for (final s in c.auth.onAuthStateChange) {
    yield s.session;
  }
});

/// Todos los providers de datos observan este id: al cambiar de usuario
/// se reconstruyen y NUNCA se muestran datos del usuario anterior.
final userIdProvider = Provider<String?>((ref) => ref.watch(sessionProvider).valueOrNull?.user.id);
