import 'dart:io';

import 'package:cipher_note/core/database/database_constants.dart';
import 'package:cipher_note/core/database/hive_service.dart';
import 'package:cipher_note/core/errors/app_exceptions.dart';
import 'package:cipher_note/data/models/cipher_format.dart';
import 'package:cipher_note/data/models/key_metadata.dart';
import 'package:cipher_note/data/models/note_model.dart';
import 'package:cipher_note/data/repositories/hive_note_repository.dart';
import 'package:cipher_note/data/repositories/key_metadata_repository.dart';
import 'package:cipher_note/data/repositories/note_repository.dart';
import 'package:cipher_note/data/repositories/secure_key_store.dart';
import 'package:cipher_note/features/encryption/data/key_service.dart';
import 'package:cipher_note/features/encryption/data/note_encryption_service.dart';
import 'package:cipher_note/features/encryption/domain/hill_key_matrix.dart';
import 'package:cipher_note/features/notes/providers/notes_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';

import '../helpers/hive_test_utils.dart';

const _title = 'গোপন Meeting — notes';
const _content =
    'Hello, how are you?\nআমি ভালো আছি। Thank you!\n\n'
    'URL: https://example.com/a?b=1 · email: me@example.com 🎉';

/// Metadata repository whose writes can fail.
class _FailingMetadataRepository extends InMemoryKeyMetadataRepository {
  bool failCreate = false;

  @override
  Future<void> create(KeyMetadata metadata) async {
    if (failCreate) throw const StorageException('Key information failed.');
    return super.create(metadata);
  }
}

/// Holds the stores that survive an "app restart" in tests.
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
}

Note _plain(String id, {String title = _title, String content = _content}) {
  final time = DateTime(2026, 11, 3, 16, 49);
  return Note(
    id: id,
    title: title,
    content: content,
    color: 0xFFDCEBFA,
    createdAt: time,
    updatedAt: time,
  );
}

