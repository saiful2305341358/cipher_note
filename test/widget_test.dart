// Widget tests for the UI: navigation, note CRUD through the UI, search,
// grid/list, colours, theme switching, autosave, unsaved changes, save
// failures and the encryption/key-management placeholders.

import 'package:cipher_note/app.dart';
import 'package:cipher_note/core/theme/app_colors.dart';
import 'package:cipher_note/data/models/note_model.dart';
import 'package:cipher_note/features/notes/providers/notes_provider.dart';
import 'package:cipher_note/features/settings/providers/settings_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import 'helpers/test_repositories.dart';

const _bangla = 'আমি Flutter দিয়ে একটি Note Taking Application তৈরি করছি।';

Note _note(String id, String title, String content, {int? color}) {
  final time = DateTime(2026, 11, 3, 16, 49);
  return Note(
    id: id,
    title: title,
    content: content,
    color: color ?? AppColors.yellow.value,
    createdAt: time,
    updatedAt: time,
  );
}

Future<ControllableNoteRepository> _pumpApp(
  WidgetTester tester, {
  List<Note> notes = const [],
  SettingsProvider? settings,
  ControllableNoteRepository? repository,
}) async {
  final repo = repository ?? ControllableNoteRepository(notes);
  await tester.pumpWidget(
    CipherNoteApp(noteRepository: repo, settings: settings),
  );
  await tester.pumpAndSettle();
  return repo;
}

NotesProvider _notesOf(WidgetTester tester) => Provider.of<NotesProvider>(
  tester.element(find.byType(Navigator).first),
  listen: false,
);

