# Phase 2 — Persistent Local Storage

> **Phase 2 provides no encryption or cryptographic protection.** Notes are
> stored on the device as normal, readable text. The Hill Cipher, key
> generation, encryption and decryption are planned for Phase 3.

## 1. Overview

Phase 1 kept notes and settings in memory only (`InMemoryNoteRepository`
was the only implementation, so there was no on-disk data to migrate).
Phase 2 adds a local Hive database behind the existing repository
interfaces. The Phase 1 screens, navigation and design are unchanged apart
from save/loading/error feedback.

```
Screens (home, editor, search, settings, key management)
   │  Provider
NotesProvider · SettingsProvider · KeyProvider
   │
NoteRepository · SettingsRepository · KeyMetadataRepository   (interfaces)
   │
HiveNoteRepository · HiveSettingsRepository · HiveKeyMetadataRepository
   │
HiveService (opens boxes, registers adapters, runs migrations)
   │
Hive CE  →  <app support dir>/cipher_note_db/   (IndexedDB on web)
```

Widgets never touch Hive. Repositories receive typed boxes from
`HiveService`, which only exists once every box is open.

## 2. Package choice

| Package | Version | Why |
|---|---|---|
| `hive_ce` | ^2.24.0 | Maintained community edition of Hive. The original `hive` (2.2.3, 2022) and `hive_flutter` (2021) are no longer maintained. |
| `path_provider` | ^2.1.5 | Finds the app's private support directory. Used instead of `hive_ce_flutter`, which would also pull in native C build hooks. |

No code generation is used: the three `TypeAdapter`s are written by hand
(`lib/core/database/hive_adapters.dart`), so `hive_ce_generator` and
`build_runner` are not needed. `provider` was already in use. No `uuid`
package (ids come from `IdGenerator`, using `Random.secure`). No
`flutter_secure_storage` yet (see section 7).

## 3. Boxes

| Box | Type | Contents |
|---|---|---|
| `notes` | `Box<Note>` | One record per note, keyed by note id |
| `settings` | `Box<AppSettings>` | One record under key `app_settings` |
| `key_metadata` | `Box<KeyMetadata>` | Key metadata records, keyed by id. **No key material.** |
| `app_metadata` | `Box<dynamic>` | `schema_version`, `created_at`, `last_migrated_at` |

Type ids: `Note` = 1, `KeyMetadata` = 2, `AppSettings` = 3. Box names,
type ids and field indexes are permanent (`DatabaseConstants`).

## 4. Data models

**Note** (`lib/data/models/note_model.dart`)

| Index | Field | Notes |
|---|---|---|
| 0 | `id` | Unique, generated once, never changes |
| 1 | `title` | Any Unicode (English, Bangla, emoji, line breaks) |
| 2 | `content` | Same |
| 3 | `isEncrypted` | Always `false` in Phase 2 |
| 4 | `color` | ARGB value from the palette |
| 5 | `createdAt` | Never changes after creation |
| 6 | `updatedAt` | Set on every real change |
| 7 | `keyId` | Future: metadata id of the key; always `null` now |
| 8 | `keyVersion` | Future: key version used; always `null` now |

Timestamps are stored as UTC microseconds and read back as local time.

**AppSettings**: `themeMode`, `viewMode`, `sortOrder`, `defaultNoteColor`,
`showContentPreview`, `autoSave` (enums stored by name).

**KeyMetadata**: `id`, `name` (display label, 1–40 characters),
`version` (≥ 1), `algorithm` (`hill-2x2`), `createdAt`, `isActive`.

## 5. Repositories

`NoteRepository`: `getAllNotes`, `getNoteById`, `createNote`, `updateNote`,
`deleteNote`, `deleteAllNotes`, `searchNotes`.

- `createNote` refuses an existing id (`DuplicateRecordException`), and
  `updateNote` refuses a missing id (`RecordNotFoundException`), so an edit
  can never create a duplicate record.
- Storage errors become `StorageException` with a user-facing message.
- Search rules live in `NoteSearch` and are shared by the repositories and
  `NotesProvider`: title or content contains the query, case-insensitive
  for English, exact for Bangla, title matches first.

`NotesProvider` writes to the repository first and only then updates its
in-memory list, so the UI never shows a change that was not stored.

## 6. Autosave (note editor)

- Title, content and colour changes are tracked against the last
  successfully saved values. Cursor movement is ignored.
- With auto-save on (default), a save runs 600 ms after typing pauses
  (debounce). Several quick edits cause one write.
