import 'package:hive_ce/hive_ce.dart';

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
  /// Version 1 is the first persistent schema. Phase 1 kept notes in memory
  /// only, so there is no earlier on-disk data to convert; the step simply
  /// records the version.
  static final Map<int, MigrationStep> defaultSteps = {1: (_) async {}};

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
