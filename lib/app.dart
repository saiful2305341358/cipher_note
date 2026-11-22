import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import 'core/constants/app_constants.dart';
import 'core/theme/app_theme.dart';
import 'data/repositories/key_metadata_repository.dart';
import 'data/repositories/note_repository.dart';
import 'data/repositories/secure_key_store.dart';
import 'data/repositories/settings_repository.dart';
import 'features/encryption/data/key_service.dart';
import 'features/encryption/data/note_encryption_service.dart';
import 'features/key_management/providers/key_provider.dart';
import 'features/notes/providers/notes_provider.dart';
import 'features/settings/providers/settings_provider.dart';
import 'routes/app_routes.dart';

/// Root widget.
///
/// The app passes the Hive- and secure-storage-backed stores created by
/// `AppInitializer`. When one is omitted (in tests) an in-memory store is
/// used.
class CipherNoteApp extends StatefulWidget {
  const CipherNoteApp({
    super.key,
    this.noteRepository,
    this.keyRepository,
    this.settingsRepository,
    this.secureKeyStore,
    this.settings,
  });

  final NoteRepository? noteRepository;
  final KeyMetadataRepository? keyRepository;
  final SettingsRepository? settingsRepository;
  final SecureKeyStore? secureKeyStore;

  /// Initial settings state. When omitted, defaults are used and saved to
  /// [settingsRepository].
  final SettingsProvider? settings;

  @override
  State<CipherNoteApp> createState() => _CipherNoteAppState();
}

class _CipherNoteAppState extends State<CipherNoteApp> {
  late final NoteRepository _notes =
      widget.noteRepository ?? InMemoryNoteRepository();
  late final KeyService _keyService = KeyService(
    metadata: widget.keyRepository ?? InMemoryKeyMetadataRepository(),
    secureStore: widget.secureKeyStore ?? InMemorySecureKeyStore(),
    notes: _notes,
  );
  late final NoteEncryptionService _encryption = NoteEncryptionService(
    keys: _keyService,
  );

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<NoteEncryptionService>.value(value: _encryption),
        ChangeNotifierProvider<SettingsProvider>(
          create: (_) =>
              widget.settings ??
              SettingsProvider(repository: widget.settingsRepository),
        ),
        ChangeNotifierProvider<NotesProvider>(
          create: (_) => NotesProvider(_notes)..load(),
        ),
        ChangeNotifierProvider<KeyProvider>(
          create: (_) => KeyProvider(_keyService)..load(),
        ),
      ],
      child: Consumer<SettingsProvider>(
        builder: (context, settings, _) => MaterialApp(
          title: AppConstants.appName,
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light,
          darkTheme: AppTheme.dark,
          themeMode: settings.themeMode,
          initialRoute: AppRoutes.home,
          onGenerateRoute: AppRoutes.onGenerateRoute,
          navigatorObservers: [AppRoutes.observer],
        ),
      ),
    );
  }
}
