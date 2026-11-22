# Phase 3 — Hill Cipher Encryption

> **This is a classical, educational cipher, not secure encryption.** A 2×2
> Hill Cipher over bytes is linear, has a very small key space, can be
> broken from a few known plaintext/ciphertext pairs, and has no integrity
> protection. It must not be used to protect passwords, financial data or
> other sensitive information. The app says this wherever keys are created
> or used.

## 1. Mathematical model

A key is a 2×2 matrix of bytes (values 0–255):

```
K = | a  b |      P = | p1 |      C = K·P (mod 256)
    | c  d |          | p2 |
c1 = (a·p1 + b·p2) mod 256
c2 = (c·p1 + d·p2) mod 256
```

Plaintext is processed as pairs of UTF-8 bytes (`HillCipher.transformPairs`).
All arithmetic uses Dart `int` (64-bit), so `255·255 + 255·255` cannot
overflow, and `%` always gives a value in 0–255.

### Why modulo 256

Each UTF-8 byte is already a number from 0 to 255, so working modulo 256
maps bytes to bytes. English (1 byte per letter) and Bangla (3 bytes per
character) are handled the same way, without a separate alphabet for each
script.

### Validity

`det(K) = ad − bc`. K is invertible modulo 256 only when
`gcd(det mod 256, 256) = 1`, i.e. the determinant is **odd**.
`HillKeyMatrix` can only be created valid: values outside 0–255 or an even
determinant raise `InvalidKeyException`. Keys loaded from storage are
validated again before use.

### Inverse

`ModularMath.modInverse` uses the extended Euclidean algorithm to find
`det⁻¹ mod 256`. Then

```
K⁻¹ = det⁻¹ · |  d  −b |  (mod 256)        P = K⁻¹·C (mod 256)
              | −c   a |
```

Tests check `K·K⁻¹ = I` for fixed and random keys and that every odd
number 0–255 has an inverse and no even number does.

## 2. Padding

PKCS#7-style padding to 2-byte blocks, **always** applied:

| Plaintext length | Added bytes |
|---|---|
| odd | `01` |
| even (including 0) | `02 02` |

After decryption the last byte must be 1 or 2 and all padding bytes must
equal it, otherwise `DecryptionFailedException` is raised. Invalid padding
or invalid UTF-8 is never ignored.

## 3. Words, separators and ciphertext format

`TextTokenizer` splits text into words and separators; joining the tokens
always gives back the exact input.

- **Word characters:** Unicode letters `\p{L}`, combining marks `\p{M}`
  (Bangla vowel signs, hasanta, accents), numbers `\p{N}`, connectors
  `\p{Pc}`, and the zero-width (non-)joiners used in Bangla conjuncts.
- **Joiners inside a word:** `' ’ - . @ / : ? = & % + # ~` when they sit
  between word characters. So `don't`, `well-known`, `3.14`, `2026-11-22`,
  `16:49`, `user@example.com` and `https://example.com/a?b=1` are single
  words. Punctuation at the start or end of a word is a separator.
- **Separators:** everything else — spaces, tabs, line breaks, commas, `।`,
  brackets, quotes, emoji and other symbols.

`WordCipher` encrypts each word separately: UTF-8 bytes → pad → Hill Cipher
→ **uppercase hex** (two characters per byte). Separators are copied
unchanged, so

```
Hello, how are you?            →  D1C260CC520B, 63B66A43 5D8B34C5 962D6435?
আমি ভালো আছি। Thank you!       →  DE6C…423B DE6C…1012 DE6C…423B। 041C…46EF 962D6435!
```

Separators never contain letters or digits, so in ciphertext every run of
`[0-9A-F]` is exactly one encrypted word. Decryption rejects ciphertext that
has odd-length hex, lowercase letters, or any other letter or digit
(`CiphertextFormatException`).

After encrypting, `WordCipher.encrypt` decrypts the result and compares it
with the input; if they differ, encryption fails instead of storing
unreadable ciphertext.

Both the **title** and the **content** are encrypted, separately, with the
same key.

## 4. Keys

### Generation

`KeyGenerator` draws four bytes from `Random.secure()` until the matrix is
valid. It also requires `b ≠ 0` and `c ≠ 0`, so the identity and other
diagonal matrices (which would encrypt each byte on its own) are never
generated. About 3 in 8 candidates are accepted.

### Storage

| Storage | Contents |
|---|---|
| Hive `key_metadata` | id, display name, version, algorithm (`hill-2x2`), created date, active flag |
| Secure storage (`flutter_secure_storage`) | the four matrix values, under `hill_key_<id>_v<version>` |

- Key values are never written to Hive, never shown in the UI, and never
  logged (`HillKeyMatrix.toString()` hides them).
- On Android, `flutter_secure_storage` encrypts values with a key held in
  the Android Keystore. `resetOnError` is set to **false**: the plugin's
  default would silently wipe all stored keys after a read error.
- Creating a key writes secure storage first, then metadata; if the
  metadata write fails, the stored value is deleted again.
- `KeyService.loadKey(id, version)` checks that the metadata exists, the
  version matches and the algorithm is supported, reads the value, and
  validates the matrix. It never falls back to another key.

### Deleting

`KeyService.deleteKey` counts stored notes that reference the key. If any
do, it throws `KeyInUseException` and deletes nothing; the UI explains how
to free the key (decrypt those notes and save them as plain text or with
another key). Unused keys are deleted from secure storage and Hive.

There is one key version per key; key rotation is not implemented.

## 5. Data model changes (schema v2)

`Note` gains field 9, `cipherFormat`, stored as a map:

