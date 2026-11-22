# Phase 4 — Encryption Workflow, Key Versions & UI Refinement

> The Hill Cipher remains a classical, educational cipher, not secure
> encryption (see `PHASE_3_IMPLEMENTATION.md`). Phase 4 changes the
> workflow, UI and key handling; the cipher itself is unchanged.

## Status

| Area | Status |
|---|---|
| Bottom Encrypt button tied to the real save state | Implemented |
| Decrypt only in the ⋮ menu (no visible Decrypt button) | Implemented |
| Decrypt → read only → Edit → encrypt again / save as plain text | Implemented |
| Key validation with explicit states | Implemented |
| Key versions (new version, exact-version use, per-version delete) | Implemented |
| Stale/concurrent-change protection before encrypting | Implemented |
| Bulk re-encryption of old notes to a new version | **Deferred** |
| Renaming keys, key backup/export | **Deferred** |

## 1. Encryption workflow

1. The user writes a plain note; it is auto-saved (or saved with ✓).
2. The **Encrypt** button appears at the bottom of the editor once the note
   exists in storage (see §3).
3. Tapping it: any pending auto-save is flushed; the note is re-read from
   storage and must be plain and identical to the text on screen.
4. No keys → **"No Encryption Key Found"** (*Create Key* / *Cancel*).
   Otherwise the key picker lists every key version (name, version,
   created date, active). Each version is validated; invalid ones are
   greyed out with the reason and cannot be chosen.
5. **"Encrypt This Note?"** confirmation (names the key and version and
   repeats the security warning).
6. The note is re-read once more (never encrypt stale content), title and
   content are encrypted with the Phase 3 `NoteEncryptionService`, and the
   result is stored in one write (`NotesProvider.replaceNote`).
7. On success the editor switches to the locked view and shows "Note
   encrypted with …". On any failure the plain note is unchanged and an
   error is shown. Success is never reported before the write succeeds.

## 2. Decryption workflow

1. An encrypted note opens in a locked view that only says *Encrypted note*
   (no key details, no instructions, no Decrypt button).
2. ⋮ → **Decrypt Note** (only shown for a locked encrypted note; disabled
   and labelled *Decrypting…* while it runs).
3. The note's exact `keyId` + `keyVersion` are loaded and validated
   (§5); the cipher format must be supported. No other key is ever tried.
4. Title and content are decrypted; padding and UTF-8 are validated. As the
   Hill Cipher has no authentication, a wrong key is not always detectable.
5. The text is shown **read only**; the stored ciphertext is untouched. On
   failure an error explains the problem and says the stored note has not
   been changed.

## 3. Encrypt button visibility

| Note state | Button |
|---|---|
| New note not yet saved | hidden |
| Saving / auto-save pending | disabled, "Saving…" |
| Unsaved changes, auto-save off | disabled, "Save to encrypt" |
| Last save failed | disabled, "Save failed" |
| Saved plain note | enabled, "Encrypt" |
| Encryption running | disabled, spinner "Encrypting…" |
| Encrypted note (locked or decrypted) | hidden |
| Keyboard open | hidden (keeps the writing area clear) |

A re-entry guard covers the whole flow, so double taps cannot start two
encryptions.

## 4. ⋮ menu by state

| Plain | Locked (encrypted) | Decrypted (read only) | Editing decrypted |
|---|---|---|---|
| Change color | **Decrypt Note** | Edit | Copy |
| Share | — | Copy | Share |
| Note information | Change color | Share | — |
| Delete | Note information | — | Lock note |
| | Delete | Lock note | — |
| | | — | Change color · Note information · Delete |
| | | Change color · Note information · Delete | |

*Lock note* hides the decrypted text again (asking first if there are
unsaved edits); the stored note is not changed. Actions that would conflict
with a running operation are disabled.

## 5. Key validation

`KeyService.loadKey(id, version)` / `validate(id, version)` check, in order:

1. metadata for exactly this id **and** version exists (id/version match);
2. the algorithm is supported (`hill-2x2`);
3. the secure-storage entry `hill_key_<id>_v<version>` exists and can be
   read;
4. it holds exactly four values, each 0–255;
5. the determinant is odd (invertible mod 256) and the inverse matrix can be
   computed.

`validate` returns a `KeyValidationStatus`: `valid`, `missingMetadata`,
`unsupportedAlgorithm`, `missingMaterial`, `invalidMatrix`,
`storageFailure`, each with a short user-facing message that never
contains key values. Encryption and decryption call `loadKey` again, so a
key is validated right before every use.