Future<void> _openMenuItem(WidgetTester tester, String label) async {
  await tester.tap(find.byTooltip('More options'));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

Future<void> _goBack(WidgetTester tester) async {
  await tester.pageBack();
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows the empty state when there are no notes', (tester) async {
    await _pumpApp(tester);
    expect(find.text('Cipher Note'), findsOneWidget);
    expect(find.text('No notes yet'), findsOneWidget);
    expect(find.byTooltip('Add note'), findsOneWidget);
  });

  testWidgets('creates a note (English + Bangla) and shows it on home', (
    tester,
  ) async {
    await _pumpApp(tester);
    await tester.tap(find.byTooltip('Add note'));
    await tester.pumpAndSettle();
    expect(find.text('New note'), findsWidgets);

    await tester.enterText(find.byKey(const Key('editor-title')), 'বাংলা নোট');
    await tester.enterText(find.byKey(const Key('editor-content')), _bangla);
    await tester.pump();
    await _goBack(tester);

    expect(find.text('No notes yet'), findsNothing);
    expect(find.text('বাংলা নোট'), findsOneWidget);
    expect(find.text(_bangla), findsOneWidget);
    final stored = _notesOf(tester).notes.single;
    expect(stored.content, _bangla);
    expect(stored.isEncrypted, isFalse);
  });

  testWidgets('leaving an empty new note does not create a note', (
    tester,
  ) async {
    await _pumpApp(tester);
    await tester.tap(find.byTooltip('Add note'));
    await tester.pumpAndSettle();
    await _goBack(tester);
    expect(find.text('No notes yet'), findsOneWidget);
  });

  testWidgets('edits an existing note and preserves its content', (
    tester,
  ) async {
    await _pumpApp(tester, notes: [_note('a', 'Problema', 'Original text')]);
    await tester.tap(find.text('Problema'));
    await tester.pumpAndSettle();

    expect(find.text('Original text'), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('editor-content')),
      'Updated text',
    );
    await tester.tap(find.byKey(const Key('editor-save')));
    await tester.pumpAndSettle();
    expect(find.text('Note saved'), findsOneWidget);
    expect(_notesOf(tester).getById('a')!.content, 'Updated text');

    await _goBack(tester);
    expect(find.text('Updated text'), findsOneWidget);
  });

  testWidgets('opening and closing a note does not change it', (tester) async {
    final original = _note('a', 'Title', 'Body');
    await _pumpApp(tester, notes: [original]);
    await tester.tap(find.text('Title'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('editor-content')));
    await tester.pump(const Duration(seconds: 1));
    await _goBack(tester);
    expect(_notesOf(tester).getById('a'), original);
  });

  testWidgets('auto-save writes changes after a short delay', (tester) async {
    await _pumpApp(tester, notes: [_note('a', 'Title', 'Body')]);
    await tester.tap(find.text('Title'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('editor-content')), 'Auto');
    await tester.pump(const Duration(seconds: 1));
    expect(_notesOf(tester).getById('a')!.content, 'Auto');
    await _goBack(tester);
  });

  testWidgets('asks to save or discard when auto-save is off', (tester) async {
    await _pumpApp(
      tester,
      notes: [_note('a', 'Title', 'Body')],
      settings: SettingsProvider(autoSave: false),
    );
    await tester.tap(find.text('Title'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('editor-content')), 'Changed');
    await tester.pump();

    await _goBack(tester);
    expect(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Unsaved changes'),
      ),
      findsOneWidget,
    );

    // Keep editing keeps the editor open.
    await tester.tap(find.text('Keep editing'));
    await tester.pumpAndSettle();
    expect(find.text('Edit note'), findsOneWidget);

    // Discard leaves without saving.
    await _goBack(tester);
    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();
    expect(find.text('Edit note'), findsNothing);
    expect(_notesOf(tester).getById('a')!.content, 'Body');

    // Save stores the changes.
    await tester.tap(find.text('Title'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('editor-content')), 'Saved');
    await tester.pump();
    await _goBack(tester);
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Edit note'), findsNothing);
    expect(_notesOf(tester).getById('a')!.content, 'Saved');
  });

  testWidgets('deletes a note after confirmation and can undo', (tester) async {
    await _pumpApp(tester, notes: [_note('a', 'Delete me', 'Body')]);
    await tester.tap(find.text('Delete me'));
    await tester.pumpAndSettle();

    await _openMenuItem(tester, 'Delete');
    expect(find.text('Delete note?'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Delete'));
    await tester.pumpAndSettle();

    expect(find.text('No notes yet'), findsOneWidget);
    expect(find.text('Note deleted'), findsOneWidget);
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(find.text('Delete me'), findsOneWidget);
  });

  testWidgets('changes the note color from the editor', (tester) async {
    await _pumpApp(tester, notes: [_note('a', 'Colorful', 'Body')]);
    await tester.tap(find.text('Colorful'));
    await tester.pumpAndSettle();

    await _openMenuItem(tester, 'Change color');
    await tester.tap(find.byKey(const ValueKey('note-color-Pink')));
    await tester.pumpAndSettle();
    expect(_notesOf(tester).getById('a')!.color, AppColors.pink.value);

    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold).last);
    expect(scaffold.backgroundColor, AppColors.pink.light);

    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    await _goBack(tester);
    final card = find.ancestor(
      of: find.text('Colorful'),
      matching: find.byType(Material),
    );
    expect(
      tester
          .widgetList<Material>(card)
          .any((m) => m.color == AppColors.pink.light),
      isTrue,
    );
  });

  testWidgets('Encrypt button shows a future-update dialog only', (
    tester,
  ) async {
    await _pumpApp(tester);
    await tester.tap(find.byTooltip('Add note'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('encrypt-button')), findsNothing);

    await tester.enterText(find.byKey(const Key('editor-content')), 'Secret');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('encrypt-button')), findsOneWidget);

    await tester.tap(find.byKey(const Key('encrypt-button')));
    await tester.pumpAndSettle();
    expect(find.text('Encryption coming soon'), findsOneWidget);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(find.text('Encryption coming soon'), findsNothing);
    await _goBack(tester);
    expect(_notesOf(tester).notes.single.content, 'Secret');
    expect(_notesOf(tester).notes.single.isEncrypted, isFalse);
  });

  testWidgets('toggles between list and grid layouts', (tester) async {
    await _pumpApp(tester, notes: [_note('a', 'One', 'Body')]);
    expect(find.byKey(const Key('notes-list')), findsOneWidget);
    await tester.tap(find.byKey(const Key('view-toggle')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('notes-grid')), findsOneWidget);
    expect(find.text('One'), findsOneWidget);
    await tester.tap(find.byKey(const Key('view-toggle')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('notes-list')), findsOneWidget);
  });

  testWidgets('search finds English and Bangla notes and opens them', (
    tester,
  ) async {
    await _pumpApp(
      tester,
      notes: [
        _note('a', 'Shopping', 'Milk and eggs'),
        _note('b', 'বাংলা নোট', _bangla),
      ],
    );
    await tester.tap(find.byTooltip('Search'));
    await tester.pumpAndSettle();
    expect(find.text('Search your notes'), findsOneWidget);

    final field = find.byKey(const Key('search-field'));
    await tester.enterText(field, 'eggs');
    await tester.pump();
    expect(find.text('1 result'), findsOneWidget);
    expect(find.text('Shopping'), findsOneWidget);

    await tester.enterText(field, 'তৈরি');
    await tester.pump();
    expect(find.text('1 result'), findsOneWidget);
    expect(find.text('বাংলা নোট'), findsOneWidget);

    await tester.enterText(field, 'nothing here');
    await tester.pump();
    expect(find.text('No results'), findsOneWidget);

    await tester.tap(find.byKey(const Key('search-clear')));
    await tester.pump();
    expect(find.text('Search your notes'), findsOneWidget);

    await tester.enterText(field, 'বাংলা');
    await tester.pump();
    await tester.tap(find.text('বাংলা নোট'));
    await tester.pumpAndSettle();
    expect(find.text('Edit note'), findsOneWidget);
    expect(find.text(_bangla), findsOneWidget);

    await _goBack(tester);
    expect(find.byKey(const Key('search-field')), findsOneWidget);
  });

  testWidgets('switches theme from settings immediately', (tester) async {
    await _pumpApp(tester);
    await _openMenuItem(tester, 'Settings');
    expect(find.text('Appearance'.toUpperCase()), findsOneWidget);

    await tester.tap(find.byKey(const Key('theme-dark')));
    await tester.pumpAndSettle();
    var app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.themeMode, ThemeMode.dark);
    expect(
      Theme.of(tester.element(find.text('Settings'))).brightness,
      Brightness.dark,
    );

    await tester.tap(find.byKey(const Key('theme-light')));
    await tester.pumpAndSettle();
    app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.themeMode, ThemeMode.light);

    await tester.tap(find.byKey(const Key('theme-system')));
    await tester.pumpAndSettle();
    app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.themeMode, ThemeMode.system);
  });

  testWidgets('default note color from settings is used for new notes', (
    tester,
  ) async {
    await _pumpApp(tester);
    await _openMenuItem(tester, 'Settings');
    await tester.tap(find.byKey(const Key('default-color')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('note-color-Green')));
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    await _goBack(tester);

    await tester.tap(find.byTooltip('Add note'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('editor-title')), 'Green');
    await _goBack(tester);
    expect(_notesOf(tester).notes.single.color, AppColors.green.value);
  });

  testWidgets('key management shows no-key state, dialog and demo state', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await _pumpApp(tester);
    await _openMenuItem(tester, 'Key Management');
    expect(
      find.text('No encryption key has been created yet.'),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('generate-key')));
    await tester.pumpAndSettle();
    expect(
      find.text('Key generation will be available in a future update.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('preview-demo-key')));
    await tester.pumpAndSettle();
    expect(find.text('Key available'), findsOneWidget);
    expect(find.text('DEMO-2X2-0001'), findsOneWidget);

    await tester.ensureVisible(find.byKey(const Key('delete-key')));
    await tester.tap(find.byKey(const Key('delete-key')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Delete'));
    await tester.pumpAndSettle();
    expect(
      find.text('No encryption key has been created yet.'),
      findsOneWidget,
    );
  });

  testWidgets('settings links open encryption info and about screens', (
    tester,
  ) async {
    // A tall phone-shaped viewport so that the whole info page is built.
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await _pumpApp(tester);
    await _openMenuItem(tester, 'Settings');

    await tester.scrollUntilVisible(
      find.text('Encryption information'),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.text('Encryption information'));
    await tester.pumpAndSettle();
    expect(find.text('What is encryption?'), findsOneWidget);
    expect(find.textContaining('educational cipher'), findsOneWidget);
    await tester.tap(find.text('বাংলা'));
    await tester.pumpAndSettle();
    expect(find.text('এনক্রিপশন কী?'), findsOneWidget);

    // Opening Key Management from here and then Encryption info again must
    // not stack duplicate screens.
    await tester.scrollUntilVisible(
      find.text('কী ম্যানেজমেন্ট খুলুন'),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.text('কী ম্যানেজমেন্ট খুলুন'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('About encryption'));
    await tester.pumpAndSettle();
    expect(find.text('Encryption information'), findsOneWidget);
    await _goBack(tester);
    expect(find.text('Settings'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('About Cipher Note'),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.text('About Cipher Note'));
    await tester.pumpAndSettle();
    expect(
      find.text('Version 1.1.0 (build 2) · Phase 2 · Local storage'),
      findsOneWidget,
    );
    await _goBack(tester);
    await _goBack(tester);
    expect(find.text('Cipher Note'), findsOneWidget);
  });

  testWidgets('home screen has no overflow on a small screen in dark mode', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await _pumpApp(
      tester,
      notes: [
        for (var i = 0; i < 6; i++)
          _note('$i', 'যুক্তাক্ষর পরীক্ষা $i — a long mixed title', _bangla),
      ],
      settings: SettingsProvider(themeMode: ThemeMode.dark),
    );
    await tester.tap(find.byKey(const Key('view-toggle')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('যুক্তাক্ষর পরীক্ষা 0 — a long mixed title'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await _goBack(tester);
  });
}
