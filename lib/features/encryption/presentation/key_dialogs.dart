import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../../core/errors/app_exceptions.dart';
import '../../../core/utils/date_formatter.dart';
import '../../../data/models/key_metadata.dart';
import '../../key_management/providers/key_provider.dart';
import '../data/key_service.dart';

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

/// Lets the user pick the key version to encrypt with. If there are no
/// keys, offers to create one. Every version is validated (metadata, secure
/// storage, matrix) and invalid ones cannot be chosen. Returns `null` if
/// cancelled.
///
/// [preselectedKeyId] / [preselectedVersion] select a version initially
/// (for example the version an encrypted note already uses); otherwise the
/// active version is selected.
Future<KeyMetadata?> showKeyPicker(
  BuildContext context, {
  String? preselectedKeyId,
  int? preselectedVersion,
}) async {
  final keys = context.read<KeyProvider>();
  if (!keys.hasKeys) {
    final create = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.key_outlined),
        title: const Text('No Encryption Key Found'),
        content: const Text(
          'Create an encryption key before encrypting this note.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('no-key-create'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Create Key'),
          ),
        ],
      ),
    );
    if (create != true || !context.mounted) return null;
    final created = await showCreateKeyDialog(context);
    if (created == null || !context.mounted) return null;
    // A brand-new key still goes through validation before use.
    final status = await keys.validate(created.id, created.version);
    if (!status.isValid) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(status.message)));
      }
      return null;
    }
    return created;
  }

  final initial =
      keys.version(preselectedKeyId, preselectedVersion) ?? keys.activeKey;
  return showModalBottomSheet<KeyMetadata>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _KeyPickerSheet(initial: initial),
  );
}

String _pickId(KeyMetadata k) => '${k.id}@v${k.version}';

class _KeyPickerSheet extends StatefulWidget {
  const _KeyPickerSheet({required this.initial});

  final KeyMetadata? initial;

  @override
  State<_KeyPickerSheet> createState() => _KeyPickerSheetState();
}

class _KeyPickerSheetState extends State<_KeyPickerSheet> {
  String? _selected;

  /// Validation result per version; missing while still checking.
  final Map<String, KeyValidationStatus> _status = {};

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    _selected = initial == null ? null : _pickId(initial);
    _validateAll();
  }

  Future<void> _validateAll() async {
    final provider = context.read<KeyProvider>();
    for (final k in provider.keys) {
      final id = _pickId(k);
      if (_status.containsKey(id)) continue;
      final status = await provider.validate(k.id, k.version);
      if (!mounted) return;
      setState(() => _status[id] = status);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final provider = context.watch<KeyProvider>();
    final keys = provider.keys;
    KeyMetadata? selected;
    for (final k in keys) {
      if (_pickId(k) == _selected) selected = k;
    }
    final selectedStatus = selected == null ? null : _status[_pickId(selected)];
    final canUse = selectedStatus?.isValid ?? false;

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
                groupValue: _selected,
                onChanged: (id) => setState(() => _selected = id),
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final key in keys)
                      _KeyOption(
                        keyMetadata: key,
                        status: _status[_pickId(key)],
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
                    onPressed: provider.isBusy
                        ? null
                        : () async {
                            final created = await showCreateKeyDialog(context);
                            if (created != null && mounted) {
                              setState(() => _selected = _pickId(created));
                              _validateAll();
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
                    onPressed: canUse
                        ? () => Navigator.of(context).pop(selected)
                        : null,
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

class _KeyOption extends StatelessWidget {
  const _KeyOption({required this.keyMetadata, required this.status});

  final KeyMetadata keyMetadata;
  final KeyValidationStatus? status;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final key = keyMetadata;
    final invalid = status != null && !status!.isValid;
    final details =
        'Version ${key.version} · Created ${DateFormatter.full(key.createdAt)}'
        '${key.isActive ? ' · Active' : ''}';
    return RadioListTile<String>(
      key: ValueKey('pick-key-${key.id}-v${key.version}'),
      value: _pickId(key),
      enabled: !invalid,
      title: Text(key.name),
      subtitle: Text(
        status == null
            ? '$details\nChecking…'
            : invalid
            ? '$details\n${status!.message}'
            : details,
        style: invalid ? TextStyle(color: scheme.error) : null,
      ),
      isThreeLine: status == null || invalid,
    );
  }
}
