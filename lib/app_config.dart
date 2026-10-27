/// Client configuration contains public project identifiers only.
/// Supply them at build time with SUPABASE_URL and SUPABASE_PUBLISHABLE_KEY.
abstract final class AppConfig {
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabasePublishableKey =
      String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');

  static bool get isConfigured =>
      supabaseUrl.startsWith('https://') &&
      supabaseUrl.endsWith('.supabase.co') &&
      supabasePublishableKey.startsWith('sb_publishable_');
}
