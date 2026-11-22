// End-to-end UI tests for encrypting, decrypting and editing notes
// (Phase 4 UI: bottom Encrypt button, Decrypt Note only in the ⋮ menu).

import 'dart:async';

import 'package:cipher_note/app.dart';
import 'package:cipher_note/data/models/key_metadata.dart';
import 'package:cipher_note/data/models/note_model.dart';
import 'package:cipher_note/data/repositories/key_metadata_repository.dart';
import 'package:cipher_note/data/repositories/secure_key_store.dart';
import 'package:cipher_note/features/encryption/data/key_service.dart';
import 'package:cipher_note/features/encryption/data/note_encryption_service.dart';
import 'package:cipher_note/features/settings/providers/settings_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../helpers/test_repositories.dart';

const _title = 'Secret plan';
const _content = 'Meet at ১০টা, room 5.\nআমি আসছি!';

/// Secure store whose reads can be held open, to observe busy states.
class _GatedSecureStore extends InMemorySecureKeyStore {
  Completer<void>? gate;

  @override
  Future<List<int>?> read({required String keyId, required int version}) async {
    final g = gate;
    if (g != null) await g.future;
    return super.read(keyId: keyId, version: version);
  }
}

class _Stores {
  _Stores([List<Note> notes = const []])
    : notes = ControllableNoteRepository(notes);

  final ControllableNoteRepository notes;
  final metadata = InMemoryKeyMetadataRepository();
  final secure = _GatedSecureStore();

  KeyService get keys =>
      KeyService(metadata: metadata, secureStore: secure, notes: notes);
  NoteEncryptionService get encryption => NoteEncryptionService(keys: keys);

  Future<Note> stored(String id) async => (await notes.getNoteById(id))!;

  /// Encrypts a stored note outside the UI (test setup).
  Future<KeyMetadata> encryptStored(String id, {KeyMetadata? key}) async {
    final k = key ?? await keys.createKey('Personal');
    final note = await stored(id);
    await notes.updateNote(
      await encryption.encrypt(
        note: note,
        title: note.title,
        content: note.content,
        key: k,
      ),
    );
    return k;
  }
}

