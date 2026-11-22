import 'package:cipher_note/core/database/database_constants.dart';
import 'package:cipher_note/core/database/database_migrator.dart';
import 'package:cipher_note/core/errors/app_exceptions.dart';
import 'package:cipher_note/core/startup/app_initializer.dart';
import 'package:cipher_note/core/theme/app_colors.dart';
import 'package:cipher_note/data/models/key_metadata.dart';
import 'package:cipher_note/data/models/note_model.dart';
import 'package:cipher_note/data/repositories/key_metadata_repository.dart';
import 'package:cipher_note/data/repositories/settings_repository.dart';
import 'package:cipher_note/features/settings/providers/settings_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:material_ui/material_ui.dart';

import '../helpers/hive_test_utils.dart';

/// Reads a record as its raw `field index -> value` map.
class _RawFieldsAdapter extends TypeAdapter<Map<int, Object?>> {
  const _RawFieldsAdapter(this.typeId);

  @override
  final int typeId;

  @override
  Map<int, Object?> read(BinaryReader reader) {
    final count = reader.readByte();
    return {for (var i = 0; i < count; i++) reader.readByte(): reader.read()};
  }

  @override
  void write(BinaryWriter writer, Map<int, Object?> obj) =>
      throw UnimplementedError();
}

KeyMetadata _key(String id, {int version = 1, bool active = true}) =>
    KeyMetadata(
      id: id,
      name: 'Personal key',
      version: version,
      algorithm: KeyMetadata.hillCipher2x2,
      createdAt: DateTime(2026, 11, 1, 10),
      isActive: active,
    );

