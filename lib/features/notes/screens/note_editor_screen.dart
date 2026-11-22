import 'dart:async';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/date_formatter.dart';
import '../../../core/utils/text_utils.dart';
import '../../../core/widgets/dialogs.dart';
import '../../../data/models/note_model.dart';
import '../../settings/providers/settings_provider.dart';
import '../providers/notes_provider.dart';
import '../widgets/note_color_picker.dart';

enum _EditorMenuAction { color, share, info, delete }

enum _LeaveChoice { save, discard, stay }

/// Creates a new note ([noteId] is null) or edits an existing one.
///
/// Edits are kept in a local draft. With auto-save on (the default), the
/// draft is written to the note store shortly after typing stops and when
/// leaving the screen. With auto-save off, leaving with unsaved changes asks
/// the user to Save or Discard.
class NoteEditorScreen extends StatefulWidget {
  const NoteEditorScreen({super.key, this.noteId});

  final String? noteId;

  @override
  State<NoteEditorScreen> createState() => _NoteEditorScreenState();
}

class _NoteEditorScreenState extends State<NoteEditorScreen> {
  late final NotesProvider _notes;
  late final SettingsProvider _settings;
  late final TextEditingController _titleController;
  late final TextEditingController _contentController;
  final FocusNode _contentFocus = FocusNode();

  String? _noteId;
  late int _color;
  late String _savedTitle;
  late String _savedContent;
  late int _savedColor;
  Timer? _autoSaveTimer;
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    _notes = context.read<NotesProvider>();
    _settings = context.read<SettingsProvider>();

    final existing = widget.noteId == null
        ? null
        : _notes.getById(widget.noteId!);
    _noteId = existing?.id;
    _savedTitle = existing?.title ?? '';
    _savedContent = existing?.content ?? '';
    _savedColor = existing?.color ?? _settings.defaultNoteColor;
    _color = _savedColor;

