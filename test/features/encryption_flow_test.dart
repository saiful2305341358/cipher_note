// End-to-end UI tests for encrypting, decrypting and editing notes.

import 'package:cipher_note/app.dart';
import 'package:cipher_note/data/models/key_metadata.dart';
import 'package:cipher_note/data/models/note_model.dart';
import 'package:cipher_note/data/repositories/key_metadata_repository.dart';
import 'package:cipher_note/data/repositories/note_repository.dart';
import 'package:cipher_note/data/repositories/secure_key_store.dart';
import 'package:cipher_note/features/encryption/data/key_service.dart';
import 'package:cipher_note/features/encryption/data/note_encryption_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

const _title = 'Secret plan';
const _content = 'Meet at ১০টা, room 5.\nআমি আসছি!';

class _Stores {
  _Stores([List<Note> notes = const []])
    : notes = InMemoryNoteRepository(notes);

  final InMemoryNoteRepository notes;
  final metadata = InMemoryKeyMetadataRepository();
  final secure = InMemorySecureKeyStore();

  KeyService get keys =>
      KeyService(metadata: metadata, secureStore: secure, notes: notes);
  NoteEncryptionService get encryption => NoteEncryptionService(keys: keys);

  Future<Note> stored(String id) async => (await notes.getNoteById(id))!;

  /// Encrypts a stored note outside the UI (test setup).
  Future<KeyMetadata> encryptStored(String id) async {
    final key = await keys.createKey('Personal');
    final note = await stored(id);
    await notes.updateNote(
      await encryption.encrypt(
        note: note,
        title: note.title,
        content: note.content,
        key: key,
      ),
    );
    return key;
  }
}

Note _note() {
  final time = DateTime(2026, 11, 3, 16, 49);
  return Note(
    id: 'n',
    title: _title,
    content: _content,
    color: 0xFFFFF3BF,
    createdAt: time,
    updatedAt: time,
  );
}

