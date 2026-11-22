import 'package:cipher_note/core/errors/app_exceptions.dart';
import 'package:cipher_note/core/utils/id_generator.dart';
import 'package:cipher_note/data/models/note_model.dart';
import 'package:cipher_note/data/repositories/note_repository.dart';
import 'package:flutter_test/flutter_test.dart';

Note _note(String id, {String title = 'T', String content = 'C'}) {
  final time = DateTime(2026, 11, 3, 16, 49);
  return Note(
    id: id,
    title: title,
    content: content,
    color: 0xFFFFF3BF,
    createdAt: time,
    updatedAt: time,
  );
}

void main() {
  group('InMemoryNoteRepository', () {
    test('starts empty and accepts initial notes', () async {
      expect(await InMemoryNoteRepository().getAllNotes(), isEmpty);
      final repo = InMemoryNoteRepository([_note('a'), _note('b')]);
      expect(
        (await repo.getAllNotes()).map((n) => n.id),
        containsAll(['a', 'b']),
      );
    });

    test(
      'create rejects duplicates and update requires an existing note',
      () async {
        final repo = InMemoryNoteRepository();
        await repo.createNote(_note('a', title: 'First'));
        await expectLater(
          repo.createNote(_note('a')),
          throwsA(isA<DuplicateRecordException>()),
        );
        await repo.updateNote(_note('a', title: 'Second'));
        expect((await repo.getNoteById('a'))!.title, 'Second');
        await expectLater(
          repo.updateNote(_note('x')),
          throwsA(isA<RecordNotFoundException>()),
        );
        expect(await repo.getAllNotes(), hasLength(1));
      },
    );

    test('delete removes only the given note; deleteAll clears', () async {
      final repo = InMemoryNoteRepository([_note('a'), _note('b')]);
      await repo.deleteNote('a');
      await repo.deleteNote('missing');
      expect(await repo.getNoteById('a'), isNull);
      expect(await repo.getNoteById('b'), isNotNull);
      await repo.deleteAllNotes();
      expect(await repo.getAllNotes(), isEmpty);
    });

    test('getAllNotes returns an unmodifiable snapshot', () async {
      final repo = InMemoryNoteRepository([_note('a')]);
      final all = await repo.getAllNotes();
      expect(() => all.add(_note('x')), throwsUnsupportedError);
    });

    test('searchNotes matches titles and content', () async {
      final repo = InMemoryNoteRepository([
        _note('a', title: 'বাংলা', content: 'x'),
        _note('b', title: 'x', content: 'Hello বাংলা'),
      ]);
      expect((await repo.searchNotes('বাংলা')).map((n) => n.id), ['a', 'b']);
      expect(await repo.searchNotes(' '), isEmpty);
    });
  });

  group('Note model', () {
    test('is not encrypted by default and keeps plain text', () {
      final note = _note('a', content: 'আমি Flutter দিয়ে একটি নোট লিখছি।');
      expect(note.isEncrypted, isFalse);
      expect(note.keyId, isNull);
      expect(note.keyVersion, isNull);
      expect(note.content, 'আমি Flutter দিয়ে একটি নোট লিখছি।');
    });

    test('map round trip preserves all fields', () {
      final note = Note(
        id: 'a',
        title: 'বাংলা',
        content: 'Mixed বাংলা text',
        color: 1,
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026, 2),
        keyId: 'k',
        keyVersion: 2,
      );
      expect(Note.fromMap(note.toMap()), note);
    });

    test('copyWith keeps id, createdAt and key reference', () {
      final note = Note(
        id: 'a',
        title: 't',
        content: 'c',
        color: 1,
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
        keyId: 'k',
        keyVersion: 1,
      );
      final copy = note.copyWith(title: 'new', updatedAt: DateTime(2027));
      expect(copy.id, 'a');
      expect(copy.createdAt, DateTime(2026));
      expect(copy.keyId, 'k');
      expect(copy.keyVersion, 1);
    });

    test('displayTitle falls back to first content line', () {
      expect(
        _note('a', title: '', content: 'Line one\nLine two').displayTitle,
        'Line one',
      );
      expect(_note('a', title: '  ', content: '').displayTitle, 'Untitled');
    });
  });

  test('IdGenerator produces unique ids', () {
    final ids = {for (var i = 0; i < 10000; i++) IdGenerator.generate()};
    expect(ids, hasLength(10000));
    expect(ids.first, startsWith('n_'));
  });
}
