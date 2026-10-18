import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

String friendlyError(Object e) {
  if (e is PostgrestException) {
    if (e.code == '23P01') return 'Las fechas se solapan con otro período existente.';
    if (e.code == '23505') return 'Ese registro ya existe.';
    return e.message;
  }
  if (e is AuthException) return e.message;
  return e.toString().replaceFirst('Exception: ', '');
}

void showSnack(BuildContext context, String message, {bool error = false}) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: error ? const Color(0xFFC0392B) : const Color(0xFF0B3D2E),
    ));
}