void main() {
  late TestDatabase db;

  setUp(() async => db = await TestDatabase.create());
  tearDown(() => db.dispose());

  group('Database initialisation and versioning', () {
    test('opens every box and records the schema version', () async {
      final service = await db.open();
      expect(service.notes.isOpen, isTrue);
      expect(service.settings.isOpen, isTrue);
      expect(service.keyMetadata.isOpen, isTrue);
      expect(service.appMetadata.isOpen, isTrue);
      expect(service.schemaVersion, DatabaseConstants.schemaVersion);
      expect(
        service.appMetadata.get(DatabaseConstants.schemaVersionKey),
        DatabaseConstants.schemaVersion,
      );
    });

    test(
      'a database from a newer app version is refused, not changed',
      () async {
        final service = await db.open();
        await service.notes.put(
          'n',
          Note(
            id: 'n',
            title: 'Keep me',
            content: '',
            color: 1,
            createdAt: DateTime(2026),
            updatedAt: DateTime(2026),
          ),
        );
        await service.appMetadata.put(DatabaseConstants.schemaVersionKey, 99);
        await db.close();

        await expectLater(db.open(), throwsA(isA<DatabaseInitException>()));

        // Data is untouched: open the raw box directly.
        final raw = await Hive.openBox<Note>(DatabaseConstants.notesBox);
        expect(raw.get('n')!.title, 'Keep me');
        expect(
          (await Hive.openBox<dynamic>(DatabaseConstants.appMetadataBox))
              .get(DatabaseConstants.schemaVersionKey),
          99,
        );
      },
    );

    test(
      'runs pending migration steps in order and stops on failure',
      () async {
        final ran = <int>[];
        final migrator = DatabaseMigrator(
          steps: {
            1: (_) async => ran.add(1),
            2: (_) async => ran.add(2),
            3: (_) async => throw StateError('boom'),
          },
        );
        Hive.init(db.directory.path);
        final metadata = await Hive.openBox<dynamic>('test_meta');
        final ctx = MigrationContext(
          notes: await Hive.openBox<dynamic>('n1'),
          settings: await Hive.openBox<dynamic>('s1'),
          keyMetadata: await Hive.openBox<dynamic>('k1'),
        );
        Hive.init(db.directory.path);

        expect(
          await migrator.migrate(
            appMetadata: metadata,
            context: ctx,
            targetVersion: 2,
          ),
          2,
        );
        expect(ran, [1, 2]);

        await expectLater(
          migrator.migrate(
            appMetadata: metadata,
            context: ctx,
            targetVersion: 3,
          ),
          throwsA(isA<DatabaseInitException>()),
        );
        expect(metadata.get(DatabaseConstants.schemaVersionKey), 2);
      },
    );

    test('AppInitializer opens the database and survives a restart', () async {
      var deps = await AppInitializer.initialize(directory: db.directory.path);
      await deps.noteRepository.createNote(
        Note(
          id: 'r',
          title: 'Restart',
          content: 'বাংলা',
          color: 1,
          createdAt: DateTime(2026),
          updatedAt: DateTime(2026),
        ),
      );
      await deps.settingsRepository.save(
        const AppSettings(themeMode: ThemeMode.dark),
      );
      await deps.database!.close();

      deps = await AppInitializer.initialize(directory: db.directory.path);
      expect((await deps.noteRepository.getNoteById('r'))!.content, 'বাংলা');
      expect(deps.initialSettings.themeMode, ThemeMode.dark);
      await deps.database!.close();
    });
  });

  group('Settings persistence', () {
    test('first launch uses defaults', () async {
      final service = await db.open();
      expect(
        await HiveSettingsRepository(service.settings).load(),
        AppSettings.defaults,
      );
      expect(
        AppSettings.defaults.defaultNoteColor,
        AppColors.defaultNoteColor.value,
      );
    });

    test('theme, colour, view and other preferences survive restart', () async {
      var service = await db.open();
      final provider = SettingsProvider(
        repository: HiveSettingsRepository(service.settings),
      );
      provider
        ..setThemeMode(ThemeMode.dark)
        ..setDefaultNoteColor(AppColors.green.value)
        ..setViewMode(NoteViewMode.grid)
        ..setSortOrder(NoteSortOrder.title)
        ..setShowContentPreview(false)
        ..setAutoSave(false);
      await provider.pendingSave;
      expect(provider.saveError, isNull);

      service = await db.open();
      final loaded = await HiveSettingsRepository(service.settings).load();
      expect(loaded.themeMode, ThemeMode.dark);
      expect(loaded.defaultNoteColor, AppColors.green.value);
      expect(loaded.viewMode, NoteViewMode.grid);
      expect(loaded.sortOrder, NoteSortOrder.title);
      expect(loaded.showContentPreview, isFalse);
      expect(loaded.autoSave, isFalse);
    });

    test('an unknown stored colour falls back to the default', () async {
      var service = await db.open();
      await HiveSettingsRepository(service.settings)
          .save(const AppSettings(defaultNoteColor: 0x12345678));
      service = await db.open();
      expect(
        (await HiveSettingsRepository(
          service.settings,
        ).load()).defaultNoteColor,
        AppSettings.defaultColorValue,
      );
    });
  });

  group('Key metadata', () {
    late HiveKeyMetadataRepository repo;

    setUp(() async {
      repo = HiveKeyMetadataRepository((await db.open()).keyMetadata);
    });

    test('create, read, update and delete', () async {
      await repo.create(_key('k1'));
      expect(await repo.getById('k1'), _key('k1'));
      expect(await repo.getActive(), _key('k1'));

      await repo.update(_key('k1').copyWith(version: 2, isActive: false));
      final updated = await repo.getById('k1');
      expect(updated!.version, 2);
      expect(updated.isActive, isFalse);
      expect(await repo.getActive(), isNull);

      await repo.delete('k1');
      expect(await repo.getAll(), isEmpty);
    });

    test('ids are unique and versions are kept per record', () async {
      await repo.create(_key('k1', version: 1, active: false));
      await repo.create(_key('k2', version: 4));
      await expectLater(
        repo.create(_key('k1')),
        throwsA(isA<DuplicateRecordException>()),
      );
      await expectLater(
        repo.update(_key('nope')),
        throwsA(isA<RecordNotFoundException>()),
      );
      final versions = {for (final k in await repo.getAll()) k.id: k.version};
      expect(versions, {'k1': 1, 'k2': 4});
    });

    test('metadata survives a restart', () async {
      await repo.create(_key('k1'));
      repo = HiveKeyMetadataRepository((await db.open()).keyMetadata);
      expect(await repo.getById('k1'), _key('k1'));
    });

    test('validates ids, versions and display names', () {
      expect(() => _key(' '), throwsArgumentError);
      expect(() => _key('k', version: 0), throwsArgumentError);
      expect(
        () => KeyMetadata(
          id: 'k',
          name: '   ',
          version: 1,
          algorithm: KeyMetadata.hillCipher2x2,
          createdAt: DateTime(2026),
        ),
        throwsArgumentError,
      );
      expect(
        () => KeyMetadata(
          id: 'k',
          name: 'x' * (KeyMetadata.maxNameLength + 1),
          version: 1,
          algorithm: KeyMetadata.hillCipher2x2,
          createdAt: DateTime(2026),
        ),
        throwsArgumentError,
      );
    });

    test(
      'only descriptive fields are written to Hive (no key material)',
      () async {
        await repo.create(_key('k1'));
        await db.close();
        Hive.resetAdapters();
        Hive.registerAdapter(
          _RawFieldsAdapter(DatabaseConstants.keyMetadataTypeId),
        );
        final raw = await Hive.openBox<dynamic>(
          DatabaseConstants.keyMetadataBox,
        );
        final fields = raw.get('k1') as Map<int, Object?>;
        await raw.close();
        Hive.resetAdapters();

        // 0 id, 1 name, 2 version, 3 algorithm, 4 createdAt, 5 isActive.
        expect(fields.keys, unorderedEquals([0, 1, 2, 3, 4, 5]));
        expect(fields[0], 'k1');
        expect(fields[1], 'Personal key');
        expect(fields[3], KeyMetadata.hillCipher2x2);
        expect(
          fields.values.whereType<List<dynamic>>(),
          isEmpty,
          reason: 'no matrix or byte list is stored',
        );
      },
    );

    test('in-memory and Hive repositories behave the same', () async {
      final memory = InMemoryKeyMetadataRepository();
      for (final r in <KeyMetadataRepository>[memory, repo]) {
        await r.create(_key('a', active: false));
        await r.create(_key('b'));
        expect((await r.getActive())!.id, 'b');
        expect(await r.getAll(), hasLength(2));
      }
    });
  });
}
