import 'package:hive_ce/hive_ce.dart';

import '../../data/models/key_metadata.dart';
import '../../data/models/note_model.dart';
import '../../data/repositories/key_metadata_repository.dart';
import '../errors/app_exceptions.dart';
import 'database_constants.dart';

/// One migration step: converts stored data from `version - 1` to `version`.
typedef MigrationStep = Future<void> Function(MigrationContext context);

/// The boxes a migration step may read and rewrite.
class MigrationContext {
  const MigrationContext({
    required this.notes,
    required this.settings,
    required this.keyMetadata,
  });

  final Box<dynamic> notes;
  final Box<dynamic> settings;
  final Box<dynamic> keyMetadata;
}

/// Brings stored data up to [DatabaseConstants.schemaVersion].
///
/// Rules:
/// * Steps only ever convert data. They never delete user data to get past
///   an error; a failing step stops startup with [DatabaseInitException]
///   and leaves the stored version unchanged, so the step runs again next
///   time.
/// * A database written by a newer app version is not touched.
class DatabaseMigrator {
  DatabaseMigrator({Map<int, MigrationStep>? steps})
    : steps = steps ?? defaultSteps;

  /// Step `n` upgrades from version `n - 1` to `n`.
  ///
  /// * v1: first persistent schema. Phase 1 kept notes in memory only, so
  ///   there is no earlier on-disk data to convert.
  /// * v2: notes gain field 9 (`cipherFormat`). Existing notes are plain;
  ///   the adapter reads the missing field as `null`, so nothing is
  ///   rewritten. The step only checks that no v1 note claims to be
  ///   encrypted (encryption did not exist in v1) and fails rather than
  ///   guess if one does.
  /// * v3: key metadata becomes versioned. Records move from being stored
  ///   under the key id to `<id>@v<version>`, so several versions of one key
  ///   can coexist. Each record is written under its new name before the
  ///   old entry is removed, so an interruption never loses a record.
  static final Map<int, MigrationStep> defaultSteps = {
    1: (_) async {},
    2: _checkNoEncryptedNotes,
    3: _versionKeyMetadataRecords,
  };

  static Future<void> _versionKeyMetadataRecords(
    MigrationContext context,
  ) async {
    final box = context.keyMetadata;
    for (final oldKey in box.keys.toList()) {
      final value = box.get(oldKey);
      if (value is! KeyMetadata) continue;
      final newKey = KeyMetadataRepository.recordKey(value.id, value.version);
      if (oldKey == newKey) continue;
      if (!box.containsKey(newKey)) await box.put(newKey, value);
      await box.delete(oldKey);
    }
  }

  static Future<void> _checkNoEncryptedNotes(MigrationContext context) async {
    for (final value in context.notes.values) {
      if (value is Note && value.isEncrypted) {
        throw StateError('A v1 note is marked encrypted');
      }
    }
  }

  final Map<int, MigrationStep> steps;

  /// Returns the schema version the database is at after migrating.
  Future<int> migrate({
    required Box<dynamic> appMetadata,
    required MigrationContext context,
    int targetVersion = DatabaseConstants.schemaVersion,
  }) async {
    final stored = appMetadata.get(DatabaseConstants.schemaVersionKey);
    var version = stored is int ? stored : 0;

    if (version > targetVersion) {
      throw DatabaseInitException(
        'Your notes were saved by a newer version of the app. '
        'Please update the app to open them.',
      );
    }
    if (stored == null) {
      await appMetadata.put(
        DatabaseConstants.createdAtKey,
        DateTime.now().toUtc().microsecondsSinceEpoch,
      );
    }

    while (version < targetVersion) {
      final next = version + 1;
      final step = steps[next];
      if (step == null) {
        throw DatabaseInitException(
          'The app could not update its database.',
          cause: StateError('Missing migration step $next'),
        );
      }
      try {
        await step(context);
      } catch (error) {
        throw DatabaseInitException(
          'The app could not update its database.',
          cause: error,
        );
      }
      version = next;
      await appMetadata.put(DatabaseConstants.schemaVersionKey, version);
      await appMetadata.put(
        DatabaseConstants.lastMigratedAtKey,
        DateTime.now().toUtc().microsecondsSinceEpoch,
      );
    }
    return version;
  }
}
