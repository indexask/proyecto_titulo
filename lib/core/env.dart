/// Variables de entorno provistas en tiempo de compilación vía
/// `--dart-define-from-file=env/dev.json` (ver env/dev.json.example).
class Env {
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  static bool get isConfigured =>
      supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;
}
