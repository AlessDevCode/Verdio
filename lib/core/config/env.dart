/// Valores inyectados en compilación con --dart-define:
///
/// flutter run \
///   --dart-define=SUPABASE_URL=https://xxxx.supabase.co \
///   --dart-define=SUPABASE_ANON_KEY=sb_publishable_xxxx \
///   --dart-define=GOOGLE_WEB_CLIENT_ID=xxxx.apps.googleusercontent.com \
///   --dart-define=GOOGLE_IOS_CLIENT_ID=xxxx.apps.googleusercontent.com
///
/// `supabaseAnonKey` guarda la clave pública del proyecto (la "publishable key").
/// Se mantiene el nombre del campo para no tocar otros archivos.
class Env {
  const Env._();

  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
  static const googleWebClientId = String.fromEnvironment('GOOGLE_WEB_CLIENT_ID');
  static const googleIosClientId = String.fromEnvironment('GOOGLE_IOS_CLIENT_ID');

  /// true si falta alguna credencial obligatoria de Supabase.
  static bool get isMissingSupabaseConfig => supabaseUrl.isEmpty || supabaseAnonKey.isEmpty;
}