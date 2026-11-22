import 'package:cipher_note/data/models/encryption_key_info.dart';
import 'package:cipher_note/data/models/note_model.dart';
import 'package:cipher_note/data/repositories/key_repository.dart';
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
      expect(await InMemoryNoteRepository().getAll(), isEmpty);
      final repo = InMemoryNoteRepository([_note('a'), _note('b')]);
      expect((await repo.getAll()).map((n) => n.id), containsAll(['a', 'b']));
    });

    test('save inserts and replaces by id', () async {
      final repo = InMemoryNoteRepository();
      await repo.save(_note('a', title: 'First'));
      await repo.save(_note('a', title: 'Second'));
      final all = await repo.getAll();
      expect(all, hasLength(1));
      expect((await repo.getById('a'))!.title, 'Second');
    });

    test('delete removes only the given note', () async {
      final repo = InMemoryNoteRepository([_note('a'), _note('b')]);
      await repo.delete('a');
      await repo.delete('missing');
      expect(await repo.getById('a'), isNull);
      expect(await repo.getById('b'), isNotNull);
    });

    test('getAll returns an unmodifiable snapshot', () async {
      final repo = InMemoryNoteRepository([_note('a')]);
      final all = await repo.getAll();
      expect(() => all.add(_note('x')), throwsUnsupportedError);
    });
  });

  group('Note model', () {
    test('is not encrypted by default and keeps plain text', () {
      final note = _note('a', content: 'আমি Flutter দিয়ে একটি নোট লিখছি।');
      expect(note.isEncrypted, isFalse);
      expect(note.content, 'আমি Flutter দিয়ে একটি নোট লিখছি।');
    });

    test('map round trip preserves all fields', () {
      final note = _note('a', title: 'বাংলা', content: 'Mixed বাংলা text');
      expect(Note.fromMap(note.toMap()), note);
    });

    test('displayTitle falls back to first content line', () {
      expect(
        _note('a', title: '', content: 'Line one\nLine two').displayTitle,
        'Line one',
      );
      expect(_note('a', title: '  ', content: '').displayTitle, 'Untitled');
    });
  });

  group('InMemoryKeyRepository', () {
    test('stores and deletes key metadata', () async {
      final repo = InMemoryKeyRepository();
      expect(await repo.getKeyInfo(), isNull);
      await repo.saveKeyInfo(
        EncryptionKeyInfo(id: 'K1', createdAt: DateTime(2026), isDemo: true),
      );
      expect((await repo.getKeyInfo())!.id, 'K1');
      await repo.deleteKeyInfo();
      expect(await repo.getKeyInfo(), isNull);
    });
  });
}
