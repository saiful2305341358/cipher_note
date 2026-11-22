import 'package:material_ui/material_ui.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/widgets/app_logo.dart';
import '../../../core/widgets/section_header.dart';

/// Application name, version, description and technology information.
class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('About')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          const SizedBox(height: 16),
          const Center(child: AppLogo(size: 80)),
          const SizedBox(height: 16),
          Text(
            AppConstants.appName,
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Version ${AppConstants.appVersion} '
            '(build ${AppConstants.buildNumber}) · '
            '${AppConstants.developmentPhase}',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(32, 16, 32, 0),
            child: Text(
              AppConstants.appDescription,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
            ),
          ),
          const SectionHeader('Technology'),
          const SectionCard(
            children: [
              ListTile(
                leading: Icon(Icons.flutter_dash_rounded),
                title: Text('Flutter & Dart'),
                subtitle: Text('Android app built with Material Design'),
              ),
              ListTile(
                leading: Icon(Icons.account_tree_outlined),
                title: Text('Provider'),
                subtitle: Text('App state management'),
              ),
              ListTile(
                leading: Icon(Icons.translate_rounded),
                title: Text('English & বাংলা'),
                subtitle: Text('Noto Sans Bengali font for Bangla text'),
              ),
              ListTile(
                leading: Icon(Icons.grid_on_rounded),
                title: Text('2×2 Hill Cipher (planned)'),
                subtitle: Text('Optional, educational note encryption'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Center(
            child: TextButton.icon(
              onPressed: () => showLicensePage(
                context: context,
                applicationName: AppConstants.appName,
                applicationVersion: AppConstants.appVersion,
                applicationIcon: const Padding(
                  padding: EdgeInsets.all(8),
                  child: AppLogo(size: 48),
                ),
              ),
              icon: const Icon(Icons.description_outlined),
              label: const Text('Open-source licenses'),
            ),
          ),
        ],
      ),
    );
  }
}