void main() {
  group('KeyService', () {
    test(
      'stores key values only in secure storage, metadata separately',
      () async {
        final world = _World();
        final key = await world.keys.createKey('  Personal  ');
        expect(key.name, 'Personal');
        expect(key.version, 1);
        expect(key.algorithm, KeyMetadata.hillCipher2x2);
        expect(key.isActive, isTrue);
        expect(key.id, startsWith('k_'));

        final entryName = 'hill_key_${key.id}_v1';
        expect(world.secure.entries.keys, [entryName]);
        final values = world.secure.entries[entryName]!
            .split(',')
            .map(int.parse);
        expect(HillKeyMatrix.fromList(values.toList()), isA<HillKeyMatrix>());
        expect(await world.metadata.getVersion(key.id, 1), key);
      },
    );

    test('rejects empty or too-long names before creating anything', () async {
      final world = _World();
      for (final name in ['', '   ', 'x' * 41]) {
        await expectLater(
          world.keys.createKey(name),
          throwsA(isA<InvalidKeyException>()),
        );
      }
      expect(world.secure.entries, isEmpty);
      expect(await world.metadata.getAll(), isEmpty);
    });

    test('a failed secure-storage write saves no metadata', () async {
      final world = _World();
      world.secure.failWrites = true;
      await expectLater(
        world.keys.createKey('K'),
        throwsA(isA<SecureStorageException>()),
      );
      expect(await world.metadata.getAll(), isEmpty);
    });

    test('a failed metadata write removes the stored key again', () async {
      final metadata = _FailingMetadataRepository()..failCreate = true;
      final world = _World(metadata: metadata);
      await expectLater(
        world.keys.createKey('K'),
        throwsA(isA<StorageException>()),
      );
      expect(world.secure.entries, isEmpty);
    });

    test('loads the exact key, and reports missing or broken keys', () async {
      final world = _World();
      final key = await world.keys.createKey('K');
      final matrix = await world.keys.loadKey(key.id, 1);
      expect(
        matrix.toList(),
        world.secure.entries.values.single.split(',').map(int.parse),
      );

      await expectLater(
        world.keys.loadKey('nope', 1),
        throwsA(isA<KeyUnavailableException>()),
      );
      await expectLater(
        world.keys.loadKey(key.id, 2),
        throwsA(isA<KeyUnavailableException>()),
      );

      world.secure.failReads = true;
      await expectLater(
        world.keys.loadKey(key.id, 1),
        throwsA(isA<SecureStorageException>()),
      );
      world.secure.failReads = false;

      world.secure.entries['hill_key_${key.id}_v1'] = '2,4,6,8'; // det even
      await expectLater(
        world.keys.loadKey(key.id, 1),
        throwsA(isA<InvalidKeyException>()),
      );
      world.secure.entries['hill_key_${key.id}_v1'] = 'garbage';
      await expectLater(
        world.keys.loadKey(key.id, 1),
        throwsA(isA<InvalidKeyException>()),
      );
      world.secure.entries.clear();
      await expectLater(
        world.keys.loadKey(key.id, 1),
        throwsA(isA<KeyUnavailableException>()),
      );
    });

    test('a key used by encrypted notes cannot be deleted', () async {
      final world = _World();
      final key = await world.keys.createKey('Used');
      await world.notes.createNote(_plain('n'));
      final encrypted = await world.encryption.encrypt(
        note: _plain('n'),
        title: _title,
        content: _content,
        key: key,
      );
      await world.notes.updateNote(encrypted);

      await expectLater(
        world.keys.deleteVersion(key.id, 1),
        throwsA(
          isA<KeyInUseException>().having((e) => e.noteCount, 'count', 1),
        ),
      );
      expect(await world.metadata.getVersion(key.id, 1), isNotNull);
      expect(world.secure.entries, isNotEmpty);

      // Once the note is plain again, the key can go.
      await world.notes.updateNote(
        encrypted.toPlain(title: 'x', content: 'y', updatedAt: DateTime(2027)),
      );
      await world.keys.deleteVersion(key.id, 1);
      expect(await world.metadata.getAll(), isEmpty);
      expect(world.secure.entries, isEmpty);
    });

    test('only one key is active at a time', () async {
      final world = _World();
      final a = await world.keys.createKey('A');
      final b = await world.keys.createKey('B');
      var all = await world.keys.listKeys();
      expect(all.first.id, b.id);
      expect(all.where((k) => k.isActive).single.id, b.id);
      await world.keys.setActive(a.id, 1);
      all = await world.keys.listKeys();
      expect(all.where((k) => k.isActive).single.id, a.id);
    });
  });

  group('NoteEncryptionService', () {
    late _World world;
    late KeyMetadata key;

    setUp(() async {
      world = _World();
      key = await world.keys.createKey('Personal');
    });

    test('encrypts title and content and records key and format', () async {
      final plain = _plain('n');
      final encrypted = await world.encryption.encrypt(
        note: plain,
        title: plain.title,
        content: plain.content,
        key: key,
      );
      expect(encrypted.id, 'n');
      expect(encrypted.isEncrypted, isTrue);
      expect(encrypted.keyId, key.id);
      expect(encrypted.keyVersion, 1);
      expect(encrypted.cipherFormat, CipherFormat.hillV1);
      expect(encrypted.color, plain.color);
      expect(encrypted.createdAt, plain.createdAt);
      expect(encrypted.title, isNot(contains('Meeting')));
      expect(encrypted.title, isNot(contains('গোপন')));
      expect(encrypted.content, isNot(contains('Hello')));
      expect(encrypted.displayTitle, Note.encryptedLabel);
      expect(encrypted.toString(), isNot(contains('Meeting')));

      final decrypted = await world.encryption.decrypt(encrypted);
      expect(decrypted.title, _title);
      expect(decrypted.content, _content);
      expect(decrypted.toString(), isNot(contains('Meeting')));
    });

    test(
      'decrypt refuses notes with missing or unknown format details',
      () async {
        final encrypted = await world.encryption.encrypt(
          note: _plain('n'),
          title: 'a',
          content: 'b',
          key: key,
        );
        final noFormat = Note(
          id: 'n',
          title: encrypted.title,
          content: encrypted.content,
          color: 1,
          createdAt: DateTime(2026),
          updatedAt: DateTime(2026),
          isEncrypted: true,
          keyId: key.id,
          keyVersion: 1,
        );
        await expectLater(
          world.encryption.decrypt(noFormat),
          throwsA(isA<CiphertextFormatException>()),
        );
        final future = encrypted.toEncrypted(
          cipherTitle: encrypted.title,
          cipherContent: encrypted.content,
          keyId: key.id,
          keyVersion: 1,
          format: const CipherFormat(
            algorithm: 'aes_gcm',
            version: 1,
            encoding: 'base64',
            blockSize: 16,
            modulus: 0,
          ),
          updatedAt: DateTime(2026),
        );
        await expectLater(
          world.encryption.decrypt(future),
          throwsA(isA<CiphertextFormatException>()),
        );
        await expectLater(
          world.encryption.decrypt(_plain('p')),
          throwsA(isA<CiphertextFormatException>()),
        );
      },
    );

    test('a missing key makes encryption fail without a result', () async {
      world.secure.entries.clear();
      await expectLater(
        world.encryption.encrypt(
          note: _plain('n'),
          title: 'a',
          content: 'b',
          key: key,
        ),
        throwsA(isA<KeyUnavailableException>()),
      );
    });
  });

  group('NotesProvider with encrypted notes', () {
    test('failed encryption leaves the stored note unchanged', () async {
      final world = _World(notes: InMemoryNoteRepository([_plain('n')]));
      final provider = NotesProvider(world.notes);
      await provider.load();
      final key = await world.keys.createKey('K');
      world.secure.entries.clear(); // key material lost

      await expectLater(
        world.encryption.encrypt(
          note: provider.getById('n')!,
          title: _title,
          content: _content,
          key: key,
        ),
        throwsA(isA<KeyUnavailableException>()),
      );
      expect(provider.getById('n'), _plain('n'));
      expect(await world.notes.getNoteById('n'), _plain('n'));
    });

    test('failed decryption does not change stored ciphertext', () async {
      final world = _World(notes: InMemoryNoteRepository([_plain('n')]));
      final provider = NotesProvider(world.notes);
      await provider.load();
      final key = await world.keys.createKey('K');
      final encrypted = await world.encryption.encrypt(
        note: provider.getById('n')!,
        title: _title,
        content: _content,
        key: key,
      );
      await provider.replaceNote(encrypted);
      world.secure.entries.clear();

      await expectLater(
        world.encryption.decrypt(provider.getById('n')!),
        throwsA(isA<KeyUnavailableException>()),
      );
      expect(await world.notes.getNoteById('n'), encrypted);
    });

    test('plain text cannot be written into an encrypted note', () async {
      final world = _World(notes: InMemoryNoteRepository([_plain('n')]));
      final provider = NotesProvider(world.notes);
      await provider.load();
      final key = await world.keys.createKey('K');
      final encrypted = await world.encryption.encrypt(
        note: provider.getById('n')!,
        title: 'a',
        content: 'b',
        key: key,
      );
      await provider.replaceNote(encrypted);
      await expectLater(
        provider.updateNote('n', content: 'leak'),
        throwsA(isA<EncryptedNoteLockedException>()),
      );
      // Colour is not secret and can still change.
      await provider.changeColor('n', 0xFFFCE1E8);
      expect(provider.getById('n')!.title, encrypted.title);
      expect(provider.getById('n')!.color, 0xFFFCE1E8);
    });

    test('search never matches encrypted notes', () async {
      final world = _World(
        notes: InMemoryNoteRepository([
          _plain('secret', title: 'Secret plan', content: 'Meeting'),
          _plain('open', title: 'Open plan', content: 'Meeting'),
        ]),
      );
      final provider = NotesProvider(world.notes);
      await provider.load();
      final key = await world.keys.createKey('K');
      await provider.replaceNote(
        await world.encryption.encrypt(
          note: provider.getById('secret')!,
          title: 'Secret plan',
          content: 'Meeting',
          key: key,
        ),
      );
      expect(provider.search('plan').map((n) => n.id), ['open']);
      expect(provider.search('Meeting').map((n) => n.id), ['open']);
      expect(provider.search('Encrypted'), isEmpty);
      final hex = provider.getById('secret')!.content.substring(0, 4);
      expect(provider.search(hex), isEmpty, reason: 'ciphertext not searched');
      expect(provider.encryptedCount, 1);
      expect(await world.notes.searchNotes('plan'), hasLength(1));
    });
  });

  group('With Hive storage', () {
    late TestDatabase db;
    late HiveService service;
    late _World world;

    Future<void> restart() async {
      service = await db.open();
      world.notes = HiveNoteRepository(service.notes);
      world.metadata = HiveKeyMetadataRepository(service.keyMetadata);
    }

    setUp(() async {
      db = await TestDatabase.create();
      world = _World();
      await restart();
    });

    tearDown(() => db.dispose());

    test('encrypt → restart → decrypt → edit → re-encrypt → restart → '
        'decrypt gives the latest text', () async {
      final key = await world.keys.createKey('Personal');
      await world.notes.createNote(_plain('n'));

      // Encrypt and store.
      var stored = (await world.notes.getNoteById('n'))!;
      await world.notes.updateNote(
        await world.encryption.encrypt(
          note: stored,
          title: stored.title,
          content: stored.content,
          key: key,
        ),
      );
      await restart();

      // Stored note is encrypted, with key reference and format.
      stored = (await world.notes.getNoteById('n'))!;
      expect(stored.isEncrypted, isTrue);
      expect(stored.keyId, key.id);
      expect(stored.keyVersion, 1);
      expect(stored.cipherFormat, CipherFormat.hillV1);
      expect(stored.title, isNot(contains('Meeting')));

      // Decrypt, edit, encrypt again.
      final decrypted = await world.encryption.decrypt(stored);
      expect(decrypted.title, _title);
      expect(decrypted.content, _content);
      const edited = '$_content\nনতুন লাইন — new line!';
      await world.notes.updateNote(
        await world.encryption.encrypt(
          note: stored,
          title: '${decrypted.title} (v2)',
          content: edited,
          key: key,
        ),
      );
      await restart();

      final again = await world.encryption.decrypt(
        (await world.notes.getNoteById('n'))!,
      );
      expect(again.title, '$_title (v2)');
      expect(again.content, edited);
    });

    test('key metadata in Hive never contains key values', () async {
      final key = await world.keys.createKey('Personal');
      final material = world.secure.entries.values.single;
      final stored = await world.metadata.getVersion(key.id, 1);
      expect(stored!.name, 'Personal');
      // Raw on-disk bytes of the key metadata box do not contain the
      // material string.
      await db.close();
      final file = db.directory.listSync().whereType<File>().firstWhere(
        (f) => f.path.endsWith('${DatabaseConstants.keyMetadataBox}.hive'),
      );
      final bytes = await file.readAsBytes();
      expect(String.fromCharCodes(bytes), isNot(contains(material)));
    });

    test('a schema v1 database upgrades to the current version and keeps '
        'plain notes', () async {
      // Build a v1 database the way Phase 2 wrote it.
      await world.notes.createNote(
        _plain('old', title: 'Old', content: 'Body'),
      );
      await service.appMetadata.put(DatabaseConstants.schemaVersionKey, 1);
      await db.close();

      await restart();
      expect(service.schemaVersion, DatabaseConstants.schemaVersion);
      expect(
        service.appMetadata.get(DatabaseConstants.schemaVersionKey),
        DatabaseConstants.schemaVersion,
      );
      final note = (await world.notes.getNoteById('old'))!;
      expect(note.title, 'Old');
      expect(note.isEncrypted, isFalse);
      expect(note.keyId, isNull);
      expect(note.cipherFormat, isNull);
    });

    test('cipher format survives storage exactly', () async {
      final key = await world.keys.createKey('K');
      await world.notes.createNote(_plain('n'));
      final encrypted = await world.encryption.encrypt(
        note: _plain('n'),
        title: 'a',
        content: 'b',
        key: key,
      );
      await world.notes.updateNote(encrypted);
      await restart();
      expect(await world.notes.getNoteById('n'), encrypted);
      expect(Hive.isBoxOpen(DatabaseConstants.notesBox), isTrue);
    });
  });
}
