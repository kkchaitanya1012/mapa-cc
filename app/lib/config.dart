/// Build-time settings, passed with `--dart-define-from-file=config.local.json`.
/// The anon key is public by design; row-level security protects the data.
class Config {
  static const _url = String.fromEnvironment('SUPABASE_URL');
  static const _key = String.fromEnvironment('SUPABASE_ANON_KEY');
  static const _api = String.fromEnvironment('API_BASE_URL', defaultValue: 'http://127.0.0.1:8000');

  // Trimmed because values pasted from dashboards often carry stray spaces.
  static String get supabaseUrl => _url.trim();
  static String get supabaseAnonKey => _key.trim();
  static String get apiBaseUrl => _api.trim();

  // Firebase (push). From the Android app's entry in Firebase project settings.
  static const _fbKey = String.fromEnvironment('FIREBASE_API_KEY');
  static const _fbApp = String.fromEnvironment('FIREBASE_APP_ID');
  static const _fbSender = String.fromEnvironment('FIREBASE_SENDER_ID');
  static const _fbProject = String.fromEnvironment('FIREBASE_PROJECT_ID');

  static String get firebaseApiKey => _fbKey.trim();
  static String get firebaseAppId => _fbApp.trim();
  static String get firebaseSenderId => _fbSender.trim();
  static String get firebaseProjectId => _fbProject.trim();

  static bool get pushIsSet =>
      firebaseApiKey.isNotEmpty && firebaseAppId.isNotEmpty && firebaseSenderId.isNotEmpty && firebaseProjectId.isNotEmpty;

  static bool get isSet => supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;
}
