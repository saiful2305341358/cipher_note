import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../../core/errors/app_exceptions.dart';
import '../../../core/utils/date_formatter.dart';
import '../../../data/models/key_metadata.dart';
import '../../key_management/providers/key_provider.dart';

/// Short reminder shown wherever keys are created or used.
const String hillCipherWarning =
    'Hill Cipher is a classical, educational cipher. It is easy to break and '
    'must not be used for passwords, bank details or other sensitive '
    'information.';

/// Asks for a key name and creates a new key. Returns the new key, or
/// `null` if cancelled.
Future<KeyMetadata?> showCreateKeyDialog(BuildContext context) {
  return showDialog<KeyMetadata>(
    context: context,
    builder: (_) => const _CreateKeyDialog(),
  );
}

class _CreateKeyDialog extends StatefulWidget {
  const _CreateKeyDialog();

  @override
  State<_CreateKeyDialog> createState() => _CreateKeyDialogState();
}

class _CreateKeyDialogState extends State<_CreateKeyDialog> {
  final _controller = TextEditingController();
  String? _error;
  bool _creating = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    if (_creating) return;
    final name = _controller.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Enter a name for the key.');
      return;
    }
    setState(() {
      _creating = true;
      _error = null;
    });
    try {
      final key = await context.read<KeyProvider>().createKey(name);
      if (mounted) Navigator.of(context).pop(key);
    } on AppException catch (error) {
      if (mounted) {
        setState(() {
          _creating = false;
          _error = error.message;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('Create a key'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'A random 2×2 Hill Cipher key will be created and kept in this '
            "device's secure storage. The name is only a label.",
            style: theme.textTheme.bodyMedium?.copyWith(height: 1.4),
          ),
          const SizedBox(height: 16),
          TextField(
            key: const Key('key-name-field'),
            controller: _controller,
            autofocus: true,
            enabled: !_creating,
            maxLength: KeyMetadata.maxNameLength,
            textCapitalization: TextCapitalization.sentences,
            onSubmitted: (_) => _create(),
            decoration: InputDecoration(
              labelText: 'Key name',
              hintText: 'e.g. Personal key',
              errorText: _error,
              border: const OutlineInputBorder(),
              isDense: false,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            hillCipherWarning,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.4,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _creating ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('create-key-confirm'),
          onPressed: _creating ? null : _create,
          child: _creating
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Create'),
        ),
      ],
    );
  }
}

/// Lets the user pick the key to encrypt with. If there are no keys, offers
/// to create one. Returns `null` if cancelled.
Future<KeyMetadata?> showKeyPicker(
  BuildContext context, {
  String? preselectedKeyId,
}) async {
  final keys = context.read<KeyProvider>();
  if (!keys.hasKeys) {
    final create = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.key_outlined),
        title: const Text('No encryption key yet'),
        content: const Text(
          'You need a key to encrypt notes. Create one now? '
          'You can keep writing normal notes without a key.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('no-key-create'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Create key'),
          ),
        ],
      ),
    );
    if (create != true || !context.mounted) return null;
    return showCreateKeyDialog(context);
  }

  return showModalBottomSheet<KeyMetadata>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _KeyPickerSheet(
      preselectedKeyId: preselectedKeyId ?? keys.activeKey?.id,
    ),
  );
}

class _KeyPickerSheet extends StatefulWidget {
  const _KeyPickerSheet({required this.preselectedKeyId});

  final String? preselectedKeyId;

  @override
  State<_KeyPickerSheet> createState() => _KeyPickerSheetState();
}

class _KeyPickerSheetState extends State<_KeyPickerSheet> {
  String? _selectedId;

  @override
  void initState() {
    super.initState();
    _selectedId = widget.preselectedKeyId;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final keys = context.watch<KeyProvider>().keys;
    if (keys.every((k) => k.id != _selectedId)) {
      _selectedId = keys.isEmpty ? null : keys.first.id;
    }
    KeyMetadata? selected;
    for (final k in keys) {
      if (k.id == _selectedId) selected = k;
    }

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.75,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                'Choose a key',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Flexible(
              child: RadioGroup<String>(
                groupValue: _selectedId,
                onChanged: (id) => setState(() => _selectedId = id),
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final key in keys)
                      RadioListTile<String>(
                        key: ValueKey('pick-key-${key.id}'),
                        value: key.id,
                        title: Text(key.name),
                        subtitle: Text(
                          'Version ${key.version} · Created '
                          '${DateFormatter.full(key.createdAt)}'
                          '${key.isActive ? ' · Active' : ''}',
                        ),
                      ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              child: Row(
                children: [
                  TextButton.icon(
                    onPressed: () async {
                      final created = await showCreateKeyDialog(context);
                      if (created != null && mounted) {
                        setState(() => _selectedId = created.id);
                      }
                    },
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('New key'),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    key: const Key('pick-key-confirm'),
                    onPressed: selected == null
                        ? null
                        : () => Navigator.of(context).pop(selected),
                    child: const Text('Use key'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
