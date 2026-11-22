import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../../core/errors/app_exceptions.dart';
import '../../../core/utils/date_formatter.dart';
import '../../../core/widgets/dialogs.dart';
import '../../../core/widgets/section_header.dart';
import '../../../data/models/key_metadata.dart';
import '../../../routes/app_routes.dart';
import '../../encryption/presentation/key_dialogs.dart';
import '../providers/key_provider.dart';

enum _KeyAction { activate, delete }

/// Lists Hill Cipher keys and lets the user create, activate and delete
/// them. Key values are never shown.
class KeyManagementScreen extends StatelessWidget {
  const KeyManagementScreen({super.key});

  Future<void> _create(BuildContext context) async {
    final key = await showCreateKeyDialog(context);
    if (key != null && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Key “${key.name}” created and set as active')),
      );
    }
  }

  Future<void> _onAction(
    BuildContext context,
    KeyMetadata key,
    _KeyAction action,
  ) async {
    final provider = context.read<KeyProvider>();
    final messenger = ScaffoldMessenger.of(context);
    try {
      switch (action) {
        case _KeyAction.activate:
          await provider.setActive(key.id);
          messenger.showSnackBar(
            SnackBar(content: Text('“${key.name}” is now the active key')),
          );
        case _KeyAction.delete:
          final confirmed = await showConfirmDialog(
            context,
            title: 'Delete key?',
            message:
                'The key “${key.name}” will be removed from this device. '
                'This cannot be undone. Keys used by encrypted notes cannot '
                'be deleted.',
            confirmLabel: 'Delete',
            destructive: true,
          );
          if (!confirmed) return;
          await provider.deleteKey(key.id);
          messenger.showSnackBar(
            SnackBar(content: Text('Key “${key.name}” deleted')),
          );
      }
    } on KeyInUseException catch (error) {
      if (!context.mounted) return;
      await showInfoDialog(
        context,
        icon: Icons.lock_outline_rounded,
        title: 'Key is in use',
        message:
            '${error.message} Deleting it would make '
            '${error.noteCount == 1 ? 'that note' : 'those notes'} '
            'impossible to read.\n\nTo delete this key, open each note, '
            'decrypt it, and save it as plain text or encrypt it with a '
            'different key.',
      );
    } on AppException catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final keys = context.watch<KeyProvider>();
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Key Management')),
      floatingActionButton: keys.hasKeys
          ? FloatingActionButton.extended(
              key: const Key('create-key'),
              onPressed: keys.isBusy ? null : () => _create(context),
              icon: const Icon(Icons.add_rounded),
              label: const Text('New key'),
            )
          : null,
      body: ListView(
        padding: const EdgeInsets.only(bottom: 96),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
            child: Text(
              'A key is a secret that locks and unlocks your encrypted '
              'notes. Keys are created randomly and kept in secure storage '
              'on this device. Creating a key is optional — you can keep '
              'writing normal notes without one.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
                height: 1.5,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: scheme.errorContainer.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.warning_amber_rounded, color: scheme.error),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      hillCipherWarning,
                      style: theme.textTheme.bodySmall?.copyWith(height: 1.4),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (keys.error != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: Text(
                keys.error!.message,
                style: theme.textTheme.bodySmall?.copyWith(color: scheme.error),
              ),
            ),
          const SectionHeader('Your keys'),
          if (!keys.isLoaded && keys.error == null)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (!keys.hasKeys)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.key_off_outlined,
                            color: scheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Text(
                              'No encryption key has been created yet.',
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        key: const Key('generate-key'),
                        onPressed: keys.isBusy ? null : () => _create(context),
                        icon: const Icon(Icons.add_rounded),
                        label: const Text('Generate New Key'),
                      ),
                    ],
                  ),
                ),
              ),
            )
          else
            SectionCard(
              children: [
                for (final key in keys.keys)
                  _KeyTile(
                    keyMetadata: key,
                    enabled: !keys.isBusy,
                    onAction: (action) => _onAction(context, key, action),
                  ),
              ],
            ),
          const SectionHeader('Learn more'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Card(
              clipBehavior: Clip.antiAlias,
              child: ListTile(
                leading: const Icon(Icons.shield_outlined),
                title: const Text('About encryption'),
                subtitle: const Text('How note encryption works'),
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

class _KeyTile extends StatelessWidget {
  const _KeyTile({
    required this.keyMetadata,
    required this.enabled,
    required this.onAction,
  });

  final KeyMetadata keyMetadata;
  final bool enabled;
  final ValueChanged<_KeyAction> onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final key = keyMetadata;
    return ListTile(
      key: ValueKey('key-tile-${key.id}'),
      leading: Icon(
        key.isActive ? Icons.vpn_key_rounded : Icons.vpn_key_outlined,
        color: key.isActive ? scheme.primary : null,
      ),
      title: Row(
        children: [
          Flexible(child: Text(key.name, overflow: TextOverflow.ellipsis)),
          if (key.isActive) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: scheme.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'Active',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: scheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ],
      ),
      subtitle: Text(
        'Hill Cipher 2×2 · Version ${key.version}\n'
        'Created ${DateFormatter.full(key.createdAt)}',
      ),
      isThreeLine: true,
      trailing: PopupMenuButton<_KeyAction>(
        key: ValueKey('key-menu-${key.id}'),
        enabled: enabled,
        tooltip: 'Key options',
        onSelected: onAction,
        itemBuilder: (context) => [
          if (!key.isActive)
            const PopupMenuItem(
              value: _KeyAction.activate,
              child: Text('Set as active'),
            ),
          PopupMenuItem(
            value: _KeyAction.delete,
            child: Text('Delete', style: TextStyle(color: scheme.error)),
          ),
        ],
      ),
    );
  }
}
