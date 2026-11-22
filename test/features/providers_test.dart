import 'package:cipher_note/core/theme/app_colors.dart';
import 'package:cipher_note/data/repositories/key_repository.dart';
import 'package:cipher_note/data/repositories/note_repository.dart';
import 'package:cipher_note/features/key_management/providers/key_provider.dart';
import 'package:cipher_note/features/notes/providers/notes_provider.dart';
import 'package:cipher_note/features/settings/providers/settings_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

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
      expect(await repo.getById(note.id), note);
    });

    test('updates fields and modified time only when changed', () async {
      final note = await provider.createNote(title: 'A', color: 1);
      now = now.add(const Duration(hours: 1));
      final same = await provider.updateNote(note.id, title: 'A');
      expect(same!.updatedAt, note.updatedAt);

      final updated = await provider.updateNote(note.id, content: 'Body');
      expect(updated!.content, 'Body');
      expect(updated.title, 'A');
      expect(updated.createdAt, note.createdAt);
      expect(updated.updatedAt, now);
      expect((await repo.getById(note.id))!.content, 'Body');
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
      expect(await repo.getById(note.id), isNull);
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

  group('SettingsProvider', () {
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
    test('has no key by default and can preview/delete a demo key', () async {
      final keys = KeyProvider(InMemoryKeyRepository());
      await keys.load();
      expect(keys.hasKey, isFalse);
      await keys.showDemoKey();
      expect(keys.hasKey, isTrue);
      expect(keys.keyInfo!.isDemo, isTrue);
      await keys.deleteKey();
      expect(keys.hasKey, isFalse);
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
