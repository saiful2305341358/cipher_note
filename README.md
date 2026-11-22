# Cipher Note

A minimalist note-taking app for Android, built with Flutter. It supports
English and Bangla (বাংলা) text. Optional note encryption with a
user-created 2×2 Hill Cipher key is planned for a later phase.

## Status

- **Phase 1 (UI/UX):** Home (list/grid, sort, empty state), Note Editor,
  Search, Settings, Key Management (UI only), Encryption Information, About.
- **Phase 2 (local storage):** notes, settings and key metadata are saved
  on the device with Hive CE, with autosave and error handling. See
  [docs/PHASE_2_IMPLEMENTATION.md](docs/PHASE_2_IMPLEMENTATION.md).
- **Phase 3 (Hill Cipher):** optional word-level 2×2 Hill Cipher
  encryption of note titles and content, keys in secure storage. See
  [docs/PHASE_3_IMPLEMENTATION.md](docs/PHASE_3_IMPLEMENTATION.md).
  **The Hill Cipher is educational, not secure encryption.**
- **Phase 4 (workflow & key versions):** Encrypt button after saving,
  Decrypt Note in the ⋮ menu, key versions and validation. See
  [docs/PHASE_4_IMPLEMENTATION.md](docs/PHASE_4_IMPLEMENTATION.md).

## Structure

```
lib/
  main.dart, app.dart          entry point, providers, MaterialApp
  core/                        constants, theme/colours, utils, shared widgets
  core/database/                Hive service, adapters, migrations
  core/startup/                database start-up and error screen
  data/models/                 Note, AppSettings, KeyMetadata
  data/repositories/           repository interfaces, Hive and in-memory impls
  features/encryption/         Hill Cipher (domain), key and note services
                               (data), key dialogs (presentation)
  features/<feature>/          screens, widgets and providers per feature
  routes/app_routes.dart       named routes and navigation helpers
```

Screens only talk to the providers, which only talk to the repository
interfaces. Hive is used only inside the repositories and `HiveService`.

## Development

```bash
flutter pub get
dart format lib test
flutter analyze
flutter test
```

Bangla text uses the bundled Noto Sans Bengali font (SIL Open Font License,
see `assets/fonts/OFL.txt`).
