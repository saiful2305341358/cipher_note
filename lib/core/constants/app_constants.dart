/// Application-wide constant values.
///
/// Keep these in sync with `pubspec.yaml` when the version changes.
class AppConstants {
  AppConstants._();

  static const String appName = 'Cipher Note';
  static const String appVersion = '1.2.0';
  static const int buildNumber = 3;
  static const String developmentPhase = 'Phase 3 · Hill Cipher';

  static const String appDescription =
      'A minimalist note-taking app for English and Bangla. Notes are '
      'saved on your device and can optionally be encrypted with your own '
      'Hill Cipher key — an educational cipher, not strong protection.';

  /// Debounce delay before the editor saves changes while auto-save is on.
  static const Duration autoSaveDelay = Duration(milliseconds: 600);
}
