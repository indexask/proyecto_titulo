/// Variables de entorno provistas en tiempo de compilación vía
/// `--dart-define-from-file=env/dev.json` (ver env/dev.json.example).
class Env {
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  /// Firebase Cloud Messaging: SOLO canal de envío de notificaciones push
  /// (RF-19). Si no se configuran, la app funciona sin push.
  static const firebaseApiKey = String.fromEnvironment('FIREBASE_API_KEY');
  static const firebaseProjectId = String.fromEnvironment('FIREBASE_PROJECT_ID');
  static const firebaseMessagingSenderId = String.fromEnvironment('FIREBASE_MESSAGING_SENDER_ID');
  static const firebaseAppIdAndroid = String.fromEnvironment('FIREBASE_APP_ID_ANDROID');
  static const firebaseAppIdIos = String.fromEnvironment('FIREBASE_APP_ID_IOS');

  static bool get isConfigured => supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;

  static bool get firebaseConfigurado =>
      firebaseApiKey.isNotEmpty && firebaseProjectId.isNotEmpty && firebaseMessagingSenderId.isNotEmpty;
}