## 6. Key versions

- A **logical key** has one id and name. Each **version** (1, 2, 3 …) has:
  its own random matrix in secure storage (`hill_key_<id>_v<n>`) and its own
  Hive record stored under `<id>@v<n>` (schema v3).
- **New version** (Key Management → *New version*): checks that no material
  or record exists for the next number (never overwrites), generates a new
  matrix, stores it, stores the metadata, then makes it the only active
  version. A failure removes anything partially written.
- **Old versions are kept.** Notes always record and use their exact
  version; a version-1 note is never decrypted with version 3.
- **Active version**: exactly one version of all keys; new encryption
  preselects it. Any version can be set active.
- **Deletion is per version.** A version used by any encrypted note cannot
  be deleted (the dialog explains how to free it). An unused version is
  deleted after confirmation; other versions of the key stay. If the active
  version is deleted, the newest remaining version of that key becomes
  active.
- Key Management shows each key with its versions, creation dates, the
  active badge and how many notes use each version.
- Existing notes are **not** re-encrypted automatically when a new version
  is created (deferred; they keep working with their own version).

## 7. Encrypted-note editing

Decrypt (read only) → ⋮ **Edit** → change title/content → ✓ or back:

- **Encrypt & save**: key picker with the note's current version
  preselected (any other valid version can be chosen) → confirmation →
  encrypt the edited text → one write.
- **Save as plain text** (with confirmation): stores readable text and
  clears `isEncrypted`, `keyId`, `keyVersion` and `cipherFormat`.
- **Discard changes** (back only): nothing is written.
- **Keep editing**.

Decrypted text is never auto-saved. Before writing, the stored note is
re-read and must be the same encrypted record that was decrypted;
otherwise the save is refused ("The stored note changed…").

## 8. Data integrity

| Situation | Result |
|---|---|
| Encryption fails (key, cipher, or database) | plain note unchanged |
| Decryption fails | ciphertext unchanged |
| Re-encryption fails | previous encrypted note unchanged; edits kept on screen |
| Key creation / new version fails | no partial metadata or material left |
| Stored note changed during the flow | operation refused |
| Plain-text conversion | all encryption fields cleared in the same write |

Storage-level changes: key metadata records renamed to `<id>@v<version>`
by migration step 3 (each record is written under its new name before
the old entry is removed; nothing is deleted). The `Note` model is
unchanged.

## 9. Error handling

Covered with user-facing messages (no stack traces, no key values): note
not saved / save pending / save failed, key unavailable, missing version,
unsupported algorithm, invalid or damaged key, secure-storage failure,
encryption failure, invalid ciphertext, invalid padding, invalid UTF-8,
database write failure, concurrent modification, re-encryption failure,
deletion blocked by references.

## 10. Tests

```bash
flutter pub get
flutter analyze
flutter test
flutter build apk --debug
```

| File | Phase 4 coverage |
|---|---|
| `test/features/encryption_flow_test.dart` | Encrypt button states (unsaved, saving, saved, failed, auto-save off, encrypted); Decrypt only in menu and disabled while running; no-key flow, cancel key creation/confirmation; choosing a version; invalid versions not selectable; stale-content refusal; failed encryption; decrypt → Edit → re-encrypt → reopen; different version; cancel re-encryption and discard; failed re-encryption; save as plain text; Lock note; missing/damaged keys; old versions; colour; Key Management versions and deletion rules |
| `test/encryption/key_versions_test.dart` | version numbering, separate secure entries, no overwrite, active handling, exact-version decryption, missing version, per-version deletion rules, every validation state, restart with Hive, v2→v3 migration |
| other test files | Phase 1–3 regression (notes, Hive, search, settings, cipher round trips) |

## 11. Known limitations

- Hill Cipher security limits (see Phase 3).
- Old notes are not re-encrypted to a newer key version automatically.
- Keys cannot be renamed, exported or backed up.
- Unsaved edits to a decrypted note are lost if the app is killed
  (deliberately not stored as plaintext).
- Not yet run on a physical Android device or emulator.

## 12. Future improvements

- Optional "re-encrypt notes with the active version" action per key.
- AES-GCM as a new `CipherFormat` (see Phase 3 §11).
- Key backup/export protected by a passphrase.