    _titleController = TextEditingController(text: _savedTitle)
      ..addListener(_onTextChanged);
    _contentController = TextEditingController(text: _savedContent)
      ..addListener(_onTextChanged);
  }

  @override
  void dispose() {
    _autoSaveTimer?.cancel();
    _titleController.dispose();
    _contentController.dispose();
    _contentFocus.dispose();
    super.dispose();
  }

  Note? get _note => _noteId == null ? null : _notes.getById(_noteId!);

  bool get _isNew => _noteId == null;

  bool get _draftIsEmpty =>
      _titleController.text.trim().isEmpty &&
      _contentController.text.trim().isEmpty;

  bool get _hasMeaningfulContent => _contentController.text.trim().isNotEmpty;

  /// True when the draft differs from what is stored. A brand-new note that
  /// is still empty has nothing worth saving.
  bool get _hasUnsavedChanges {
    if (_isNew && _draftIsEmpty) return false;
    return _titleController.text != _savedTitle ||
        _contentController.text != _savedContent ||
        _color != _savedColor;
  }

  void _onTextChanged() {
    // Rebuild so the Encrypt button and the pop guard stay up to date.
    setState(() {});
    if (_settings.autoSave) {
      _autoSaveTimer?.cancel();
      _autoSaveTimer = Timer(AppConstants.autoSaveDelay, _commit);
    }
  }

  /// Writes the draft to the note store. Returns false if there was nothing
  /// to save (an empty new note).
  Future<bool> _commit() async {
    _autoSaveTimer?.cancel();
    if (!_hasUnsavedChanges) return !_isNew;
    final title = _titleController.text;
    final content = _contentController.text;
    final color = _color;
    if (_isNew) {
      final note = await _notes.createNote(
        title: title,
        content: content,
        color: color,
      );
      _noteId = note.id;
    } else {
      await _notes.updateNote(
        _noteId!,
        title: title,
        content: content,
        color: color,
      );
    }
    _savedTitle = title;
    _savedContent = content;
    _savedColor = color;
    if (mounted) setState(() {});
    return true;
  }

  Future<void> _onSavePressed() async {
    FocusScope.of(context).unfocus();
    final messenger = ScaffoldMessenger.of(context);
    if (_isNew && _draftIsEmpty) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Write something before saving.')),
      );
      return;
    }
    await _commit();
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text('Note saved'),
          duration: Duration(seconds: 2),
        ),
      );
  }

  Future<void> _handlePop(bool didPop) async {
    if (didPop || _closing) return;
    final navigator = Navigator.of(context);

    if (_settings.autoSave) {
      await _commit();
      _close(navigator);
      return;
    }

    final choice = await showDialog<_LeaveChoice>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Unsaved changes'),
        content: const Text(
          'You have changes that are not saved. Save them before leaving?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(_LeaveChoice.stay),
            child: const Text('Keep editing'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(_LeaveChoice.discard),
            child: const Text('Discard'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(_LeaveChoice.save),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    switch (choice) {
      case _LeaveChoice.save:
        await _commit();
        _close(navigator);
      case _LeaveChoice.discard:
        _close(navigator);
      case _LeaveChoice.stay || null:
        break;
    }
  }

  void _close(NavigatorState navigator) {
    _autoSaveTimer?.cancel();
    setState(() => _closing = true);
    navigator.pop();
  }

  Future<void> _changeColor() async {
    await showNoteColorPickerSheet(
      context,
      selected: _color,
      onSelected: (value) {
        setState(() => _color = value);
        // An existing note updates on the home screen right away.
        if (_settings.autoSave && !(_isNew && _draftIsEmpty)) _commit();
      },
    );
  }

  Future<void> _delete() async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Delete note?',
      message: _isNew
          ? 'This note has not been saved yet. Discard it?'
          : 'This note will be removed. You can undo right after deleting.',
      confirmLabel: _isNew ? 'Discard' : 'Delete',
      destructive: true,
    );
    if (!confirmed || !mounted) return;

    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final id = _noteId;
    _close(navigator);
    if (id == null) return;

    final removed = await _notes.deleteNote(id);
    if (removed == null) return;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: const Text('Note deleted'),
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () => _notes.restoreNote(removed),
          ),
        ),
      );
  }

  Future<void> _share() async {
    final title = _titleController.text.trim();
    final content = _contentController.text.trim();
    final text = [title, content].where((s) => s.isNotEmpty).join('\n\n');
    await showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                'Share note',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
            ),
            ListTile(
              key: const Key('share-copy'),
              enabled: text.isNotEmpty,
              leading: const Icon(Icons.copy_rounded),
              title: const Text('Copy note text'),
              subtitle: Text(
                text.isEmpty
                    ? 'The note is empty.'
                    : 'Paste it into any app to share it.',
              ),
              onTap: () async {
                final messenger = ScaffoldMessenger.of(context);
                Navigator.of(sheetContext).pop();
                await Clipboard.setData(ClipboardData(text: text));
                messenger.showSnackBar(
                  const SnackBar(content: Text('Note copied to clipboard')),
                );
              },
            ),
            const ListTile(
              enabled: false,
              leading: Icon(Icons.ios_share_rounded),
              title: Text('Share to other apps'),
              subtitle: Text(
                'Not available yet — planned for a future update.',
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _showInfo() async {
    final note = _note;
    final content = _contentController.text;
    final rows = <(String, String)>[
      (
        'Created',
        note == null ? 'Not saved yet' : DateFormatter.full(note.createdAt),
      ),
      (
        'Modified',
        note == null ? 'Not saved yet' : DateFormatter.full(note.updatedAt),
      ),
      ('Words', '${TextUtils.wordCount(content)}'),
      ('Characters', '${TextUtils.characterCount(content)}'),
      ('Color', AppColors.noteColorFor(_color).name),
      (
        'Encryption',
        (note?.isEncrypted ?? false) ? 'Encrypted' : 'Not encrypted',
      ),
      ('Storage', 'This session only (in memory)'),
    ];
    await showDialog<void>(
      context: context,
      builder: (context) {
        final theme = Theme.of(context);
        return AlertDialog(
          title: const Text('Note information'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final (label, value) in rows)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 96,
                        child: Text(
                          label,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Text(value, style: theme.textTheme.bodyMedium),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  void _onMenuSelected(_EditorMenuAction action) {
    switch (action) {
      case _EditorMenuAction.color:
        _changeColor();
      case _EditorMenuAction.share:
        _share();
      case _EditorMenuAction.info:
        _showInfo();
      case _EditorMenuAction.delete:
        _delete();
    }
  }

  void _showEncryptInfo() {
    showInfoDialog(
      context,
      icon: Icons.lock_outline_rounded,
      title: 'Encryption coming soon',
      message:
          'Encrypting notes with your own Hill Cipher key will be available '
          'in a future update.\n\nThis note has not been changed and is '
          'stored as normal, readable text.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final background = AppColors.noteBackground(_color, theme.brightness);
    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
    final note = _note;

    final String status;
    if (note == null) {
      status = 'New note';
    } else {
      status = 'Edited ${DateFormatter.full(note.updatedAt)}';
    }

    return PopScope<Object?>(
      canPop: _closing || !_hasUnsavedChanges,
      onPopInvokedWithResult: (didPop, _) => _handlePop(didPop),
      child: Scaffold(
        backgroundColor: background,
        appBar: AppBar(
          backgroundColor: background,
          leading: BackButton(
            onPressed: () => Navigator.of(context).maybePop(),
          ),
          title: Text(
            _isNew ? 'New note' : 'Edit note',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          actions: [
            IconButton(
              key: const Key('editor-save'),
              tooltip: 'Save',
              icon: Icon(
                _hasUnsavedChanges ? Icons.save_rounded : Icons.check_rounded,
              ),
              onPressed: _onSavePressed,
            ),
            PopupMenuButton<_EditorMenuAction>(
              key: const Key('editor-menu'),
              tooltip: 'More options',
              icon: const Icon(Icons.more_vert_rounded),
              onSelected: _onMenuSelected,
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: _EditorMenuAction.color,
                  child: ListTile(
                    leading: Icon(Icons.palette_outlined),
                    title: Text('Change color'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                const PopupMenuItem(
                  value: _EditorMenuAction.share,
                  child: ListTile(
                    leading: Icon(Icons.share_outlined),
                    title: Text('Share'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                const PopupMenuItem(
                  value: _EditorMenuAction.info,
                  child: ListTile(
                    leading: Icon(Icons.info_outline_rounded),
                    title: Text('Note information'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                PopupMenuItem(
                  value: _EditorMenuAction.delete,
                  child: ListTile(
                    leading: Icon(
                      Icons.delete_outline_rounded,
                      color: scheme.error,
                    ),
                    title: Text(
                      'Delete',
                      style: TextStyle(color: scheme.error),
                    ),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ],
            ),
            const SizedBox(width: 4),
          ],
        ),
        floatingActionButton: _hasMeaningfulContent && !keyboardOpen
            ? FloatingActionButton.extended(
                key: const Key('encrypt-button'),
                onPressed: _showEncryptInfo,
                icon: const Icon(Icons.lock_outline_rounded),
                label: const Text('Encrypt'),
              )
            : null,
        body: SafeArea(
          top: false,
          child: SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.manual,
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 120),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  status,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  key: const Key('editor-title'),
                  controller: _titleController,
                  autofocus: _isNew,
                  textCapitalization: TextCapitalization.sentences,
                  textInputAction: TextInputAction.next,
                  onSubmitted: (_) => _contentFocus.requestFocus(),
                  maxLines: null,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                    height: 1.35,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Title',
                    hintStyle: TextStyle(
                      color: scheme.onSurfaceVariant.withValues(alpha: 0.7),
                    ),
                    contentPadding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                ),
                Divider(color: AppColors.noteAccent(_color, theme.brightness)),
                const SizedBox(height: 8),
                TextField(
                  key: const Key('editor-content'),
                  controller: _contentController,
                  focusNode: _contentFocus,
                  keyboardType: TextInputType.multiline,
                  textCapitalization: TextCapitalization.sentences,
                  maxLines: null,
                  minLines: 12,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    fontSize: 17,
                    height: 1.6,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Start writing… / লেখা শুরু করুন…',
                    hintStyle: TextStyle(
                      color: scheme.onSurfaceVariant.withValues(alpha: 0.7),
                    ),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