Note _note({
  String id = 'n',
  String title = _title,
  String content = _content,
}) {
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

Future<void> _pump(
  WidgetTester tester,
  _Stores stores, {
  SettingsProvider? settings,
}) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    CipherNoteApp(
      noteRepository: stores.notes,
      keyRepository: stores.metadata,
      secureKeyStore: stores.secure,
      settings: settings,
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _tapText(WidgetTester tester, String text) async {
  await tester.tap(find.text(text).last);
  await tester.pumpAndSettle();
}

Future<void> _tapKey(WidgetTester tester, String key) async {
  await tester.tap(find.byKey(Key(key)));
  await tester.pumpAndSettle();
}

Future<void> _openMenu(WidgetTester tester) async {
  await tester.tap(find.byTooltip('More options'));
  await tester.pumpAndSettle();
}

Future<void> _menu(WidgetTester tester, String item) async {
  await _openMenu(tester);
  await _tapText(tester, item);
}

Future<void> _back(WidgetTester tester) async {
  await tester.pageBack();
  await tester.pumpAndSettle();
}

Future<void> _confirmEncrypt(WidgetTester tester) async {
  expect(find.text('Encrypt This Note?'), findsOneWidget);
  await tester.tap(find.widgetWithText(TextButton, 'Encrypt'));
  await tester.pumpAndSettle();
}

FilledButton _encryptButton(WidgetTester tester) =>
    tester.widget<FilledButton>(find.byKey(const Key('encrypt-button')));

bool _encryptEnabled(WidgetTester tester) =>
    _encryptButton(tester).onPressed != null;

Finder get _content_ => find.byKey(const Key('editor-content'));
Finder get _title_ => find.byKey(const Key('editor-title'));

void main() {
  group('Encrypt button', () {
    testWidgets('appears only after saving and follows the save state', (
      tester,
    ) async {
      final stores = _Stores();
      await _pump(tester, stores);
      await tester.tap(find.byTooltip('Add note'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('encrypt-button')), findsNothing);

      // Typing a new note: not saved yet → hidden.
      await tester.enterText(_content_, 'Draft');
      await tester.pump();
      expect(find.byKey(const Key('encrypt-button')), findsNothing);

      // Saved → visible and enabled.
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('encrypt-button')), findsOneWidget);
      expect(_encryptEnabled(tester), isTrue);
      expect(find.text('Encrypt'), findsOneWidget);

      // Editing again → disabled until the change is saved.
      await tester.enterText(_content_, 'Draft 2');
      await tester.pump();
      expect(_encryptEnabled(tester), isFalse);
      expect(find.text('Saving…'), findsWidgets);
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(_encryptEnabled(tester), isTrue);
      await _back(tester);
    });

    testWidgets('a failed save disables encryption', (tester) async {
      final stores = _Stores([_note()]);
      await _pump(tester, stores);
      await _tapText(tester, _title);
      expect(_encryptEnabled(tester), isTrue);

      stores.notes.failWrites = true;
      await tester.enterText(_content_, 'Unsaved');
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(_encryptEnabled(tester), isFalse);
      expect(find.text('Save failed'), findsOneWidget);
      expect((await stores.stored('n')).isEncrypted, isFalse);

      stores.notes.failWrites = false;
      await tester.tap(find.byKey(const Key('editor-retry')));
      await tester.pumpAndSettle();
      expect(_encryptEnabled(tester), isTrue);
      await _back(tester);
    });

    testWidgets('with auto-save off, changes must be saved first', (
      tester,
    ) async {
      final stores = _Stores([_note()]);
      await _pump(tester, stores, settings: SettingsProvider(autoSave: false));
      await _tapText(tester, _title);
      await tester.enterText(_content_, 'Changed');
      await tester.pump();
      expect(find.text('Save to encrypt'), findsOneWidget);
      expect(_encryptEnabled(tester), isFalse);

      await tester.tap(find.byKey(const Key('editor-save')));
      await tester.pumpAndSettle();
      expect(_encryptEnabled(tester), isTrue);
      await _back(tester);
    });

    testWidgets('is hidden for encrypted notes', (tester) async {
      final stores = _Stores([_note()]);
      await stores.encryptStored('n');
      await _pump(tester, stores);
      await _tapText(tester, 'Encrypted note');
      expect(find.byKey(const Key('encrypt-button')), findsNothing);
      await _menu(tester, 'Decrypt Note');
      expect(find.byKey(const Key('encrypt-button')), findsNothing);
      await _back(tester);
    });
  });

  group('Decrypt Note menu', () {
    testWidgets('is absent for plain notes and only in the menu for '
        'encrypted notes', (tester) async {
      final stores = _Stores([_note(), _note(id: 'p', title: 'Plain')]);
      await stores.encryptStored('n');
      await _pump(tester, stores);

      // Plain note: no Decrypt anywhere.
      await _tapText(tester, 'Plain');
      await _openMenu(tester);
      expect(find.text('Decrypt Note'), findsNothing);
      expect(find.text('Change color'), findsOneWidget);
      expect(find.text('Share'), findsOneWidget);
      await tester.tapAt(const Offset(10, 600));
      await tester.pumpAndSettle();
      await _back(tester);

      // Encrypted note: no visible Decrypt button or key details.
      await _tapText(tester, 'Encrypted note');
      expect(find.byKey(const Key('locked-view')), findsOneWidget);
      expect(find.textContaining('Decrypt'), findsNothing);
      expect(find.textContaining('Personal'), findsNothing);
      expect(find.textContaining('version'), findsNothing);
      await _openMenu(tester);
      expect(find.text('Decrypt Note'), findsOneWidget);
      expect(find.text('Delete'), findsOneWidget);
      await tester.tapAt(const Offset(10, 600));
      await tester.pumpAndSettle();
      await _back(tester);
    });

    testWidgets('is disabled while decrypting', (tester) async {
      final stores = _Stores([_note()]);
      await stores.encryptStored('n');
      await _pump(tester, stores);
      await _tapText(tester, 'Encrypted note');

      stores.secure.gate = Completer<void>();
      await _openMenu(tester);
      await tester.tap(find.text('Decrypt Note'));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Decrypting…'), findsOneWidget);

      // A spinner is running, so pump for fixed times instead of settling.
      await tester.tap(find.byTooltip('More options'));
      await tester.pump(const Duration(milliseconds: 500));
      final item = tester.widget<PopupMenuItem<Object?>>(
        find.ancestor(
          of: find.text('Decrypting…').last,
          matching: find.byWidgetPredicate((w) => w is PopupMenuItem),
        ),
      );
      expect(item.enabled, isFalse);
      await tester.tapAt(const Offset(10, 600));
      await tester.pump(const Duration(milliseconds: 500));

      stores.secure.gate!.complete();
      stores.secure.gate = null;
      await tester.pumpAndSettle();
      expect(find.text(_title), findsOneWidget);
      await _back(tester);
    });
  });

  group('Encrypting', () {
    testWidgets('creates a key when none exists, then encrypts', (
      tester,
    ) async {
      final stores = _Stores([_note()]);
      await _pump(tester, stores);
      await _tapText(tester, _title);
      await _tapKey(tester, 'encrypt-button');
      expect(find.text('No Encryption Key Found'), findsOneWidget);
      expect(
        find.text('Create an encryption key before encrypting this note.'),
        findsOneWidget,
      );
      await _tapKey(tester, 'no-key-create');
      await tester.enterText(
        find.byKey(const Key('key-name-field')),
        'Personal',
      );
      await _tapKey(tester, 'create-key-confirm');
      await _confirmEncrypt(tester);

      expect(find.byKey(const Key('locked-view')), findsOneWidget);
      expect(find.text('Note encrypted with “Personal”'), findsOneWidget);
      final stored = await stores.stored('n');
      final key = (await stores.metadata.getAll()).single;
      expect(stored.isEncrypted, isTrue);
      expect(stored.keyId, key.id);
      expect(stored.keyVersion, 1);
      expect(stored.title, isNot(contains('Secret')));

      await _back(tester);
      expect(find.text('Encrypted note'), findsOneWidget);
      expect(find.textContaining('Secret'), findsNothing);
    });

    testWidgets('cancelling key creation or confirmation keeps the note', (
      tester,
    ) async {
      final stores = _Stores([_note()]);
      await _pump(tester, stores);
      await _tapText(tester, _title);

      await _tapKey(tester, 'encrypt-button');
      await _tapKey(tester, 'no-key-create');
      await _tapText(tester, 'Cancel'); // cancel key creation
      expect(await stores.metadata.getAll(), isEmpty);
      expect(await stores.stored('n'), _note());

      // Cancel at the "No Encryption Key Found" dialog.
      await _tapKey(tester, 'encrypt-button');
      await _tapText(tester, 'Cancel');
      expect(await stores.stored('n'), _note());
      expect(find.byKey(const Key('locked-view')), findsNothing);
    });

    testWidgets('selects an existing key version and can cancel', (
      tester,
    ) async {
      final stores = _Stores([_note()]);
      final v1 = await stores.keys.createKey('Personal');
      await stores.keys.createNewVersion(v1.id);
      await _pump(tester, stores);
      await _tapText(tester, _title);

      await _tapKey(tester, 'encrypt-button');
      expect(find.text('Choose a key'), findsOneWidget);
      expect(find.byKey(ValueKey('pick-key-${v1.id}-v1')), findsOneWidget);
      expect(find.byKey(ValueKey('pick-key-${v1.id}-v2')), findsOneWidget);

      // Cancel at the confirmation step: nothing changes.
      await _tapKey(tester, 'pick-key-confirm');
      await _tapText(tester, 'Cancel');
      expect(await stores.stored('n'), _note());

      // Choose version 1 explicitly and encrypt.
      await _tapKey(tester, 'encrypt-button');
      await _tapKey(tester, 'pick-key-${v1.id}-v1');
      await _tapKey(tester, 'pick-key-confirm');
      expect(find.textContaining('(version 1)'), findsOneWidget);
      await _confirmEncrypt(tester);
      final stored = await stores.stored('n');
      expect(stored.keyId, v1.id);
      expect(stored.keyVersion, 1);
    });

    testWidgets('an invalid key version cannot be chosen', (tester) async {
      final stores = _Stores([_note()]);
      final key = await stores.keys.createKey('Personal');
      stores.secure.entries['hill_key_${key.id}_v1'] = '2,4,6,8';
      await _pump(tester, stores);
      await _tapText(tester, _title);
      await _tapKey(tester, 'encrypt-button');
      expect(find.textContaining('The stored key is damaged'), findsOneWidget);
      final use = tester.widget<FilledButton>(
        find.byKey(const Key('pick-key-confirm')),
      );
      expect(use.onPressed, isNull);
      await _tapText(tester, 'Cancel');
      expect((await stores.stored('n')).isEncrypted, isFalse);
    });

    testWidgets('never encrypts content that changed in storage meanwhile', (
      tester,
    ) async {
      final stores = _Stores([_note()]);
      await stores.keys.createKey('Personal');
      await _pump(tester, stores);
      await _tapText(tester, _title);
      await _tapKey(tester, 'encrypt-button');
      await _tapKey(tester, 'pick-key-confirm');

      // Another writer changes the stored note before confirmation.
      final changed = _note(content: 'Changed elsewhere');
      await stores.notes.updateNote(changed);
      await _confirmEncrypt(tester);

      expect(
        find.text('The note has unsaved changes. Save it, then try again.'),
        findsOneWidget,
      );
      expect(await stores.stored('n'), changed);
      expect(find.byKey(const Key('locked-view')), findsNothing);
    });

    testWidgets('a failed encryption keeps the plain note', (tester) async {
      final stores = _Stores([_note()]);
      final key = await stores.keys.createKey('Personal');
      await _pump(tester, stores);
      await _tapText(tester, _title);
      await _tapKey(tester, 'encrypt-button');
      await _tapKey(tester, 'pick-key-confirm');
      stores.secure.entries.remove('hill_key_${key.id}_v1');
      await _confirmEncrypt(tester);

      expect(find.text('Could not encrypt'), findsOneWidget);
      await _tapText(tester, 'Close');
      expect(await stores.stored('n'), _note());
      expect(find.text(_content), findsOneWidget);
    });
  });

  group('Decrypting and editing', () {
    testWidgets('decrypt (read only) → Edit → encrypt again → reopen', (
      tester,
    ) async {
      final stores = _Stores([_note()]);
      final v1 = await stores.encryptStored('n');
      final before = await stores.stored('n');
      await _pump(tester, stores);

      await _tapText(tester, 'Encrypted note');
      await _menu(tester, 'Decrypt Note');
      expect(find.text(_title), findsOneWidget);
      expect(find.text(_content), findsOneWidget);
      expect(find.text('Decrypted · read only'), findsOneWidget);
      expect(await stores.stored('n'), before);
      expect(
        tester.widget<TextField>(_content_).readOnly,
        isTrue,
        reason: 'read only until Edit is chosen',
      );

      await _menu(tester, 'Edit');
      expect(tester.widget<TextField>(_content_).readOnly, isFalse);
      await tester.enterText(_title_, '$_title v2');
      await tester.enterText(_content_, '$_content\nনতুন লাইন');
      await tester.pump(const Duration(seconds: 2));
      expect(await stores.stored('n'), before, reason: 'never auto-saved');

      await tester.pageBack();
      await tester.pumpAndSettle();
      await _tapKey(tester, 'encrypt-and-save');
      // The note's own key version is preselected.
      expect(find.text('Choose a key'), findsOneWidget);
      await _tapKey(tester, 'pick-key-confirm');
      expect(find.textContaining('(version 1)'), findsOneWidget);
      await _confirmEncrypt(tester);
      expect(find.text('Decrypted note'), findsNothing, reason: 'closed');

      final stored = await stores.stored('n');
      expect(stored.keyId, v1.id);
      expect(stored.keyVersion, 1);
      final text = await stores.encryption.decrypt(stored);
      expect(text.title, '$_title v2');
      expect(text.content, '$_content\nনতুন লাইন');

      await _tapText(tester, 'Encrypted note');
      await _menu(tester, 'Decrypt Note');
      expect(find.text('$_content\nনতুন লাইন'), findsOneWidget);
      await _back(tester); // no changes: closes without asking
      expect(find.text('Encrypted note'), findsOneWidget);
    });

    testWidgets('re-encrypting with a different key version', (tester) async {
      final stores = _Stores([_note()]);
      final v1 = await stores.encryptStored('n');
      final v2 = await stores.keys.createNewVersion(v1.id);
      await _pump(tester, stores);

      await _tapText(tester, 'Encrypted note');
      await _menu(tester, 'Decrypt Note');
      await _menu(tester, 'Edit');
      await tester.enterText(_content_, 'Rotated');
      await tester.tap(find.byKey(const Key('editor-save')));
      await tester.pumpAndSettle();
      await _tapKey(tester, 'encrypt-and-save');
      await _tapKey(tester, 'pick-key-${v2.id}-v2');
      await _tapKey(tester, 'pick-key-confirm');
      await _confirmEncrypt(tester);

      final stored = await stores.stored('n');
      expect(stored.keyVersion, 2);
      expect((await stores.encryption.decrypt(stored)).content, 'Rotated');
      expect(find.byKey(const Key('locked-view')), findsOneWidget);
    });

    testWidgets('cancelling re-encryption or editing keeps the stored note', (
      tester,
    ) async {
      final stores = _Stores([_note()]);
      await stores.encryptStored('n');
      final before = await stores.stored('n');
      await _pump(tester, stores);

      await _tapText(tester, 'Encrypted note');
      await _menu(tester, 'Decrypt Note');
      await _menu(tester, 'Edit');
      await tester.enterText(_content_, 'Throw this away');

      // Cancel re-encryption at the key picker: still editing.
      await tester.pageBack();
      await tester.pumpAndSettle();
      await _tapKey(tester, 'encrypt-and-save');
      await _tapText(tester, 'Cancel');
      expect(find.text('Throw this away'), findsOneWidget);
      expect(await stores.stored('n'), before);

      // Discard the edits.
      await tester.pageBack();
      await tester.pumpAndSettle();
      await _tapText(tester, 'Discard changes');
      expect(await stores.stored('n'), before);
      expect(find.text('Encrypted note'), findsOneWidget);
    });

    testWidgets('a failed re-encryption keeps the previous encrypted note', (
      tester,
    ) async {
      final stores = _Stores([_note()]);
      final key = await stores.encryptStored('n');
      final before = await stores.stored('n');
      await _pump(tester, stores);

      await _tapText(tester, 'Encrypted note');
      await _menu(tester, 'Decrypt Note');
      await _menu(tester, 'Edit');
      await tester.enterText(_content_, 'Edited');
      await tester.tap(find.byKey(const Key('editor-save')));
      await tester.pumpAndSettle();
      await _tapKey(tester, 'encrypt-and-save');
      await _tapKey(tester, 'pick-key-confirm');
      stores.notes.failWrites = true; // the database write fails
      await _confirmEncrypt(tester);

      expect(find.text('Could not encrypt'), findsOneWidget);
      await _tapText(tester, 'Close');
      expect(await stores.stored('n'), before);
      expect(find.text('Edited'), findsOneWidget, reason: 'edits kept');
      expect(key.version, 1);
    });

    testWidgets('a decrypted note can be saved as plain text', (tester) async {
      final stores = _Stores([_note()]);
      await stores.encryptStored('n');
      await _pump(tester, stores);

      await _tapText(tester, 'Encrypted note');
      await _menu(tester, 'Decrypt Note');
      await _menu(tester, 'Edit');
      await tester.enterText(_title_, 'Public title');
      await tester.enterText(_content_, 'Now public');
      await tester.tap(find.byKey(const Key('editor-save')));
      await tester.pumpAndSettle();
      await _tapText(tester, 'Save as plain text');
      await tester.tap(find.widgetWithText(TextButton, 'Save as plain text'));
      await tester.pumpAndSettle();

      final stored = await stores.stored('n');
      expect(stored.isEncrypted, isFalse);
      expect(stored.keyId, isNull);
      expect(stored.keyVersion, isNull);
      expect(stored.cipherFormat, isNull);
      expect(stored.title, 'Public title');
      expect(stored.content, 'Now public');
      expect(find.text('Edit note'), findsOneWidget);
      // A plain note again: Encrypt is offered at the bottom.
      expect(find.byKey(const Key('encrypt-button')), findsOneWidget);
    });

    testWidgets('Lock note hides the text again without changes', (
      tester,
    ) async {
      final stores = _Stores([_note()]);
      await stores.encryptStored('n');
      final before = await stores.stored('n');
      await _pump(tester, stores);
      await _tapText(tester, 'Encrypted note');
      await _menu(tester, 'Decrypt Note');
      await _menu(tester, 'Lock note');
      expect(find.byKey(const Key('locked-view')), findsOneWidget);
      expect(find.text(_content), findsNothing);
      expect(await stores.stored('n'), before);
    });

    testWidgets('a missing key is reported and the note is unchanged', (
      tester,
    ) async {
      final stores = _Stores([_note()]);
      final key = await stores.encryptStored('n');
      await stores.metadata.delete(key.id, key.version);
      stores.secure.entries.clear();
      final before = await stores.stored('n');
      await _pump(tester, stores);

      expect(find.text('Key unavailable on this device'), findsOneWidget);
      await _tapText(tester, 'Encrypted note');
      await _menu(tester, 'Decrypt Note');
      expect(find.text('Could not decrypt'), findsOneWidget);
      expect(find.textContaining('has not been changed'), findsOneWidget);
      await _tapText(tester, 'Close');
      expect(await stores.stored('n'), before);
      expect(find.byKey(const Key('locked-view')), findsOneWidget);
    });

    testWidgets('a damaged key is reported and the note is unchanged', (
      tester,
    ) async {
      final stores = _Stores([_note()]);
      final key = await stores.encryptStored('n');
      stores.secure.entries['hill_key_${key.id}_v1'] = '2,4,6,8';
      final before = await stores.stored('n');
      await _pump(tester, stores);
      await _tapText(tester, 'Encrypted note');
      await _menu(tester, 'Decrypt Note');
      expect(find.textContaining('The stored key is damaged'), findsOneWidget);
      await _tapText(tester, 'Close');
      expect(await stores.stored('n'), before);
    });

    testWidgets('an older version still decrypts its notes', (tester) async {
      final stores = _Stores([_note()]);
      final v1 = await stores.encryptStored('n');
      await stores.keys.createNewVersion(v1.id);
      await _pump(tester, stores);
      await _tapText(tester, 'Encrypted note');
      await _menu(tester, 'Decrypt Note');
      expect(find.text(_content), findsOneWidget);
      await _back(tester);
    });

    testWidgets('the colour of an encrypted note can change without '
        'decrypting', (tester) async {
      final stores = _Stores([_note()]);
      await stores.encryptStored('n');
      final before = await stores.stored('n');
      await _pump(tester, stores);

      await _tapText(tester, 'Encrypted note');
      await _menu(tester, 'Change color');
      await tester.tap(find.byKey(const ValueKey('note-color-Green')));
      await tester.pumpAndSettle();
      final after = await stores.stored('n');
      expect(after.color, 0xFFDDF3E4);
      expect(after.title, before.title);
      expect(after.content, before.content);
      expect(after.isEncrypted, isTrue);
    });
  });

  group('Key Management', () {
    testWidgets('creates new versions and blocks deleting a used version', (
      tester,
    ) async {
      final stores = _Stores([_note()]);
      final key = await stores.encryptStored('n');
      await _pump(tester, stores);

      await _openMenu(tester);
      await _tapText(tester, 'Key Management');
      expect(find.text('Personal'), findsOneWidget);
      expect(find.text('Used by 1 note', findRichText: true), findsNothing);
      expect(find.textContaining('Used by 1 note'), findsOneWidget);

      await _tapKey(tester, 'new-version-${key.id}');
      expect(find.text('Create a new version?'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, 'Create version'));
      await tester.pumpAndSettle();
      expect(find.text('Version 2'), findsOneWidget);
      expect(find.text('Version 1'), findsOneWidget);
      expect(find.textContaining('2 versions'), findsOneWidget);
      final versions = await stores.metadata.getVersions(key.id);
      expect(versions.first.isActive, isTrue);
      expect(versions.last.isActive, isFalse);

      // Version 1 is used by the note: deletion is refused.
      await tester.tap(
        find.descendant(
          of: find.byKey(ValueKey('key-version-${key.id}-v1')),
          matching: find.byTooltip('Version options'),
        ),
      );
      await tester.pumpAndSettle();
      await _tapText(tester, 'Delete version');
      await tester.tap(find.widgetWithText(TextButton, 'Delete'));
      await tester.pumpAndSettle();
      expect(find.text('Key version is in use'), findsOneWidget);
      await _tapText(tester, 'Close');
      expect(await stores.metadata.getVersion(key.id, 1), isNotNull);

      // Version 2 is unused: it can be deleted after confirmation, and
      // version 1 remains.
      await tester.tap(
        find.descendant(
          of: find.byKey(ValueKey('key-version-${key.id}-v2')),
          matching: find.byTooltip('Version options'),
        ),
      );
      await tester.pumpAndSettle();
      await _tapText(tester, 'Delete version');
      await tester.tap(find.widgetWithText(TextButton, 'Delete'));
      await tester.pumpAndSettle();
      expect(find.text('Version 2'), findsNothing);
      expect(find.text('Version 1'), findsOneWidget);
      expect(stores.secure.entries.keys, ['hill_key_${key.id}_v1']);
    });
  });
}