```
{algorithm: hill_cipher, version: 1, encoding: hex, blockSize: 2, modulus: 256}
```

An encrypted note stores ciphertext in `title` and `content`, with
`isEncrypted = true`, `keyId`, `keyVersion` and `cipherFormat`. Plaintext
is never stored. `Note.toEncrypted` and `Note.toPlain` keep these fields
consistent, and `Note.toString()` never includes text.

Migration v1 → v2 rewrites nothing: older notes read the missing field as
`null` and stay plain. The step only checks that no v1 note claims to be
encrypted, and fails safely (without deleting data) if one does. Unknown
`cipherFormat` values make decryption fail with a clear message, so a
future AES-GCM format can be added alongside.

## 6. Workflows

### Encrypt (note editor)

1. The plain note is saved first.
2. **Encrypt** → if there is no key: *Create key / Cancel*. Otherwise a key
   picker (active key preselected, with *New key*).
3. Confirmation explaining that text will be replaced and repeating the
   security warning.
4. `NoteEncryptionService.encrypt` computes the encrypted note; only after
   it succeeds is it stored with one `NotesProvider.replaceNote` write. On
   any failure the stored note is unchanged.

Encryption is never automatic.

### Decrypt

Opening an encrypted note shows a locked view (no text, key name and
version, or "key not available"). **Decrypt** loads exactly the referenced
key version and decrypts title and content. The stored ciphertext is not
touched. Errors (missing/deleted key, wrong version, damaged key, unknown
format, invalid padding or UTF-8, secure-storage failure) are shown with
"The stored note has not been changed."

A wrong key can occasionally produce valid-looking text by chance: the Hill
Cipher cannot detect that. No unkeyed checksum is added, because it would
not be real authentication.

### Edit (decrypt → edit → encrypt again)

- Decrypted text is kept only in the editor's memory. Auto-save is off in
  this mode, so plaintext is never written to storage automatically.
- Leaving with changes asks: **Encrypt & save** (key picker, the note's key
  preselected), **Save as plain text** (with confirmation), **Discard
  changes**, or **Keep editing**. Leaving without changes just closes.
- The stored encrypted note is replaced only after the new encryption
  succeeds. Cancelling or any failure keeps the previous version.
- If the app is closed while a decrypted note has unsaved edits, those
  edits are lost (by design: they are not written as plaintext).
- The colour of an encrypted note can be changed without decrypting it.

## 7. Lists and search

- Encrypted notes show **"Encrypted note"**, a lock, and "Tap to decrypt"
  (or "Key unavailable on this device"). Titles and ciphertext are never
  shown, sorted by, or used in accessibility labels.
- Search never matches encrypted notes (neither plaintext nor
  ciphertext), and no plaintext index exists. The search screen says
  "encrypted notes are not searched".

## 8. Error handling

New `AppException` types: `InvalidKeyException`, `KeyUnavailableException`,
`CiphertextFormatException`, `DecryptionFailedException`,
`EncryptionFailedException`, `SecureStorageException`, `KeyInUseException`,
`EncryptedNoteLockedException` (raised if code tries to write readable text
into an encrypted note). Messages contain no note text, ciphertext or key
values; `ErrorReporter` receives only error types or platform error codes.

## 9. Tests

| File | Covers |
|---|---|
| `test/encryption/hill_cipher_math_test.dart` | gcd, extended Euclid, modular inverse (all 256 values), determinant, validity (grid), inverse matrix, worked example, mod-256 edges, padding, hex, key generator |
| `test/encryption/word_cipher_test.dart` | tokenizer rules and exact reconstruction; round trips for English, Bangla, vowel signs, conjuncts, ZWJ/ZWNJ, combining marks, emoji, Unicode punctuation, paragraphs, tabs, numbers, dates, URLs, emails; separators unchanged; invalid hex/padding/UTF-8; wrong key |
| `test/encryption/key_and_note_encryption_test.dart` | key creation/storage split, name validation, rollback on failure, key loading errors, in-use deletion block, active key; note encryption metadata; failure safety; search exclusion; Hive restart cycles; raw Hive file has no key values; v1→v2 migration |
| `test/features/encryption_flow_test.dart` | UI: create key and encrypt, list/search hide text, decrypt → edit → re-encrypt → reopen, discard, save as plain text, missing key, blocked key deletion, colour change |
| earlier test files | Phase 1 and Phase 2 behaviour (regression) |

```bash
flutter pub get
flutter analyze
flutter test
flutter build apk --debug
```

## 10. Known limitations

- Security: see the top of this document. Ciphertext also shows the
  number and length of words, keeps punctuation and emoji visible, and
  repeats for repeated words (no IV). Bangla words share a common byte
  prefix, which shows up as repeated hex blocks.
- Losing a key (deleted, app uninstalled, secure storage reset) makes its
  notes unreadable. There is no key backup or recovery.
- Encrypted notes are not searchable.
- Unsaved edits to a decrypted note are lost if the app is killed.
- Not yet run on a physical Android device or emulator; verified with unit
  and widget tests, an Android debug build, and the web build in Chromium.

## 11. Moving to AES-GCM later

The design keeps this possible without touching the screens:

- `CipherFormat` identifies the algorithm per note; add an `aes_gcm`
  format and keep `hill_cipher` v1 readable for migration.
- `NoteEncryptionService` is the only place that turns notes into
  ciphertext; swap in an authenticated cipher behind it.
- `SecureKeyStore` already stores opaque byte lists per key id/version, so
  32-byte AES keys fit as-is.
- AES-GCM would encrypt the whole title/content with a random nonce
  (separators could no longer be kept), and its authentication tag would
  reliably detect wrong keys and tampering.
