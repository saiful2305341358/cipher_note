import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../../core/utils/date_formatter.dart';
import '../../../core/widgets/dialogs.dart';
import '../../../core/widgets/section_header.dart';
import '../../../data/models/encryption_key_info.dart';
import '../../../routes/app_routes.dart';
import '../providers/key_provider.dart';

/// Shows the status of the (future) Hill Cipher key.
///
/// No cryptographic work happens here in Phase 1. A clearly-labelled demo
/// state can be shown to preview how an existing key will look.
class KeyManagementScreen extends StatelessWidget {
  const KeyManagementScreen({super.key});

  static const String _futureMessage =
      'Key generation will be available in a future update.';

  void _showFutureDialog(BuildContext context, {String title = 'Coming soon'}) {
    showInfoDialog(
      context,
      icon: Icons.key_outlined,
      title: title,
      message: _futureMessage,
    );
  }

  Future<void> _confirmDelete(BuildContext context, KeyProvider keys) async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Delete key?',
      message: keys.keyInfo?.isDemo ?? false
          ? 'This removes the demo key preview. No notes are affected.'
          : 'This removes the encryption key.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (confirmed) await keys.deleteKey();
  }

  @override
  Widget build(BuildContext context) {
    final keys = context.watch<KeyProvider>();
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Key Management')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
            child: Text(
              'An encryption key is a secret that you will create yourself. '
              'It will let you lock individual notes so that they cannot be '
              'read without the key. Creating a key is optional — you can '
              'keep writing normal notes without one.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
                height: 1.5,
              ),
            ),
          ),
          const SectionHeader('Current key'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: keys.hasKey
                  ? _KeyAvailableCard(
                      key: const ValueKey('key-available'),
                      info: keys.keyInfo!,
                      onChange: () =>
                          _showFutureDialog(context, title: 'Change key'),
                      onDelete: () => _confirmDelete(context, keys),
                    )
                  : _NoKeyCard(
                      key: const ValueKey('no-key'),
                      onGenerate: () =>
                          _showFutureDialog(context, title: 'Generate key'),
                      onPreview: keys.showDemoKey,
                    ),
            ),
          ),
          const SectionHeader('Learn more'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Card(
              clipBehavior: Clip.antiAlias,
              child: ListTile(
                leading: const Icon(Icons.shield_outlined),
                title: const Text('About encryption'),
                subtitle: const Text('How note encryption will work'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => AppRoutes.open(context, AppRoutes.encryptionInfo),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusRow extends StatelessWidget {
  const _StatusRow({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(icon, color: color),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _NoKeyCard extends StatelessWidget {
  const _NoKeyCard({
    super.key,
    required this.onGenerate,
    required this.onPreview,
  });

  final VoidCallback onGenerate;
  final VoidCallback onPreview;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _StatusRow(
              icon: Icons.key_off_outlined,
              color: theme.colorScheme.onSurfaceVariant,
              title: 'No key',
              subtitle: 'No encryption key has been created yet.',
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              key: const Key('generate-key'),
              onPressed: onGenerate,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Generate New Key'),
            ),
            const SizedBox(height: 4),
            TextButton(
              key: const Key('preview-demo-key'),
              onPressed: onPreview,
              child: const Text('Preview how a saved key will look (demo)'),
            ),
          ],
        ),
      ),
    );
  }
}

class _KeyAvailableCard extends StatelessWidget {
  const _KeyAvailableCard({
    super.key,
    required this.info,
    required this.onChange,
    required this.onDelete,
  });

  final EncryptionKeyInfo info;
  final VoidCallback onChange;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final labelStyle = theme.textTheme.bodyMedium?.copyWith(
      color: scheme.onSurfaceVariant,
    );

    Widget detail(String label, String value) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(width: 110, child: Text(label, style: labelStyle)),
          Expanded(child: Text(value, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _StatusRow(
              icon: Icons.vpn_key_rounded,
              color: Colors.green.shade600,
              title: 'Key available',
              subtitle: info.isDemo
                  ? 'Demo preview — not a real key'
                  : 'Ready to encrypt notes',
            ),
            if (info.isDemo) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: scheme.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  'This is example data to preview the screen. No key exists '
                  'and nothing can be encrypted yet.',
                  style: theme.textTheme.bodySmall?.copyWith(height: 1.4),
                ),
              ),
            ],
            const SizedBox(height: 12),
            detail('Status', 'Available'),
            detail('Key ID', info.id),
            detail('Created', DateFormatter.full(info.createdAt)),
            detail('Key values', 'Hidden'),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    key: const Key('change-key'),
                    onPressed: onChange,
                    icon: const Icon(Icons.sync_rounded),
                    label: const Text('Change Key'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    key: const Key('delete-key'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: scheme.error,
                      side: BorderSide(
                        color: scheme.error.withValues(alpha: 0.5),
                      ),
                    ),
                    onPressed: onDelete,
                    icon: const Icon(Icons.delete_outline_rounded),
                    label: const Text('Delete Key'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
