// Widget tests for autosave and storage error handling in the UI.

import 'package:cipher_note/app.dart';
import 'package:cipher_note/core/constants/app_constants.dart';
import 'package:cipher_note/core/errors/app_exceptions.dart';
import 'package:cipher_note/core/startup/app_initializer.dart';
import 'package:cipher_note/core/startup/startup_error_app.dart';
import 'package:cipher_note/data/models/note_model.dart';
import 'package:cipher_note/data/repositories/key_metadata_repository.dart';
import 'package:cipher_note/data/repositories/secure_key_store.dart';
import 'package:cipher_note/features/notes/providers/notes_provider.dart';
import 'package:cipher_note/features/settings/providers/settings_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../helpers/test_repositories.dart';

Note _note(String id, String title, String content) {
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

Future<ControllableNoteRepository> _pump(
  WidgetTester tester, {
  List<Note> notes = const [],
  SettingsProvider? settings,
}) async {
  final repo = ControllableNoteRepository(notes);
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

Finder get _title => find.byKey(const Key('editor-title'));
Finder get _content => find.byKey(const Key('editor-content'));

String _status(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(const Key('editor-status'))).data!;

Future<void> _back(WidgetTester tester) async {
  await tester.pageBack();
  await tester.pumpAndSettle();
}

const _afterDebounce = Duration(milliseconds: 700);

void main() {
  testWidgets('title and content autosave once typing pauses (debounced)', (
    tester,
  ) async {
    final repo = await _pump(tester, notes: [_note('a', 'Title', 'Body')]);
    await tester.tap(find.text('Title'));
    await tester.pumpAndSettle();

    // Several quick edits inside the debounce window...
    await tester.enterText(_title, 'T');
    await tester.pump(const Duration(milliseconds: 200));
    await tester.enterText(_title, 'Ti');
    await tester.pump(const Duration(milliseconds: 200));
    await tester.enterText(_content, 'বাংলা body');
    await tester.pump(const Duration(milliseconds: 200));
    expect(repo.updateCalls, 0, reason: 'nothing written while typing');
    expect(_status(tester), 'Saving…');

    // ...are written as a single update once typing stops.
    await tester.pump(_afterDebounce);
    expect(repo.updateCalls, 1);
    final stored = await repo.getNoteById('a');
    expect(stored!.title, 'Ti');
    expect(stored.content, 'বাংলা body');
    await tester.pump();
    expect(_status(tester), startsWith('Saved'));
    await _back(tester);
  });

  testWidgets('a new note is created once, then updated (no duplicates)', (
    tester,
  ) async {
    final repo = await _pump(tester);
    await tester.tap(find.byTooltip('Add note'));
    await tester.pumpAndSettle();
    await tester.enterText(_title, 'First');
    await tester.pump(_afterDebounce);
    await tester.enterText(_content, 'More text');
    await tester.pump(_afterDebounce);
    await tester.enterText(_content, 'Even more');
    await _back(tester);

    expect(repo.createCalls, 1);
    final all = await repo.getAllNotes();
    expect(all, hasLength(1));
    expect(all.single.content, 'Even more');
  });

  testWidgets('a pending save is flushed when leaving immediately', (
    tester,
  ) async {
    final repo = await _pump(tester, notes: [_note('a', 'Title', 'Body')]);
    await tester.tap(find.text('Title'));
    await tester.pumpAndSettle();
    await tester.enterText(_content, 'Typed then left');
    // Leave before the debounce delay has passed.
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Edit note'), findsNothing);
    expect((await repo.getNoteById('a'))!.content, 'Typed then left');
  });

  testWidgets('pending changes are saved when the app goes to background', (
    tester,
  ) async {
    final repo = await _pump(tester, notes: [_note('a', 'Title', 'Body')]);
    await tester.tap(find.text('Title'));
    await tester.pumpAndSettle();
    await tester.enterText(_content, 'Backgrounded');
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    expect((await repo.getNoteById('a'))!.content, 'Backgrounded');
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await _back(tester);
  });

  testWidgets('a failed autosave is shown and changes are kept', (
    tester,
  ) async {
    final repo = await _pump(tester, notes: [_note('a', 'Title', 'Body')]);
    await tester.tap(find.text('Title'));
    await tester.pumpAndSettle();
    repo.failWrites = true;

    await tester.enterText(_content, 'Important');
    await tester.pump(_afterDebounce);
    await tester.pump();
    expect(_status(tester), 'Unable to save');
    expect(find.textContaining('Saved'), findsNothing);
    expect((await repo.getNoteById('a'))!.content, 'Body');

    // Leaving asks what to do; keep editing stays with the text intact.
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Unable to save'), findsWidgets);
    await tester.tap(find.text('Keep editing'));
    await tester.pumpAndSettle();
    expect(find.text('Edit note'), findsOneWidget);
    expect(find.text('Important'), findsOneWidget);

    // Leaving again asks again; once storage works, "Try again" saves and
    // leaves.
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Try again'), findsOneWidget);
    repo.failWrites = false;
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(find.text('Edit note'), findsNothing);
    expect((await repo.getNoteById('a'))!.content, 'Important');
  });

  testWidgets('discarding after a failed save is an explicit choice', (
    tester,
  ) async {
    final repo = await _pump(tester, notes: [_note('a', 'Title', 'Body')]);
    await tester.tap(find.text('Title'));
    await tester.pumpAndSettle();
    repo.failWrites = true;
    await tester.enterText(_content, 'Lost on purpose');
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Discard changes'));
    await tester.pumpAndSettle();
    expect(find.text('Edit note'), findsNothing);
    expect((await repo.getNoteById('a'))!.content, 'Body');
  });

  testWidgets('Save button reports failure instead of "Note saved"', (
    tester,
  ) async {
    final repo = await _pump(
      tester,
      notes: [_note('a', 'Title', 'Body')],
      settings: SettingsProvider(autoSave: false),
    );
    await tester.tap(find.text('Title'));
    await tester.pumpAndSettle();
    repo.failWrites = true;
    await tester.enterText(_content, 'x');
    await tester.tap(find.byKey(const Key('editor-save')));
    await tester.pumpAndSettle();
    expect(find.text('Note saved'), findsNothing);
    expect(find.text('The note could not be saved.'), findsOneWidget);

    repo.failWrites = false;
    await tester.tap(find.byKey(const Key('editor-save')));
    await tester.pumpAndSettle();
    expect(find.text('Note saved'), findsOneWidget);
    await tester.pumpAndSettle(const Duration(seconds: 3));
    await _back(tester);
  });

  testWidgets('a failed delete keeps the note and the editor open', (
    tester,
  ) async {
    final repo = await _pump(tester, notes: [_note('a', 'Keep me', 'Body')]);
    repo.failDeletes = true;
    await tester.tap(find.text('Keep me'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('More options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete').last);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Delete'));
    await tester.pumpAndSettle();

    expect(find.text('The note could not be deleted.'), findsOneWidget);
    expect(find.text('Edit note'), findsOneWidget);
    expect(_notesOf(tester).getById('a'), isNotNull);
    expect(await repo.getNoteById('a'), isNotNull);
  });

  testWidgets('home shows a retryable error when notes cannot load', (
    tester,
  ) async {
    final repo = ControllableNoteRepository([_note('a', 'Saved note', 'x')])
      ..failLoad = true;
    await tester.pumpWidget(CipherNoteApp(noteRepository: repo));
    await tester.pumpAndSettle();
    expect(find.text('Your notes could not be loaded'), findsOneWidget);
    expect(find.textContaining('Nothing has been deleted'), findsOneWidget);

    repo.failLoad = false;
    await tester.tap(find.byKey(const Key('notes-retry')));
    await tester.pumpAndSettle();
    expect(find.text('Saved note'), findsOneWidget);
  });

  testWidgets('settings changes are saved and failures are shown', (
    tester,
  ) async {
    final settingsRepo = RecordingSettingsRepository();
    await tester.pumpWidget(
      CipherNoteApp(
        noteRepository: ControllableNoteRepository(),
        settings: SettingsProvider(repository: settingsRepo),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('More options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Settings').last);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('theme-dark')));
    await tester.pumpAndSettle();
    expect(settingsRepo.stored.themeMode, ThemeMode.dark);
    expect(find.byKey(const Key('settings-save-error')), findsNothing);

    settingsRepo.failSaves = true;
    await tester.tap(find.byKey(const Key('theme-light')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('settings-save-error')), findsOneWidget);
    expect(settingsRepo.stored.themeMode, ThemeMode.dark);
  });

  testWidgets('startup error screen retries and then opens the app', (
    tester,
  ) async {
    var attempts = 0;
    Future<AppDependencies> initialize() async {
      attempts++;
      if (attempts == 1) {
        throw const DatabaseInitException('Still locked.');
      }
      return AppDependencies(
        noteRepository: ControllableNoteRepository([
          _note('a', 'Recovered', 'x'),
        ]),
        keyRepository: InMemoryKeyMetadataRepository(),
        settingsRepository: RecordingSettingsRepository(),
        secureKeyStore: InMemorySecureKeyStore(),
        initialSettings: AppSettings.defaults,
      );
    }

    await tester.pumpWidget(
      StartupErrorApp(
        error: const DatabaseInitException(
          'The app could not open your saved notes.',
        ),
        initialize: initialize,
      ),
    );
    expect(find.text('Your notes could not be opened'), findsOneWidget);
    expect(find.textContaining('Nothing has been deleted'), findsOneWidget);

    await tester.tap(find.byKey(const Key('startup-retry')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Still locked.'), findsOneWidget);

    await tester.tap(find.byKey(const Key('startup-retry')));
    await tester.pumpAndSettle();
    expect(find.text(AppConstants.appName), findsOneWidget);
    expect(find.text('Recovered'), findsOneWidget);
  });
}
