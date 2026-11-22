/// Application-wide constant values.
///
/// Keep these in sync with `pubspec.yaml` when the version changes.
class AppConstants {
  AppConstants._();

  static const String appName = 'Cipher Note';
  static const String appVersion = '1.1.0';
  static const int buildNumber = 2;
  static const String developmentPhase = 'Phase 2 · Local storage';

  static const String appDescription =
      'A minimalist note-taking app for English and Bangla. Notes are '
      'saved on your device. Optional note encryption with your own Hill '
      'Cipher key is planned for a future update.';

  /// Debounce delay before the editor saves changes while auto-save is on.
  static const Duration autoSaveDelay = Duration(milliseconds: 600);
}
