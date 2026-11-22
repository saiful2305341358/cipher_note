import 'package:cipher_note/core/theme/app_colors.dart';
import 'package:cipher_note/core/errors/app_exceptions.dart';
import 'package:cipher_note/data/models/key_metadata.dart';
import 'package:cipher_note/data/repositories/key_metadata_repository.dart';
import 'package:cipher_note/data/repositories/secure_key_store.dart';
import 'package:cipher_note/features/encryption/data/key_service.dart';
import 'package:cipher_note/data/repositories/note_repository.dart';
import 'package:cipher_note/features/key_management/providers/key_provider.dart';
import 'package:cipher_note/features/notes/providers/notes_provider.dart';
import 'package:cipher_note/features/settings/providers/settings_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../helpers/test_repositories.dart';

void main() {
  group('NotesProvider', () {
    late InMemoryNoteRepository repo;
    late NotesProvider provider;
    late DateTime now;
    var counter = 0;

    setUp(() async {
      repo = InMemoryNoteRepository();
      now = DateTime(2026, 11, 1, 9);
      counter = 0;
      provider = NotesProvider(
        repo,
        clock: () => now,
        idGenerator: () => 'id${counter++}',
      );
      await provider.load();
    });

    test('loads as empty', () {
      expect(provider.isLoaded, isTrue);
      expect(provider.isEmpty, isTrue);
    });

    test('creates a note in memory and in the repository', () async {
      final note = await provider.createNote(
        title: 'Shopping',
        content: 'Milk',
        color: AppColors.blue.value,
      );
      expect(note.isEncrypted, isFalse);
      expect(note.createdAt, now);
      expect(provider.getById(note.id), note);
      expect(await repo.getNoteById(note.id), note);
    });

    test('updates fields and modified time only when changed', () async {
      final note = await provider.createNote(title: 'A', color: 1);
      now = now.add(const Duration(hours: 1));
      final same = await provider.updateNote(note.id, title: 'A');
      expect(same.updatedAt, note.updatedAt);

      final updated = await provider.updateNote(note.id, content: 'Body');
      expect(updated.content, 'Body');
      expect(updated.title, 'A');
      expect(updated.createdAt, note.createdAt);
      expect(updated.updatedAt, now);
      expect((await repo.getNoteById(note.id))!.content, 'Body');
    });

    test('changes note color', () async {
      final note = await provider.createNote(color: AppColors.yellow.value);
      await provider.changeColor(note.id, AppColors.pink.value);
      expect(provider.getById(note.id)!.color, AppColors.pink.value);
    });

    test('deletes and restores a note', () async {
      final note = await provider.createNote(title: 'Delete me', color: 1);
      final removed = await provider.deleteNote(note.id);
      expect(removed, note);
      expect(provider.getById(note.id), isNull);
      expect(await repo.getNoteById(note.id), isNull);
      expect(await provider.deleteNote(note.id), isNull);

      await provider.restoreNote(removed!);
      expect(provider.getById(note.id), note);
    });

    test('searches English titles and content case-insensitively', () async {
      await provider.createNote(title: 'Groceries', content: 'eggs', color: 1);
      await provider.createNote(
        title: 'Work',
        content: 'Buy EGGS too',
        color: 1,
      );
      await provider.createNote(title: 'Other', content: 'nothing', color: 1);

      expect(
        provider.search('eggs').map((n) => n.title),
        unorderedEquals(['Groceries', 'Work']),
      );
      expect(provider.search('GROC').single.title, 'Groceries');
      expect(provider.search('missing'), isEmpty);
      expect(provider.search('   '), isEmpty);
    });

    test('lists title matches before content matches', () async {
      await provider.createNote(title: 'Note', content: 'flutter', color: 1);
      now = now.add(const Duration(minutes: 1));
      await provider.createNote(title: 'Flutter tips', color: 1);
      now = now.add(const Duration(minutes: 1));
      await provider.createNote(title: 'Plain', content: 'Flutter', color: 1);
      expect(provider.search('flutter').first.title, 'Flutter tips');
    });

    test('searches Bangla titles and content', () async {
      await provider.createNote(
        title: 'বাংলা নোট',
        content: 'আমি Flutter দিয়ে একটি Note Taking Application তৈরি করছি।',
        color: 1,
      );
      await provider.createNote(
        title: 'সমস্যা',
        content: 'পিসি কিছুক্ষণ পর নিজে থেকেই বন্ধ হয়ে যায়।',
        color: 1,
      );
      await provider.createNote(title: 'English', content: 'text', color: 1);

      expect(provider.search('বাংলা').single.title, 'বাংলা নোট');
      expect(provider.search('তৈরি').single.title, 'বাংলা নোট');
      // Conjuncts (যুক্তাক্ষর), vowel signs and mixed-script queries.
      expect(provider.search('কিছুক্ষণ').single.title, 'সমস্যা');
      expect(provider.search('সমস্যা').single.title, 'সমস্যা');
      expect(provider.search('ক্ষ').single.title, 'সমস্যা');
      expect(provider.search('Flutter দিয়ে'), hasLength(1));
    });

    test('sorts by modified, created and title', () async {
      final a = await provider.createNote(title: 'Banana', color: 1);
      now = now.add(const Duration(minutes: 1));
      await provider.createNote(title: 'apple', color: 1);
      now = now.add(const Duration(minutes: 1));
      await provider.updateNote(a.id, content: 'edited');

      List<String> titles(NoteSortOrder o) =>
          provider.sorted(o).map((n) => n.title).toList();
      expect(titles(NoteSortOrder.modified), ['Banana', 'apple']);
      expect(titles(NoteSortOrder.created), ['apple', 'Banana']);
      expect(titles(NoteSortOrder.title), ['apple', 'Banana']);
    });

    test('notifies listeners on changes', () async {
      var notifications = 0;
      provider.addListener(() => notifications++);
      final note = await provider.createNote(color: 1);
      await provider.updateNote(note.id, title: 'x');
      await provider.deleteNote(note.id);
      expect(notifications, 3);
    });
  });

  group('NotesProvider failures', () {
    test('a failed write throws and leaves the list unchanged', () async {
      final repo = ControllableNoteRepository();
      final provider = NotesProvider(repo);
      await provider.load();
      final note = await provider.createNote(title: 'ok', color: 1);

      repo.failWrites = true;
      await expectLater(
        provider.createNote(title: 'fails', color: 1),
        throwsA(isA<StorageException>()),
      );
      await expectLater(
        provider.updateNote(note.id, title: 'changed'),
        throwsA(isA<StorageException>()),
      );
      expect(provider.notes.single.title, 'ok');

      repo.failDeletes = true;
      await expectLater(
        provider.deleteNote(note.id),
        throwsA(isA<StorageException>()),
      );
      expect(provider.getById(note.id), isNotNull);
    });

    test('a failed load sets loadError and can be retried', () async {
      final repo = ControllableNoteRepository()..failLoad = true;
      final provider = NotesProvider(repo);
      await provider.load();
      expect(provider.isLoaded, isFalse);
      expect(provider.loadError, isA<StorageException>());

      repo.failLoad = false;
      await provider.load();
      expect(provider.isLoaded, isTrue);
      expect(provider.loadError, isNull);
    });

    test(
      'updating a deleted note reports it instead of re-creating it',
      () async {
        final provider = NotesProvider(InMemoryNoteRepository());
        await provider.load();
        await expectLater(
          provider.updateNote('missing', title: 'x'),
          throwsA(isA<RecordNotFoundException>()),
        );
        expect(provider.isEmpty, isTrue);
      },
    );
  });

  group('SettingsProvider', () {
    test('saves every change and reports failures', () async {
      final repo = RecordingSettingsRepository();
      final settings = SettingsProvider(repository: repo);
      settings.setThemeMode(ThemeMode.dark);
      settings.setViewMode(NoteViewMode.grid);
      await settings.pendingSave;
      expect(repo.stored.themeMode, ThemeMode.dark);
      expect(repo.stored.viewMode, NoteViewMode.grid);
      expect(settings.saveError, isNull);

      repo.failSaves = true;
      settings.setThemeMode(ThemeMode.light);
      await settings.pendingSave;
      expect(settings.themeMode, ThemeMode.light, reason: 'still applied');
      expect(settings.saveError, isA<StorageException>());

      repo.failSaves = false;
      settings.setThemeMode(ThemeMode.dark);
      await settings.pendingSave;
      expect(settings.saveError, isNull);
    });

    test('setting the same value does not write again', () async {
      final repo = RecordingSettingsRepository();
      final settings = SettingsProvider(repository: repo);
      settings.setThemeMode(ThemeMode.system);
      await settings.pendingSave;
      expect(repo.saveCalls, 0);
    });

    test('toggles between list and grid view', () {
      final settings = SettingsProvider();
      expect(settings.viewMode, NoteViewMode.list);
      settings.toggleViewMode();
      expect(settings.isGridView, isTrue);
      settings.toggleViewMode();
      expect(settings.viewMode, NoteViewMode.list);
    });

    test('switches theme mode', () {
      final settings = SettingsProvider();
      expect(settings.themeMode, ThemeMode.system);
      for (final mode in ThemeMode.values) {
        settings.setThemeMode(mode);
        expect(settings.themeMode, mode);
      }
    });

    test('stores note preferences', () {
      final settings = SettingsProvider();
      expect(settings.defaultNoteColor, AppColors.yellow.value);
      settings
        ..setDefaultNoteColor(AppColors.green.value)
        ..setSortOrder(NoteSortOrder.title)
        ..setShowContentPreview(false)
        ..setAutoSave(false);
      expect(settings.defaultNoteColor, AppColors.green.value);
      expect(settings.sortOrder, NoteSortOrder.title);
      expect(settings.showContentPreview, isFalse);
      expect(settings.autoSave, isFalse);
    });
  });

  group('KeyProvider', () {
    KeyProvider build({
      InMemoryKeyMetadataRepository? metadata,
      InMemoryNoteRepository? notes,
    }) => KeyProvider(
      KeyService(
        metadata: metadata ?? InMemoryKeyMetadataRepository(),
        secureStore: InMemorySecureKeyStore(),
        notes: notes ?? InMemoryNoteRepository(),
      ),
    );

    test('starts without keys, creates one and makes it active', () async {
      final keys = build();
      await keys.load();
      expect(keys.isLoaded, isTrue);
      expect(keys.hasKeys, isFalse);
      final created = await keys.createKey('Personal');
      expect(keys.keys, [created]);
      expect(keys.activeKey, created);
      expect(keys.isAvailable(created.id, 1), isTrue);
      expect(keys.isAvailable(created.id, 2), isFalse);
      expect(keys.isBusy, isFalse);
    });

    test('switches the active key and deletes an unused key', () async {
      final keys = build();
      await keys.load();
      final first = await keys.createKey('First');
      final second = await keys.createKey('Second');
      expect(keys.activeKey!.id, second.id);
      await keys.setActive(first.id);
      expect(keys.activeKey!.id, first.id);
      expect(keys.keys.where((k) => k.isActive), hasLength(1));
      await keys.deleteKey(second.id);
      expect(keys.keys.map((k) => k.id), [first.id]);
    });

    test('loads stored key metadata', () async {
      final keys = build(
        metadata: InMemoryKeyMetadataRepository([
          KeyMetadata(
            id: 'k1',
            name: 'Stored',
            version: 2,
            algorithm: KeyMetadata.hillCipher2x2,
            createdAt: DateTime(2026),
          ),
        ]),
      );
      await keys.load();
      expect(keys.keyById('k1')!.version, 2);
      expect(keys.keyById('missing'), isNull);
    });
  });

  group('AppColors', () {
    test('resolves palette values and falls back for unknown values', () {
      expect(AppColors.noteColorFor(AppColors.purple.value), AppColors.purple);
      expect(AppColors.noteColorFor(0x12345678), AppColors.defaultNoteColor);
      expect(
        AppColors.noteBackground(AppColors.blue.value, Brightness.dark),
        AppColors.blue.dark,
      );
    });
  });
}