Future<void> _pump(WidgetTester tester, _Stores stores) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    CipherNoteApp(
      noteRepository: stores.notes,
      keyRepository: stores.metadata,
      secureKeyStore: stores.secure,
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

Future<void> _back(WidgetTester tester) async {
  await tester.pageBack();
  await tester.pumpAndSettle();
}

Finder get _content_ => find.byKey(const Key('editor-content'));

void main() {
  testWidgets('encrypt with a new key, then decrypt, edit and re-encrypt', (
    tester,
  ) async {
    final stores = _Stores([_note()]);
    await _pump(tester, stores);

    // 1. Encrypt a plain note; no key exists yet, so create one.
    await _tapText(tester, _title);
    await _tapKey(tester, 'encrypt-button');
    expect(find.text('No encryption key yet'), findsOneWidget);
    await _tapKey(tester, 'no-key-create');
    await tester.enterText(find.byKey(const Key('key-name-field')), 'Personal');
    await _tapKey(tester, 'create-key-confirm');
    expect(find.text('Encrypt this note?'), findsOneWidget);
    expect(find.textContaining('educational cipher'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Encrypt'));
    await tester.pumpAndSettle();

    expect(find.text('This note is encrypted'), findsOneWidget);
    expect(find.text('Key: “Personal” · version 1'), findsOneWidget);
    expect(find.text(_title), findsNothing);
    expect(find.text(_content), findsNothing);
    var stored = await stores.stored('n');
    expect(stored.isEncrypted, isTrue);
    expect(stored.title, isNot(contains('Secret')));
    expect(stored.content, isNot(contains('Meet')));
    final key = (await stores.metadata.getAll()).single;
    expect(stored.keyId, key.id);
    expect(stored.keyVersion, 1);

    // 2. The home list shows a generic label, never the title.
    await _back(tester);
    expect(find.text('Encrypted note'), findsOneWidget);
    expect(find.text('Tap to decrypt'), findsOneWidget);
    expect(find.textContaining('Secret'), findsNothing);

    // 3. Search does not reveal or match it.
    await tester.tap(find.byTooltip('Search'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('search-field')), 'Secret');
    await tester.pump();
    expect(find.text('No results'), findsOneWidget);
    expect(
      find.textContaining('Encrypted notes are not searched'),
      findsOneWidget,
    );
    await _back(tester);

    // 4. Decrypt, edit, and encrypt again with the same key.
    await _tapText(tester, 'Encrypted note');
    await _tapKey(tester, 'decrypt-button');
    expect(find.text(_title), findsOneWidget);
    expect(find.text(_content), findsOneWidget);
    expect(find.byKey(const Key('unlocked-banner')), findsOneWidget);
    expect(
      await stores.stored('n'),
      stored,
      reason: 'decrypting does not change the stored note',
    );

    await tester.enterText(_content_, '$_content\nনতুন লাইন');
    await tester.pump(const Duration(seconds: 2));
    expect(
      await stores.stored('n'),
      stored,
      reason: 'decrypted edits are never auto-saved',
    );
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Save changes?'), findsOneWidget);
    await _tapKey(tester, 'encrypt-and-save');
    expect(find.text('Choose a key'), findsOneWidget);
    await _tapKey(tester, 'pick-key-confirm');
    await tester.tap(find.widgetWithText(TextButton, 'Encrypt'));
    await tester.pumpAndSettle();
    expect(find.text('Decrypted note'), findsNothing, reason: 'editor closed');

    stored = await stores.stored('n');
    expect(stored.isEncrypted, isTrue);
    final latest = await stores.encryption.decrypt(stored);
    expect(latest.title, _title);
    expect(latest.content, '$_content\nনতুন লাইন');

    // 5. Reopen and decrypt again: the latest text is restored.
    await _tapText(tester, 'Encrypted note');
    await _tapKey(tester, 'decrypt-button');
    expect(find.text('$_content\nনতুন লাইন'), findsOneWidget);
    await _back(tester); // no changes: leaves without asking
    expect(find.text('Encrypted note'), findsOneWidget);
  });

  testWidgets('discarding edits keeps the stored encrypted note', (
    tester,
  ) async {
    final stores = _Stores([_note()]);
    await stores.encryptStored('n');
    final before = await stores.stored('n');
    await _pump(tester, stores);

    await _tapText(tester, 'Encrypted note');
    await _tapKey(tester, 'decrypt-button');
    await tester.enterText(_content_, 'Throw this away');
    await tester.pageBack();
    await tester.pumpAndSettle();
    await _tapText(tester, 'Discard changes');

    expect(await stores.stored('n'), before);
    expect(find.text('Encrypted note'), findsOneWidget);
  });

  testWidgets('a decrypted note can be saved as plain text', (tester) async {
    final stores = _Stores([_note()]);
    await stores.encryptStored('n');
    await _pump(tester, stores);

    await _tapText(tester, 'Encrypted note');
    await _tapKey(tester, 'decrypt-button');
    await tester.enterText(_content_, 'Now public');
    await tester.tap(find.byKey(const Key('editor-save')));
    await tester.pumpAndSettle();
    await _tapText(tester, 'Save as plain text');
    // Confirmation dialog.
    await tester.tap(find.widgetWithText(TextButton, 'Save as plain text'));
    await tester.pumpAndSettle();

    final stored = await stores.stored('n');
    expect(stored.isEncrypted, isFalse);
    expect(stored.keyId, isNull);
    expect(stored.keyVersion, isNull);
    expect(stored.cipherFormat, isNull);
    expect(stored.title, _title);
    expect(stored.content, 'Now public');
    expect(find.text('Edit note'), findsOneWidget, reason: 'plain mode now');
  });

  testWidgets('a note whose key is missing shows it and stays unchanged', (
    tester,
  ) async {
    final stores = _Stores([_note()]);
    final key = await stores.encryptStored('n');
    // Simulate a lost key: metadata and secure value gone.
    await stores.metadata.delete(key.id);
    stores.secure.entries.clear();
    final before = await stores.stored('n');
    await _pump(tester, stores);

    expect(find.text('Key unavailable on this device'), findsOneWidget);
    await _tapText(tester, 'Encrypted note');
    expect(
      find.text('The key for this note is not available on this device.'),
      findsOneWidget,
    );
    await _tapKey(tester, 'decrypt-button');
    expect(find.text('Could not decrypt'), findsOneWidget);
    expect(find.textContaining('has not been changed'), findsOneWidget);
    await _tapText(tester, 'Close');
    expect(await stores.stored('n'), before);
  });

  testWidgets('a key used by a note cannot be deleted from Key Management', (
    tester,
  ) async {
    final stores = _Stores([_note()]);
    await stores.encryptStored('n');
    await _pump(tester, stores);

    await tester.tap(find.byTooltip('More options'));
    await tester.pumpAndSettle();
    await _tapText(tester, 'Key Management');
    expect(find.text('Personal'), findsOneWidget);
    await tester.tap(find.byTooltip('Key options'));
    await tester.pumpAndSettle();
    await _tapText(tester, 'Delete');
    await tester.tap(find.widgetWithText(TextButton, 'Delete'));
    await tester.pumpAndSettle();

    expect(find.text('Key is in use'), findsOneWidget);
    expect(
      find.textContaining('1 encrypted note uses this key.'),
      findsOneWidget,
    );
    await _tapText(tester, 'Close');
    expect(await stores.metadata.getAll(), hasLength(1));
    expect(stores.secure.entries, hasLength(1));
  });

  testWidgets('the colour of an encrypted note can change without '
      'decrypting', (tester) async {
    final stores = _Stores([_note()]);
    await stores.encryptStored('n');
    final before = await stores.stored('n');
    await _pump(tester, stores);

    await _tapText(tester, 'Encrypted note');
    await tester.tap(find.byTooltip('More options'));
    await tester.pumpAndSettle();
    await _tapText(tester, 'Change color');
    await tester.tap(find.byKey(const ValueKey('note-color-Green')));
    await tester.pumpAndSettle();
    final after = await stores.stored('n');
    expect(after.color, 0xFFDDF3E4);
    expect(after.title, before.title);
    expect(after.content, before.content);
    expect(after.isEncrypted, isTrue);
  });
}
