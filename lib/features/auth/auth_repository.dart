import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/config/env.dart';
import '../../core/providers.dart';

class AuthRepository {
  AuthRepository(this._c);
  final SupabaseClient _c;

  Future<void> signIn(String email, String password) =>
      _c.auth.signInWithPassword(email: email, password: password);

  Future<AuthResponse> signUp(String email, String password) =>
      _c.auth.signUp(email: email, password: password);

  Future<void> resetPassword(String email) => _c.auth.resetPasswordForEmail(email);

  /// Google nativo -> idToken -> Supabase (sin redirecciones web).
  Future<void> signInWithGoogle() async {
    final google = GoogleSignIn(
      serverClientId: '589096907164-6plnm5pgs7uc548rqoghn6307qag94hl.apps.googleusercontent.com',
    );
    final account = await google.signIn();
    if (account == null) return;
    final tokens = await account.authentication;
    final idToken = tokens.idToken;
    if (idToken == null) throw Exception('Google no devolvió un idToken.');
    await _c.auth.signInWithIdToken(
      provider: OAuthProvider.google,
      idToken: idToken,
      accessToken: tokens.accessToken,
    );
  }

  Future<void> signOut() async {
    try {
      await GoogleSignIn().signOut();
    } catch (_) {}
    await _c.auth.signOut();
  }
}

final authRepositoryProvider = Provider((ref) => AuthRepository(ref.watch(supabaseProvider)));
