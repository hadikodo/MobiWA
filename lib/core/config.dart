/// Supabase connection. The publishable key is designed to ship inside apps:
/// row-level security in the database decides what each user can see.
/// Override at build time with --dart-define=SUPABASE_URL=... / SUPABASE_KEY=...
class Config {
  Config._();

  static const supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://lyrsxywtqalwelbgydbc.supabase.co',
  );

  static const supabaseKey = String.fromEnvironment(
    'SUPABASE_KEY',
    defaultValue: 'sb_publishable_oxfE-ZqhXKxnEpDAEU9Xyw_EB5_SN7_',
  );

  /// Keep in sync with "version:" in pubspec.yaml.
  static const appVersion = '1.0.0';

  /// Public website (landing page) and the pages Google Play requires.
  static const website = 'https://mobiwa.com';
  static const privacyUrl = '$website/privacy';
  static const termsUrl = '$website/terms';
  static const deleteAccountUrl = '$website/delete-account';
  static const supportEmail = 'support@mobiwa.com';

  /// Chrome extension used by the web app to work inside WhatsApp Web.
  static const extensionUrl = '$website/extension';

  /// Usernames without "@" are stored in Supabase Auth as
  /// <username>@users.mobiwa.app. Must match supabase/functions/admin-users.
  static const userEmailDomain = 'users.mobiwa.app';
}
