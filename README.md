# Cipher Note

A minimalist note-taking app for Android, built with Flutter. It supports
English and Bangla (বাংলা) text. Optional note encryption with a
user-created 2×2 Hill Cipher key is planned for a later phase.

## Status: Phase 1 (UI/UX)

- Home (list/grid, sort, empty state), Note Editor, Search, Settings,
  Key Management (UI only), Encryption Information, About.
- Notes are kept **in memory for the current session only**. Persistent
  storage (Hive) is Phase 2. Encryption is Phase 3. Neither is implemented yet.

## Structure

```
lib/
  main.dart, app.dart          entry point, providers, MaterialApp
  core/                        constants, theme/colours, utils, shared widgets
  data/models/                 Note, EncryptionKeyInfo
  data/repositories/           NoteRepository / KeyRepository + in-memory impls
  features/<feature>/          screens, widgets and providers per feature
  routes/app_routes.dart       named routes and navigation helpers
```

The UI only talks to `NotesProvider` / `KeyProvider`, which only talk to the
repository interfaces, so a Hive-backed repository can be dropped in later.

## Development

```bash
flutter pub get
dart format lib test
flutter analyze
flutter test
```

Bangla text uses the bundled Noto Sans Bengali font (SIL Open Font License,
see `assets/fonts/OFL.txt`).
