/// Names, type ids and versions used by the local Hive database.
///
/// Never change an existing box name, type id or field index: stored data
/// depends on them. Add new ones instead.
class DatabaseConstants {
  DatabaseConstants._();

  /// Sub-directory of the app's private support directory.
  static const String directoryName = 'cipher_note_db';

  // Boxes.
  static const String notesBox = 'notes';
  static const String settingsBox = 'settings';
  static const String keyMetadataBox = 'key_metadata';
  static const String appMetadataBox = 'app_metadata';

  // Hive type ids (0–223 are available to apps).
  static const int noteTypeId = 1;
  static const int keyMetadataTypeId = 2;
  static const int appSettingsTypeId = 3;

  /// Key of the single record in the settings box.
  static const String settingsKey = 'app_settings';

  // Keys in the app metadata box.
  static const String schemaVersionKey = 'schema_version';
  static const String createdAtKey = 'created_at';
  static const String lastMigratedAtKey = 'last_migrated_at';

  /// Current database schema version. Increase it and add a migration step
  /// in `DatabaseMigrator` whenever stored data needs converting.
  static const int schemaVersion = 3;
}
