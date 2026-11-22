import '../../data/models/app_settings.dart';
import '../../data/repositories/hive_note_repository.dart';
import '../../data/repositories/key_metadata_repository.dart';
import '../../data/repositories/note_repository.dart';
import '../../data/repositories/settings_repository.dart';
import '../database/hive_service.dart';
import '../errors/app_exceptions.dart';
import '../errors/error_reporter.dart';

/// Everything the app needs once the database is open.
class AppDependencies {
  const AppDependencies({
    this.database,
    required this.noteRepository,
    required this.keyRepository,
    required this.settingsRepository,
    required this.initialSettings,
  });

  /// The open database; `null` only when tests supply in-memory stores.
  final HiveService? database;
  final NoteRepository noteRepository;
  final KeyMetadataRepository keyRepository;
  final SettingsRepository settingsRepository;
  final AppSettings initialSettings;
}

/// Opens the database and loads settings before the first frame, so the
/// saved theme is used from the start.
class AppInitializer {
  AppInitializer._();

  static const Duration timeout = Duration(seconds: 20);

  /// Throws [DatabaseInitException] if the database cannot be opened.
  static Future<AppDependencies> initialize({String? directory}) async {
    final HiveService database;
    try {
      database = await HiveService.open(directory: directory).timeout(timeout);
    } on DatabaseInitException catch (error, stack) {
      ErrorReporter.report('AppInitializer', error.cause ?? error, stack);
      rethrow;
    } catch (error, stack) {
      ErrorReporter.report('AppInitializer', error, stack);
      throw DatabaseInitException(
        'The app could not open your saved notes.',
        cause: error,
      );
    }

    final settingsRepository = HiveSettingsRepository(database.settings);
    AppSettings settings;
    try {
      settings = await settingsRepository.load();
    } on AppException {
      // Notes are still usable; fall back to default preferences.
      settings = AppSettings.defaults;
    }

    return AppDependencies(
      database: database,
      noteRepository: HiveNoteRepository(database.notes),
      keyRepository: HiveKeyMetadataRepository(database.keyMetadata),
      settingsRepository: settingsRepository,
      initialSettings: settings,
    );
  }
}
