import 'package:cipher_note/core/database/database_constants.dart';
import 'package:cipher_note/core/database/hive_service.dart';
import 'package:cipher_note/core/errors/app_exceptions.dart';
import 'package:cipher_note/data/models/note_model.dart';
import 'package:cipher_note/data/repositories/hive_note_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';

import '../helpers/hive_test_utils.dart';

const _bangla = 'আমি Flutter দিয়ে একটি Note Taking Application তৈরি করছি।';

Note _note(
  String id, {
  String title = 'Title',
  String content = 'Content',
  DateTime? created,
  DateTime? updated,
  int color = 0xFFFFF3BF,
}) {
  final c = created ?? DateTime(2026, 11, 3, 16, 49, 12, 345, 678);
  return Note(
    id: id,
    title: title,
    content: content,
    color: color,
    createdAt: c,
    updatedAt: updated ?? c,
  );
}

/// Writes notes the way an older app version without key fields would.
class _LegacyNoteAdapter extends TypeAdapter<Note> {
  @override
  int get typeId => DatabaseConstants.noteTypeId;

  @override
  Note read(BinaryReader reader) => throw UnimplementedError();

  @override
  void write(BinaryWriter writer, Note obj) {
    writer
      ..writeByte(4)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.title)
      ..writeByte(2)
      ..write(obj.content)
      ..writeByte(6)
      ..write(obj.updatedAt.toUtc().microsecondsSinceEpoch);
  }
}

