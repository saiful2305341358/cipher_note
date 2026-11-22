import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:path_provider/path_provider.dart';

import '../../data/models/app_settings.dart';
import '../../data/models/key_metadata.dart';
import '../../data/models/note_model.dart';
import '../errors/app_exceptions.dart';
import 'database_constants.dart';
import 'database_migrator.dart';
import 'hive_adapters.dart';

/// Owns the Hive database: initialises it, registers adapters, opens every
/// box, runs migrations and closes it again.
///
/// An instance only exists once all boxes are open, so the rest of the app
/// can never reach an unopened box. Repositories receive the typed boxes
/// from here; widgets never touch Hive.
class HiveService {
  HiveService._({
    required this.hive,
    required this.directory,
    required this.notes,
    required this.settings,
    required this.keyMetadata,
    required this.appMetadata,
    required this.schemaVersion,
  });

  final HiveInterface hive;
  final String directory;
  final Box<Note> notes;
  final Box<AppSettings> settings;
  final Box<KeyMetadata> keyMetadata;
  final Box<dynamic> appMetadata;
  final int schemaVersion;

  bool _closed = false;
  bool get isOpen => !_closed;

  /// Opens the database.
  ///
  /// [directory] defaults to a folder inside the app's private support
  /// directory. Tests pass a temporary directory instead.
  ///
  /// Throws [DatabaseInitException] with a user-facing message on failure.
  /// Existing data is never deleted to recover from an error.
  static Future<HiveService> open({
    String? directory,
    HiveInterface? hive,
    DatabaseMigrator? migrator,
  }) async {
    final db = hive ?? Hive;
    final String path;
    try {
      if (kIsWeb && directory == null) {
        // Browsers store boxes in IndexedDB; no directory is needed.
        path = '';
      } else {
        path = directory ?? await _defaultDirectory();
        await Directory(path).create(recursive: true);
      }
    } catch (error) {
      throw DatabaseInitException(
        'The app could not find a place to store your notes.',
        cause: error,
      );
    }

    db.init(path.isEmpty ? null : path);
    _registerAdapters(db);

    final opened = <Box<dynamic>>[];
    Future<Box<T>> openBox<T>(String name) async {
      final box = await db.openBox<T>(name);
      opened.add(box);
      return box;
    }

    try {
      // Metadata and migrations first: they can read the other boxes
      // untyped, before typed access starts.
      final appMetadata = await openBox<dynamic>(
        DatabaseConstants.appMetadataBox,
      );
      final notes = await openBox<Note>(DatabaseConstants.notesBox);
      final settings = await openBox<AppSettings>(
        DatabaseConstants.settingsBox,
      );
      final keyMetadata = await openBox<KeyMetadata>(
        DatabaseConstants.keyMetadataBox,
      );

      final version = await (migrator ?? DatabaseMigrator()).migrate(
        appMetadata: appMetadata,
        context: MigrationContext(
          notes: notes,
          settings: settings,
          keyMetadata: keyMetadata,
        ),
      );

      return HiveService._(
        hive: db,
        directory: path,
        notes: notes,
        settings: settings,
        keyMetadata: keyMetadata,
        appMetadata: appMetadata,
        schemaVersion: version,
      );
    } catch (error) {
      for (final box in opened) {
        try {
          await box.close();
        } catch (_) {
          // Already failing; keep the original error.
        }
      }
      if (error is DatabaseInitException) rethrow;
      throw DatabaseInitException(
        'The app could not open your saved notes.',
        cause: error,
      );
    }
  }

  static Future<String> _defaultDirectory() async {
    final base = await getApplicationSupportDirectory();
    return '${base.path}${Platform.pathSeparator}'
        '${DatabaseConstants.directoryName}';
  }

  static void _registerAdapters(HiveInterface db) {
    if (!db.isAdapterRegistered(DatabaseConstants.noteTypeId)) {
      db.registerAdapter(NoteAdapter());
    }
    if (!db.isAdapterRegistered(DatabaseConstants.keyMetadataTypeId)) {
      db.registerAdapter(KeyMetadataAdapter());
    }
    if (!db.isAdapterRegistered(DatabaseConstants.appSettingsTypeId)) {
      db.registerAdapter(AppSettingsAdapter());
    }
  }

  /// Writes pending data and closes every box.
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    for (final box in [notes, settings, keyMetadata, appMetadata]) {
      if (box.isOpen) {
        await box.flush();
        await box.close();
      }
    }
  }
}
