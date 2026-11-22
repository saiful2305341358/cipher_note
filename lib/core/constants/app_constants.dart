/// Application-wide constant values.
///
/// Keep these in sync with `pubspec.yaml` when the version changes.
class AppConstants {
  AppConstants._();

  static const String appName = 'Cipher Note';
  static const String appVersion = '1.0.0';
  static const int buildNumber = 1;
  static const String developmentPhase = 'Phase 1 · UI preview';

  static const String appDescription =
      'A minimalist note-taking app for English and Bangla. '
      'Optional note encryption with your own Hill Cipher key is '
      'planned for a future update.';

  /// Delay before the editor writes changes back to the note store while
  /// auto-save is on.
  static const Duration autoSaveDelay = Duration(milliseconds: 600);
}
