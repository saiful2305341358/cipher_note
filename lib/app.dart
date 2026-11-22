import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import 'core/constants/app_constants.dart';
import 'core/theme/app_theme.dart';
import 'data/repositories/key_metadata_repository.dart';
import 'data/repositories/note_repository.dart';
import 'data/repositories/settings_repository.dart';
import 'features/key_management/providers/key_provider.dart';
import 'features/notes/providers/notes_provider.dart';
import 'features/settings/providers/settings_provider.dart';
import 'routes/app_routes.dart';

/// Root widget.
///
/// The app passes the Hive-backed repositories created by `AppInitializer`.
/// When a repository is omitted (in tests) an in-memory one is used.
class CipherNoteApp extends StatelessWidget {
  const CipherNoteApp({
    super.key,
    this.noteRepository,
    this.keyRepository,
    this.settingsRepository,
    this.settings,
  });

  final NoteRepository? noteRepository;
  final KeyMetadataRepository? keyRepository;
  final SettingsRepository? settingsRepository;

  /// Initial settings state. When omitted, defaults are used and saved to
  /// [settingsRepository].
  final SettingsProvider? settings;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<SettingsProvider>(
          create: (_) =>
              settings ?? SettingsProvider(repository: settingsRepository),
        ),
        ChangeNotifierProvider<NotesProvider>(
          create: (_) =>
              NotesProvider(noteRepository ?? InMemoryNoteRepository())..load(),
        ),
        ChangeNotifierProvider<KeyProvider>(
          create: (_) =>
              KeyProvider(keyRepository ?? InMemoryKeyMetadataRepository())
                ..load(),
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
