import 'package:cipher_note/core/database/database_constants.dart';
import 'package:cipher_note/core/errors/app_exceptions.dart';
import 'package:cipher_note/data/models/key_metadata.dart';
import 'package:cipher_note/data/models/note_model.dart';
import 'package:cipher_note/data/repositories/hive_note_repository.dart';
import 'package:cipher_note/data/repositories/key_metadata_repository.dart';
import 'package:cipher_note/data/repositories/note_repository.dart';
import 'package:cipher_note/data/repositories/secure_key_store.dart';
import 'package:cipher_note/features/encryption/data/key_service.dart';
import 'package:cipher_note/features/encryption/data/note_encryption_service.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/hive_test_utils.dart';

const _title = 'পুরোনো Title';
const _content = 'Version test — আমি ভালো আছি।\nLine 2!';

class _World {
  _World({NoteRepository? notes, KeyMetadataRepository? metadata})
    : notes = notes ?? InMemoryNoteRepository(),
      metadata = metadata ?? InMemoryKeyMetadataRepository();

  final secure = InMemorySecureKeyStore();
  NoteRepository notes;
  KeyMetadataRepository metadata;

  KeyService get keys =>
      KeyService(metadata: metadata, secureStore: secure, notes: notes);
  NoteEncryptionService get encryption => NoteEncryptionService(keys: keys);

  /// Creates a plain note and stores it encrypted with [key].
  Future<Note> encryptNew(String id, KeyMetadata key) async {
    final time = DateTime(2026, 11, 3);
    final plain = Note(
      id: id,
      title: _title,
      content: _content,
      color: 1,
      createdAt: time,
      updatedAt: time,
    );
    await notes.createNote(plain);
    final encrypted = await encryption.encrypt(
      note: plain,
      title: _title,
      content: _content,
      key: key,
    );
    await notes.updateNote(encrypted);
    return encrypted;
  }
}

