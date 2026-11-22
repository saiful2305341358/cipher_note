import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/dialogs.dart';
import '../../../core/widgets/section_header.dart';
import '../../../routes/app_routes.dart';
import '../../key_management/providers/key_provider.dart';
import '../../notes/widgets/note_color_picker.dart';
import '../providers/settings_provider.dart';

/// Appearance, note, security and general settings.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  Future<void> _pickSortOrder(
    BuildContext context,
    SettingsProvider settings,
  ) async {
    final selected = await showDialog<NoteSortOrder>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Sort notes by'),
        children: [
          RadioGroup<NoteSortOrder>(
            groupValue: settings.sortOrder,
            onChanged: (value) => Navigator.of(context).pop(value),
            child: Column(
              children: [
                for (final order in NoteSortOrder.values)
                  RadioListTile<NoteSortOrder>(
                    value: order,
                    title: Text(order.label),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
    if (selected != null) settings.setSortOrder(selected);
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final keys = context.watch<KeyProvider>();
    final theme = Theme.of(context);
    final brightness = theme.brightness;
    final defaultColor = AppColors.noteColorFor(settings.defaultNoteColor);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          if (settings.saveError != null)
            Container(
              key: const Key('settings-save-error'),
              margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '${settings.saveError!.message} Changes apply now but may '
                'reset when the app restarts.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onErrorContainer,
                ),
              ),
            ),
          const SectionHeader('Appearance'),
          SectionCard(
            children: [
              RadioGroup<ThemeMode>(
                groupValue: settings.themeMode,
                onChanged: (mode) {
                  if (mode != null) settings.setThemeMode(mode);
                },
                child: const Column(
                  children: [
                    RadioListTile<ThemeMode>(
                      key: Key('theme-light'),
                      value: ThemeMode.light,
                      title: Text('Light'),
                      secondary: Icon(Icons.light_mode_outlined),
                    ),
                    RadioListTile<ThemeMode>(
                      key: Key('theme-dark'),
                      value: ThemeMode.dark,
                      title: Text('Dark'),
                      secondary: Icon(Icons.dark_mode_outlined),
                    ),
                    RadioListTile<ThemeMode>(
                      key: Key('theme-system'),
                      value: ThemeMode.system,
                      title: Text('System default'),
                      secondary: Icon(Icons.brightness_auto_outlined),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SectionHeader('Notes'),
          SectionCard(
            children: [
              ListTile(
                key: const Key('default-color'),
                leading: const Icon(Icons.palette_outlined),
                title: const Text('Default note color'),
                subtitle: Text(defaultColor.name),
                trailing: Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: defaultColor.resolve(brightness),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: AppColors.noteAccent(
                        settings.defaultNoteColor,
                        brightness,
                      ),
                    ),
                  ),
                ),
                onTap: () => showNoteColorPickerSheet(
                  context,
                  title: 'Default color for new notes',
                  selected: settings.defaultNoteColor,
                  onSelected: settings.setDefaultNoteColor,
                ),
              ),
              ListTile(
                leading: const Icon(Icons.dashboard_outlined),
                title: const Text('Default view'),
                trailing: SegmentedButton<NoteViewMode>(
                  key: const Key('view-mode-setting'),
                  showSelectedIcon: false,
                  style: const ButtonStyle(
                    visualDensity: VisualDensity.compact,
                  ),
                  segments: const [
                    ButtonSegment(
                      value: NoteViewMode.list,
                      icon: Icon(Icons.view_agenda_outlined, size: 18),
                      tooltip: 'List',
                    ),
                    ButtonSegment(
                      value: NoteViewMode.grid,
                      icon: Icon(Icons.grid_view_rounded, size: 18),
                      tooltip: 'Grid',
                    ),
                  ],
                  selected: {settings.viewMode},
                  onSelectionChanged: (value) =>
                      settings.setViewMode(value.first),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.sort_rounded),
                title: const Text('Sort notes by'),
                subtitle: Text(settings.sortOrder.label),
                onTap: () => _pickSortOrder(context, settings),
              ),
              SwitchListTile(
                key: const Key('show-preview'),
                secondary: const Icon(Icons.notes_rounded),
                title: const Text('Show content preview'),
                subtitle: const Text('Show the first lines of each note'),
                value: settings.showContentPreview,
                onChanged: settings.setShowContentPreview,
              ),
              SwitchListTile(
                key: const Key('auto-save'),
                secondary: const Icon(Icons.save_outlined),
                title: const Text('Auto-save while editing'),
                subtitle: Text(
                  settings.autoSave
                      ? 'Changes are saved as you type'
                      : 'You will be asked before leaving unsaved changes',
                ),
                value: settings.autoSave,
                onChanged: settings.setAutoSave,
              ),
              ListTile(
                leading: const Icon(Icons.storage_outlined),
                title: const Text('Storage'),
                subtitle: const Text('Saved on this device'),
                trailing: const Icon(Icons.info_outline_rounded),
                onTap: () => showInfoDialog(
                  context,
                  icon: Icons.storage_outlined,
                  title: 'Storage',
                  message:
                      'Notes, settings and key information are saved in a '
                      'private database on this device and stay after the '
                      'app is closed. Notes are stored as normal, readable '
                      'text: encryption is not available yet.',
                ),
              ),
            ],
          ),
          const SectionHeader('Security'),
          SectionCard(
            children: [
              ListTile(
                leading: const Icon(Icons.key_outlined),
                title: const Text('Key Management'),
                subtitle: Text(
                  !keys.hasKey
                      ? 'No key created (optional)'
                      : keys.isDemo
                      ? 'Demo key preview'
                      : 'Key available',
                ),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => AppRoutes.open(context, AppRoutes.keyManagement),
              ),
              ListTile(
                leading: const Icon(Icons.shield_outlined),
                title: const Text('Encryption information'),
                subtitle: const Text(
                  'What encryption will mean for your notes',
                ),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => AppRoutes.open(context, AppRoutes.encryptionInfo),
              ),
            ],
          ),
          const SectionHeader('General'),
          SectionCard(
            children: [
              ListTile(
                leading: const Icon(Icons.info_outline_rounded),
                title: const Text('About ${AppConstants.appName}'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => AppRoutes.open(context, AppRoutes.about),
              ),
              const ListTile(
                leading: Icon(Icons.tag_rounded),
                title: Text('Version'),
                trailing: Text(
                  '${AppConstants.appVersion} (${AppConstants.buildNumber})',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
