import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import 'core/constants/app_constants.dart';
import 'core/theme/app_theme.dart';
import 'data/repositories/key_repository.dart';
import 'data/repositories/note_repository.dart';
import 'features/key_management/providers/key_provider.dart';
import 'features/notes/providers/notes_provider.dart';
import 'features/settings/providers/settings_provider.dart';
import 'routes/app_routes.dart';

/// Root widget. Repositories can be injected (for tests, or later for a
/// Hive-backed implementation); by default in-memory stores are used.
class CipherNoteApp extends StatelessWidget {
  const CipherNoteApp({
    super.key,
    this.noteRepository,
    this.keyRepository,
    this.settings,
  });

  final NoteRepository? noteRepository;
  final KeyRepository? keyRepository;
  final SettingsProvider? settings;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<SettingsProvider>(
          create: (_) => settings ?? SettingsProvider(),
        ),
        ChangeNotifierProvider<NotesProvider>(
          create: (_) =>
              NotesProvider(noteRepository ?? InMemoryNoteRepository())..load(),
        ),
        ChangeNotifierProvider<KeyProvider>(
          create: (_) =>
              KeyProvider(keyRepository ?? InMemoryKeyRepository())..load(),
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
