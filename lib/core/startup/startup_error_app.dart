import 'package:material_ui/material_ui.dart';

import '../../app.dart';
import '../../features/settings/providers/settings_provider.dart';
import '../constants/app_constants.dart';
import '../errors/app_exceptions.dart';
import '../theme/app_theme.dart';
import 'app_initializer.dart';

/// Shown instead of the app when the database cannot be opened. Lets the
/// user retry; on success it switches to the normal app.
///
/// Nothing is deleted or reset here.
class StartupErrorApp extends StatefulWidget {
  const StartupErrorApp({
    super.key,
    required this.error,
    this.initialize = AppInitializer.initialize,
  });

  final AppException error;
  final Future<AppDependencies> Function() initialize;

  @override
  State<StartupErrorApp> createState() => _StartupErrorAppState();
}

class _StartupErrorAppState extends State<StartupErrorApp> {
  late AppException _error = widget.error;
  AppDependencies? _dependencies;
  bool _retrying = false;

  Future<void> _retry() async {
    setState(() => _retrying = true);
    try {
      final deps = await widget.initialize();
      if (!mounted) return;
      setState(() => _dependencies = deps);
    } on AppException catch (error) {
      if (!mounted) return;
      setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _retrying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final deps = _dependencies;
    if (deps != null) return buildApp(deps);

    return MaterialApp(
      title: AppConstants.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      home: Builder(
        builder: (context) {
          final theme = Theme.of(context);
          return Scaffold(
            body: SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.storage_rounded,
                        size: 56,
                        color: theme.colorScheme.error,
                      ),
                      const SizedBox(height: 20),
                      Text(
                        'Your notes could not be opened',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        '${_error.message}\n\nNothing has been deleted. '
                        'Try again, or close and reopen the app.',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 24),
                      FilledButton.icon(
                        key: const Key('startup-retry'),
                        onPressed: _retrying ? null : _retry,
                        icon: _retrying
                            ? const SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.refresh_rounded),
                        label: const Text('Try again'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Builds the app from opened dependencies.
Widget buildApp(AppDependencies deps) => CipherNoteApp(
  noteRepository: deps.noteRepository,
  keyRepository: deps.keyRepository,
  settingsRepository: deps.settingsRepository,
  secureKeyStore: deps.secureKeyStore,
  settings: SettingsProvider(
    repository: deps.settingsRepository,
    initial: deps.initialSettings,
  ),
);
