import 'dart:async';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/errors/app_exceptions.dart';
import '../../../core/errors/error_reporter.dart';
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

enum _FailedSaveChoice { retry, discard, stay }

enum _SaveStatus { idle, saving, saved, failed }

/// Creates a new note ([noteId] is null) or edits an existing one.
///
/// Edits are kept in a local draft. With auto-save on (the default), the
/// draft is saved shortly after typing pauses, when the app goes to the
/// background and before leaving the screen. With auto-save off, leaving
/// with unsaved changes asks the user to Save or Discard. If a save fails,
/// the user is told and changes are never dropped without asking.
class NoteEditorScreen extends StatefulWidget {
  const NoteEditorScreen({super.key, this.noteId});

  final String? noteId;

  @override
  State<NoteEditorScreen> createState() => _NoteEditorScreenState();
}

class _NoteEditorScreenState extends State<NoteEditorScreen>
    with WidgetsBindingObserver {
  late final NotesProvider _notes;
  late final SettingsProvider _settings;
  late final TextEditingController _titleController;
  late final TextEditingController _contentController;
  final FocusNode _contentFocus = FocusNode();

  String? _noteId;
  late int _color;

  // Last values successfully written to storage.
  late String _savedTitle;
  late String _savedContent;
  late int _savedColor;

  // Last text seen by the change listener (it also fires for cursor moves).
  late String _seenTitle;
  late String _seenContent;

  Timer? _autoSaveTimer;

  /// Saves run strictly one after another through this chain, so two saves
  /// never overlap and a new note is never created twice.
  Future<bool> _saveChain = Future.value(true);
  int _savesInFlight = 0;
  _SaveStatus _status = _SaveStatus.idle;
  AppException? _saveError;
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _notes = context.read<NotesProvider>();
    _settings = context.read<SettingsProvider>();

    final existing = widget.noteId == null
        ? null
        : _notes.getById(widget.noteId!);
    _noteId = existing?.id;
    _savedTitle = _seenTitle = existing?.title ?? '';
    _savedContent = _seenContent = existing?.content ?? '';
    _savedColor = existing?.color ?? _settings.defaultNoteColor;
    _color = _savedColor;

    _titleController = TextEditingController(text: _savedTitle)
      ..addListener(_onTextChanged);
    _contentController = TextEditingController(text: _savedContent)
      ..addListener(_onTextChanged);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _autoSaveTimer?.cancel();
    // Safety net: if the screen is removed some other way while auto-save
    // is on, still store the latest draft.
    if (!_closing && _settings.autoSave && _hasUnsavedChanges) {
      _saveDraftAfterDispose();
    }
    _titleController.dispose();
    _contentController.dispose();
    _contentFocus.dispose();
    super.dispose();
  }

  void _saveDraftAfterDispose() {
    final id = _noteId;
    final title = _titleController.text;
    final content = _contentController.text;
    final color = _color;
    _saveChain.then((_) async {
      try {
        if (id == null) {
          await _notes.createNote(title: title, content: content, color: color);
        } else {
          await _notes.updateNote(
            id,
            title: title,
            content: content,
            color: color,
          );
        }
      } on AppException catch (error, stack) {
        ErrorReporter.report('NoteEditor.dispose', error, stack);
      }
    });
  }

  /// Saves right away when the app goes to the background, so changes are
  /// not lost if the system closes the app.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed &&
        _settings.autoSave &&
        _hasUnsavedChanges &&
        !_closing) {
      _commit();
    }
  }

  Note? get _note => _noteId == null ? null : _notes.getById(_noteId!);

  bool get _isNew => _noteId == null;

  bool get _isSaving => _savesInFlight > 0;

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
    final title = _titleController.text;
    final content = _contentController.text;
    if (title == _seenTitle && content == _seenContent) return;
    _seenTitle = title;
    _seenContent = content;
    // Rebuild so the Encrypt button, status and pop guard stay up to date.
    setState(() {});
    if (_settings.autoSave) _scheduleAutoSave();
  }

  /// Debounce: write once typing pauses instead of on every keystroke.
  void _scheduleAutoSave() {
    _autoSaveTimer?.cancel();
    _autoSaveTimer = Timer(AppConstants.autoSaveDelay, _commit);
  }

  /// Queues a save of the current draft. Completes with `true` when the
  /// draft is stored (or there was nothing to store), `false` on failure.
  Future<bool> _commit() {
    _autoSaveTimer?.cancel();
    final run = _saveChain.then((_) => _performSave());
    _saveChain = run;
    return run;
  }

  Future<bool> _performSave() async {
    if (!_hasUnsavedChanges) return true;
    final title = _titleController.text;
    final content = _contentController.text;
    final color = _color;

    _savesInFlight++;
    _setStatus(_SaveStatus.saving);
    try {
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
      _saveError = null;
      _savesInFlight--;
      _setStatus(_SaveStatus.saved);
      return true;
    } on AppException catch (error) {
      _saveError = error;
      _savesInFlight--;
      _setStatus(_SaveStatus.failed);
      return false;
    }
  }

  void _setStatus(_SaveStatus status) {
    _status = status;
    if (mounted) setState(() {});
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
    final ok = await _commit();
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(ok ? 'Note saved' : _saveErrorMessage),
          duration: const Duration(seconds: 2),
        ),
      );
  }

  String get _saveErrorMessage =>
      _saveError?.message ?? 'The note could not be saved.';

  Future<void> _handlePop(bool didPop) async {
    if (didPop || _closing) return;
    final navigator = Navigator.of(context);

    if (!_hasUnsavedChanges && !_isSaving) {
      _close(navigator);
      return;
    }

    if (_settings.autoSave) {
      // Flush the pending autosave before leaving.
      while (mounted) {
        if (await _commit()) {
          _close(navigator);
          return;
        }
        if (!mounted) return;
        final choice = await _askAfterFailedSave();
        if (choice == _FailedSaveChoice.discard) {
          _close(navigator);
          return;
        }
        if (choice != _FailedSaveChoice.retry) return;
      }
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
        if (await _commit()) {
          _close(navigator);
        } else if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(_saveErrorMessage)));
        }
      case _LeaveChoice.discard:
        _close(navigator);
      case _LeaveChoice.stay || null:
        break;
    }
  }

  /// Asked when leaving fails to save. Changes are only dropped if the user
  /// explicitly chooses to discard them.
  Future<_FailedSaveChoice?> _askAfterFailedSave() => showDialog(
    context: context,
    builder: (context) => AlertDialog(
      icon: Icon(
        Icons.error_outline_rounded,
        color: Theme.of(context).colorScheme.error,
      ),
      title: const Text('Unable to save'),
      content: Text(
        '$_saveErrorMessage\n\nIf you leave now, your latest changes '
        'will be lost.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(_FailedSaveChoice.stay),
          child: const Text('Keep editing'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(_FailedSaveChoice.discard),
          child: const Text('Discard changes'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_FailedSaveChoice.retry),
          child: const Text('Try again'),
        ),
      ],
    ),
  );

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
    // Let any running save finish first so it cannot re-create the note.
    _autoSaveTimer?.cancel();
    await _saveChain;
    if (!mounted) return;
    final id = _noteId;
    if (id == null) {
      _close(navigator);
      return;
    }

    final Note? removed;
    try {
      removed = await _notes.deleteNote(id);
    } on AppException catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(error.message)));
      return;
    }
    if (!mounted) return;
    _close(navigator);
    if (removed == null) return;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: const Text('Note deleted'),
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () async {
              try {
                await _notes.restoreNote(removed!);
              } on AppException catch (error) {
                messenger.showSnackBar(SnackBar(content: Text(error.message)));
              }
            },
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
      ('Storage', note == null ? 'Not saved yet' : 'Saved on this device'),
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
    if (_status == _SaveStatus.failed) {
      status = 'Unable to save';
    } else if (_isSaving ||
        (_settings.autoSave && _hasUnsavedChanges && !_closing)) {
      status = 'Saving…';
    } else if (_hasUnsavedChanges) {
      status = 'Unsaved changes';
    } else if (note == null) {
      status = 'New note';
    } else if (_status == _SaveStatus.saved) {
      status = 'Saved · Edited ${DateFormatter.full(note.updatedAt)}';
    } else {
      status = 'Edited ${DateFormatter.full(note.updatedAt)}';
    }

    return PopScope<Object?>(
      // Every back action goes through [_handlePop] so pending changes are
      // always checked, even if the user leaves within the same frame.
      canPop: _closing,
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
                _SaveStatusLine(
                  text: status,
                  isError: _status == _SaveStatus.failed,
                  onRetry: _commit,
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

/// Small status text under the app bar ("Saving…", "Saved", errors).
class _SaveStatusLine extends StatelessWidget {
  const _SaveStatusLine({
    required this.text,
    required this.isError,
    required this.onRetry,
  });

  final String text;
  final bool isError;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final style = theme.textTheme.labelSmall?.copyWith(
      color: isError ? scheme.error : scheme.onSurfaceVariant,
      fontWeight: isError ? FontWeight.w600 : null,
    );
    if (!isError) {
      return Text(text, key: const Key('editor-status'), style: style);
    }
    return Row(
      children: [
        Icon(Icons.error_outline_rounded, size: 14, color: scheme.error),
        const SizedBox(width: 4),
        Flexible(
          child: Text(text, key: const Key('editor-status'), style: style),
        ),
        TextButton(
          key: const Key('editor-retry'),
          onPressed: onRetry,
          style: TextButton.styleFrom(
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.symmetric(horizontal: 8),
          ),
          child: const Text('Retry'),
        ),
      ],
    );
  }
}