void main() {
  group('Key versions', () {
    test('a new version increments the number, keeps the id and name, '
        'and stores a separate matrix', () async {
      final world = _World();
      final v1 = await world.keys.createKey('Personal');
      final v2 = await world.keys.createNewVersion(v1.id);
      final v3 = await world.keys.createNewVersion(v1.id);

      expect([v1.version, v2.version, v3.version], [1, 2, 3]);
      expect({v1.id, v2.id, v3.id}, {v1.id});
      expect({v1.name, v2.name, v3.name}, {'Personal'});
      expect(world.secure.entries.keys, {
        'hill_key_${v1.id}_v1',
        'hill_key_${v1.id}_v2',
        'hill_key_${v1.id}_v3',
      });
      final m1 = await world.keys.loadKey(v1.id, 1);
      final m2 = await world.keys.loadKey(v1.id, 2);
      final m3 = await world.keys.loadKey(v1.id, 3);
      expect({m1, m2, m3}, hasLength(3), reason: 'each version is new');
    });

    test(
      'the new version becomes the only active one; old ones remain',
      () async {
        final world = _World();
        final v1 = await world.keys.createKey('Personal');
        final material1 = world.secure.entries['hill_key_${v1.id}_v1'];
        await world.keys.createNewVersion(v1.id);

        final versions = await world.metadata.getVersions(v1.id);
        expect(versions.map((k) => k.version), [2, 1]);
        expect(versions.where((k) => k.isActive).single.version, 2);
        expect(
          world.secure.entries['hill_key_${v1.id}_v1'],
          material1,
          reason: 'version 1 is never overwritten',
        );
      },
    );

    test(
      'notes keep using the exact version they were encrypted with',
      () async {
        final world = _World();
        final v1 = await world.keys.createKey('Personal');
        final oldNote = await world.encryptNew('old', v1);
        final v2 = await world.keys.createNewVersion(v1.id);
        final newNote = await world.encryptNew('new', v2);

        expect(oldNote.keyVersion, 1);
        expect(newNote.keyVersion, 2);
        expect(oldNote.content, isNot(newNote.content));

        final oldText = await world.encryption.decrypt(oldNote);
        final newText = await world.encryption.decrypt(newNote);
        expect(oldText.title, _title);
        expect(oldText.content, _content);
        expect(newText.content, _content);

        // Version 1 is never replaced by version 2's matrix: decrypting the
        // old note with version 2 would not give the original text.
        final wrongVersion = oldNote.toEncrypted(
          cipherTitle: oldNote.title,
          cipherContent: oldNote.content,
          keyId: v1.id,
          keyVersion: 2,
          format: oldNote.cipherFormat!,
          updatedAt: oldNote.updatedAt,
        );
        try {
          final result = await world.encryption.decrypt(wrongVersion);
          expect(result.content, isNot(_content));
        } on AppException catch (error) {
          expect(error, isA<DecryptionFailedException>());
        }
      },
    );

    test('a missing version is reported, never replaced by another', () async {
      final world = _World();
      final v1 = await world.keys.createKey('Personal');
      final note = await world.encryptNew('n', v1);
      await world.keys.createNewVersion(v1.id);
      // Remove version 1 behind the app's back.
      await world.metadata.delete(v1.id, 1);
      await expectLater(
        world.encryption.decrypt(note),
        throwsA(
          isA<KeyUnavailableException>().having(
            (e) => e.message,
            'message',
            contains('Version 1 of the key “Personal”'),
          ),
        ),
      );
    });

    test('a referenced version cannot be deleted; unused ones can', () async {
      final world = _World();
      final v1 = await world.keys.createKey('Personal');
      await world.encryptNew('n', v1);
      final v2 = await world.keys.createNewVersion(v1.id);

      await expectLater(
        world.keys.deleteVersion(v1.id, 1),
        throwsA(
          isA<KeyInUseException>().having((e) => e.noteCount, 'count', 1),
        ),
      );
      expect(await world.metadata.getVersion(v1.id, 1), isNotNull);
      expect(world.secure.entries, contains('hill_key_${v1.id}_v1'));

      // Version 2 is unused: deleting it keeps version 1 (and the key).
      await world.keys.deleteVersion(v2.id, 2);
      final remaining = await world.metadata.getVersions(v1.id);
      expect(remaining.map((k) => k.version), [1]);
      expect(remaining.single.isActive, isTrue, reason: 'active moves back');
      expect(world.secure.entries.keys, ['hill_key_${v1.id}_v1']);
    });

    test('setActive selects one exact version', () async {
      final world = _World();
      final v1 = await world.keys.createKey('Personal');
      await world.keys.createNewVersion(v1.id);
      await world.keys.setActive(v1.id, 1);
      final active = await world.metadata.getActive();
      expect(active!.version, 1);
      expect(
        (await world.metadata.getAll()).where((k) => k.isActive),
        hasLength(1),
      );
      await expectLater(
        world.keys.setActive(v1.id, 9),
        throwsA(isA<KeyUnavailableException>()),
      );
    });

    test('a new version never overwrites existing key material', () async {
      final world = _World();
      final v1 = await world.keys.createKey('Personal');
      // Leftover material for version 2 (e.g. from an interrupted write).
      world.secure.entries['hill_key_${v1.id}_v2'] = '3,5,7,2';
      await expectLater(
        world.keys.createNewVersion(v1.id),
        throwsA(isA<DuplicateRecordException>()),
      );
      expect(world.secure.entries['hill_key_${v1.id}_v2'], '3,5,7,2');
      expect(await world.metadata.getVersion(v1.id, 2), isNull);
    });

    test('creating a version of an unknown key fails', () async {
      await expectLater(
        _World().keys.createNewVersion('missing'),
        throwsA(isA<KeyUnavailableException>()),
      );
    });
  });

  group('Key validation', () {
    test('reports each problem without exposing key values', () async {
      final world = _World();
      final key = await world.keys.createKey('K');
      final entry = 'hill_key_${key.id}_v1';
      final original = world.secure.entries[entry]!;

      expect(await world.keys.validate(key.id, 1), KeyValidationStatus.valid);
      expect(
        await world.keys.validate(key.id, 2),
        KeyValidationStatus.missingMetadata,
      );
      expect(
        await world.keys.validate('nope', 1),
        KeyValidationStatus.missingMetadata,
      );

      world.secure.entries[entry] = '2,4,6,8'; // even determinant
      expect(
        await world.keys.validate(key.id, 1),
        KeyValidationStatus.invalidMatrix,
      );
      world.secure.entries[entry] = '1,2,3'; // three values
      expect(
        await world.keys.validate(key.id, 1),
        KeyValidationStatus.invalidMatrix,
      );
      world.secure.entries[entry] = '1,2,3,999'; // out of range
      expect(
        await world.keys.validate(key.id, 1),
        KeyValidationStatus.invalidMatrix,
      );
      world.secure.entries.remove(entry);
      expect(
        await world.keys.validate(key.id, 1),
        KeyValidationStatus.missingMaterial,
      );
      world.secure.entries[entry] = original;
      world.secure.failReads = true;
      expect(
        await world.keys.validate(key.id, 1),
        KeyValidationStatus.storageFailure,
      );
      world.secure.failReads = false;

      await world.metadata.update(
        KeyMetadata(
          id: key.id,
          name: 'K',
          version: 1,
          algorithm: 'aes_gcm',
          createdAt: key.createdAt,
        ),
      );
      expect(
        await world.keys.validate(key.id, 1),
        KeyValidationStatus.unsupportedAlgorithm,
      );
      for (final status in KeyValidationStatus.values) {
        expect(status.message, isNot(contains(original)));
      }
    });
  });

  group('With Hive', () {
    late TestDatabase db;

    setUp(() async => db = await TestDatabase.create());
    tearDown(() => db.dispose());

    test('versions and their notes survive a restart', () async {
      var service = await db.open();
      final world = _World(
        notes: HiveNoteRepository(service.notes),
        metadata: HiveKeyMetadataRepository(service.keyMetadata),
      );
      final v1 = await world.keys.createKey('Personal');
      await world.encryptNew('old', v1);
      final v2 = await world.keys.createNewVersion(v1.id);
      await world.encryptNew('new', v2);

      service = await db.open();
      world
        ..notes = HiveNoteRepository(service.notes)
        ..metadata = HiveKeyMetadataRepository(service.keyMetadata);
      expect((await world.metadata.getVersions(v1.id)).map((k) => k.version), [
        2,
        1,
      ]);
      for (final id in ['old', 'new']) {
        final text = await world.encryption.decrypt(
          (await world.notes.getNoteById(id))!,
        );
        expect(text.content, _content);
      }
    });

    test('schema v2 key records are moved to versioned names (v3)', () async {
      var service = await db.open();
      final legacy = KeyMetadata(
        id: 'k_legacy',
        name: 'Old key',
        version: 1,
        algorithm: KeyMetadata.hillCipher2x2,
        createdAt: DateTime(2026, 11, 1),
      );
      // Phase 3 stored records under the bare key id.
      await service.keyMetadata.put(legacy.id, legacy);
      await service.appMetadata.put(DatabaseConstants.schemaVersionKey, 2);
      await db.close();

      service = await db.open();
      expect(service.schemaVersion, 3);
      expect(service.keyMetadata.keys, ['k_legacy@v1']);
      final repo = HiveKeyMetadataRepository(service.keyMetadata);
      expect(await repo.getVersion('k_legacy', 1), legacy);
    });
  });
}