void main() {
  late TestDatabase db;
  late HiveService service;
  late HiveNoteRepository repo;

  Future<void> restart() async {
    service = await db.open();
    repo = HiveNoteRepository(service.notes);
  }

  setUp(() async {
    db = await TestDatabase.create();
    await restart();
  });

  tearDown(() => db.dispose());

  group('HiveNoteRepository CRUD', () {
    test('creates a note and retrieves it by id and in the list', () async {
      final note = _note('a');
      await repo.createNote(note);
      expect(await repo.getNoteById('a'), note);
      expect(await repo.getAllNotes(), [note]);
      expect(await repo.getNoteById('missing'), isNull);
    });

    test('rejects a duplicate id instead of creating a second record', () {
      return expectLater(() async {
        await repo.createNote(_note('a'));
        await repo.createNote(_note('a', title: 'Other'));
      }(), throwsA(isA<DuplicateRecordException>()));
    });

    test('updates in place, keeping id and createdAt', () async {
      final original = _note('a');
      await repo.createNote(original);
      final edited = original.copyWith(
        title: 'New title',
        content: 'New content',
        updatedAt: original.updatedAt.add(const Duration(minutes: 5)),
      );
      await repo.updateNote(edited);

      final all = await repo.getAllNotes();
      expect(all, hasLength(1));
      expect(all.single.id, 'a');
      expect(all.single.title, 'New title');
      expect(all.single.createdAt, original.createdAt);
      expect(all.single.updatedAt, edited.updatedAt);
    });

    test('updating a missing note fails and does not create it', () async {
      await expectLater(
        repo.updateNote(_note('ghost')),
        throwsA(isA<RecordNotFoundException>()),
      );
      expect(await repo.getAllNotes(), isEmpty);
    });

    test('rejects an empty id', () {
      expect(repo.createNote(_note(' ')), throwsA(isA<StorageException>()));
    });

    test('deletes one note and deletes all notes', () async {
      await repo.createNote(_note('a'));
      await repo.createNote(_note('b'));
      await repo.createNote(_note('c'));
      await repo.deleteNote('a');
      await repo.deleteNote('missing');
      expect(
        (await repo.getAllNotes()).map((n) => n.id),
        unorderedEquals(['b', 'c']),
      );
      await repo.deleteAllNotes();
      expect(await repo.getAllNotes(), isEmpty);
    });

    test('stores future key reference fields', () async {
      final note = Note(
        id: 'k',
        title: 't',
        content: 'c',
        color: 1,
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
        keyId: 'key_1',
        keyVersion: 3,
      );
      await repo.createNote(note);
      await restart();
      final stored = await repo.getNoteById('k');
      expect(stored!.keyId, 'key_1');
      expect(stored.keyVersion, 3);
      expect(stored.isEncrypted, isFalse);
    });
  });

  group('Search', () {
    setUp(() async {
      await repo.createNote(
        _note('en', title: 'Shopping', content: 'Milk and EGGS'),
      );
      await repo.createNote(_note('bn', title: 'সমস্যা', content: _bangla));
      await repo.createNote(
        _note('mix', title: 'Flutter নোট', content: 'plain'),
      );
    });

    test('searches titles and content, English case-insensitively', () async {
      expect((await repo.searchNotes('shop')).single.id, 'en');
      expect((await repo.searchNotes('eggs')).single.id, 'en');
    });

    test('searches Bangla and mixed-language text', () async {
      expect((await repo.searchNotes('সমস্যা')).single.id, 'bn');
      expect((await repo.searchNotes('তৈরি')).single.id, 'bn');
      expect((await repo.searchNotes('নোট')).single.id, 'mix');
      expect((await repo.searchNotes('flutter')).map((n) => n.id), [
        'mix',
        'bn',
      ], reason: 'title matches come before content matches');
    });

    test('blank or unmatched queries return nothing', () async {
      expect(await repo.searchNotes(''), isEmpty);
      expect(await repo.searchNotes('   '), isEmpty);
      expect(await repo.searchNotes('zzz'), isEmpty);
    });
  });

  group('Text and timestamps survive a restart', () {
    test('preserves Unicode, line breaks, punctuation and emoji', () async {
      const title = 'মিশ্র Title — “quotes” & symbols!? 🎉';
      const content =
          'Line 1: $_bangla\n'
          'Line 2: যুক্তাক্ষর ক্ষ ত্র জ্ঞ, কার ও ফলা: কি কী কু কূ ক্য ক্র\n'
          '\n'
          '\tTabbed; punctuation: ,.;:!?()[]{}"\'—…।\n'
          'Emoji: 😀 👨‍👩‍👧‍👦 🇧🇩 ❤️\n'
          'Trailing spaces   ';
      await repo.createNote(_note('u', title: title, content: content));
      await restart();
      final stored = await repo.getNoteById('u');
      expect(stored!.title, title);
      expect(stored.content, content);
    });

    test('preserves timestamps to the microsecond', () async {
      final created = DateTime(2026, 1, 2, 3, 4, 5, 6, 7);
      final updated = DateTime(2026, 11, 22, 23, 59, 59, 999, 999);
      await repo.createNote(_note('t', created: created, updated: updated));
      await restart();
      final stored = await repo.getNoteById('t');
      expect(stored!.createdAt, created);
      expect(stored.updatedAt, updated);
    });

    test('created, updated and deleted notes persist correctly', () async {
      await repo.createNote(_note('keep', title: 'Keep'));
      await repo.createNote(_note('edit', title: 'Before'));
      await repo.createNote(_note('gone', title: 'Gone'));
      await restart();

      final edit = (await repo.getNoteById('edit'))!;
      await repo.updateNote(edit.copyWith(title: 'After'));
      await repo.deleteNote('gone');
      await restart();

      final ids = (await repo.getAllNotes()).map((n) => n.id);
      expect(ids, unorderedEquals(['keep', 'edit']));
      expect((await repo.getNoteById('edit'))!.title, 'After');
      expect(await repo.getNoteById('gone'), isNull);
    });
  });

  test('loads legacy records that lack newer fields', () async {
    await db.close();
    Hive.resetAdapters();
    Hive.registerAdapter(_LegacyNoteAdapter());
    final legacyBox = await Hive.openBox<Note>(DatabaseConstants.notesBox);
    final updated = DateTime(2025, 5, 6, 7, 8);
    await legacyBox.put('old', _note('old', title: 'Old', updated: updated));
    await legacyBox.close();
    Hive.resetAdapters();

    await restart();
    final stored = await repo.getNoteById('old');
    expect(stored!.title, 'Old');
    expect(stored.color, 0xFFFFF3BF, reason: 'missing colour gets default');
    expect(stored.createdAt, updated, reason: 'falls back to updatedAt');
    expect(stored.keyId, isNull);
    expect(stored.keyVersion, isNull);
    expect(stored.isEncrypted, isFalse);
  });
}