- Saves run one at a time through a chain, so writes never overlap and a
  new note is created exactly once; later saves update it.
- Pending changes are saved: when leaving the editor (back button, system
  back), when the app goes to the background, and, as a safety net, if the
  editor is removed some other way.
- Status line: **Saving…**, **Saved · Edited …**, **Unable to save**
  (with Retry). "Saved" appears only after the write succeeds.
- If saving fails when leaving, the user chooses **Try again**, **Keep
  editing** or **Discard changes**. Changes are never dropped silently.
- With auto-save off, leaving asks **Save / Discard / Keep editing**.
- Delete waits for any running save, deletes, and only then closes the
  editor. A failed delete shows a message and keeps the note.

## 7. Key management foundation

- `KeyMetadataRepository` (Hive + in-memory) supports create, read,
  update, delete and "active key" lookup.
- Nothing creates real metadata yet, because key generation is Phase 3.
  The Key Management screen still offers its clearly labelled **demo**
  preview; the demo record is held in memory only and never saved.
- `SecureKeyStore` (`lib/data/repositories/secure_key_store.dart`) is an
  interface for where key material will live (platform secure storage,
  e.g. `flutter_secure_storage`). It has no implementation and is not
  called anywhere.
- A test reads the raw stored record to confirm only the six descriptive
  fields are written to Hive.

## 8. Error handling

| Situation | Behaviour |
|---|---|
| Database cannot be opened at startup | `StartupErrorApp`: plain message, "Nothing has been deleted", **Try again** |
| Notes fail to load | Home shows an error with **Try again** |
| Save fails | Status "Unable to save", Retry, and a choice before leaving |
| Delete fails | Snackbar message, note kept |
| Settings fail to save | Change still applies; banner says it may reset on restart |
| Settings fail to load | Defaults are used; notes still work |
| Malformed or legacy record | Adapter fills safe defaults; an empty id is repaired from the box key |

Exceptions (`AppException` and subclasses) carry user-facing messages that
never include note text. `ErrorReporter` prints technical details only in
debug builds and never note contents or key material.

## 9. Versioning and migration

- `app_metadata.schema_version` records the schema version (currently 1).
- `DatabaseMigrator` runs steps `n` (from `n-1` to `n`) in order at
  startup, saving the version after each step.
- A failing step stops startup with an error screen and leaves the stored
  version unchanged, so it runs again next time. No data is deleted.
- A database written by a newer app version is refused, not modified.
- Adapters store `field index → value` maps and ignore unknown fields, so
  adding a field normally needs no migration: old records get defaults.
- To change the schema: add the field with a new index (never reuse one),
  give it a default in the adapter, and if existing data must be converted,
  increase `DatabaseConstants.schemaVersion` and add a step.

## 10. Running checks

```bash
flutter pub get
dart format lib test
flutter analyze
flutter test
flutter build apk --debug
```

Database tests use a fresh temporary directory per test
(`test/helpers/hive_test_utils.dart`) and never touch real app data.

| Test file | Covers |
|---|---|
| `test/database/hive_note_repository_test.dart` | CRUD, duplicates, search (English, Bangla, mixed), Unicode/emoji/line breaks, timestamps, restart persistence, legacy records |
| `test/database/database_setup_test.dart` | Box opening, schema version, newer-version refusal, migration order and failure, AppInitializer restart, settings persistence, key metadata CRUD, no key material stored |
| `test/features/editor_persistence_test.dart` | Debounce, title/content autosave, single create, flush on leave and on background, save/delete/load failures, settings save errors, startup retry |
| `test/features/providers_test.dart`, `test/data/note_repository_test.dart`, `test/widget_test.dart` | Providers, models and Phase 1 UI flows |

## 11. Known limitations

- `flutter build apk --debug` succeeds (Android SDK 36, version 1.1.0+2),
  but the app has not yet been run on an Android device or emulator. Tests
  ran on the Dart VM, and real persistence was checked in a Flutter web
  build in Chromium (IndexedDB) across page reloads.
- Hive data is not encrypted at rest.
- There is no backup, export or import yet.
- `deleteAllNotes` exists in the repository and provider but has no UI.

## 12. Deferred to Phase 3

Hill Cipher (2×2 matrix, modular arithmetic and inverse), key generation
and validation, storing key material via `SecureKeyStore`, encrypting and
decrypting notes (`isEncrypted`, `keyId`, `keyVersion`), and any password,
PIN, key rotation or recovery features.
