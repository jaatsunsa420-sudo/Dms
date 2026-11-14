class AppConfig {
  // Optional: Paste default URL/Key here, OR enter directly inside the App Login screen!
  static const String defaultSupabaseUrl = '';
  static const String defaultSupabaseAnonKey = '';
}

class AppStrings {
  static bool isHindi = false;
  static String t(String en, String hi) => isHindi ? hi : en;
}
