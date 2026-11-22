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
import '../../../data/models/key_metadata.dart';
import '../../../data/models/note_model.dart';
import '../../encryption/data/note_encryption_service.dart';
import '../../encryption/presentation/key_dialogs.dart';
import '../../key_management/providers/key_provider.dart';
import '../../settings/providers/settings_provider.dart';
import '../providers/notes_provider.dart';
import '../widgets/note_color_picker.dart';

enum _EditorMenuAction { decrypt, edit, copy, lock, color, share, info, delete }

enum _LeaveChoice { save, discard, stay }

enum _FailedSaveChoice { retry, discard, stay }

enum _SaveStatus { idle, saving, saved, failed }

/// * plain: normal note.
/// * locked: encrypted; no text is shown. Decrypt is in the ⋮ menu.
/// * decrypted: an encrypted note decrypted into memory, read-only.
/// * editingDecrypted: the decrypted text is being edited. The stored note
///   stays encrypted until the user explicitly saves (encrypt again or
///   save as plain text).
enum _EditorMode { plain, locked, decrypted, editingDecrypted }

enum _UnlockedSaveChoice { encrypt, plain, discard, stay }

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

  _EditorMode _mode = _EditorMode.plain;

  /// True while encrypting or decrypting (blocks repeated taps).
  bool _busy = false;

  /// The stored encrypted note as it was when decrypted. Used to offer the
  /// same key version when encrypting again, and to detect if the stored
  /// note changed in the meantime.
  Note? _decryptedFrom;

  bool get _isDecrypted =>
      _mode == _EditorMode.decrypted || _mode == _EditorMode.editingDecrypted;

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
    if (existing != null && existing.isEncrypted) {
      _mode = _EditorMode.locked;
    }
    // Ciphertext is never loaded into the text fields.
    final readable = existing != null && !existing.isEncrypted;
    _savedTitle = _seenTitle = readable ? existing.title : '';
    _savedContent = _seenContent = readable ? existing.content : '';
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
    if (!_closing && _autoSaveOn && _hasUnsavedChanges) {
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
        _autoSaveOn &&
        _hasUnsavedChanges &&
        !_closing) {
      _commit();
    }
  }

  Note? get _note => _noteId == null ? null : _notes.getById(_noteId!);

  /// Auto-save only ever writes plain notes. Decrypted text is never saved
  /// automatically, so it cannot reach storage without an explicit choice.
  bool get _autoSaveOn => _settings.autoSave && _mode == _EditorMode.plain;

  bool get _isNew => _noteId == null;

  bool get _isSaving => _savesInFlight > 0;

  bool get _draftIsEmpty =>
      _titleController.text.trim().isEmpty &&
      _contentController.text.trim().isEmpty;

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
    if (_autoSaveOn) _scheduleAutoSave();
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
    // Only plain notes are saved here; encrypted notes are written by
    // [_encrypt] and [_saveUnlockedAsPlain].
    if (_mode != _EditorMode.plain) return false;
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
    if (_mode == _EditorMode.locked) {
      messenger.showSnackBar(
        const SnackBar(content: Text('This note is encrypted and saved.')),
      );
      return;
    }
    if (_mode == _EditorMode.decrypted) {
      messenger.showSnackBar(
        const SnackBar(content: Text('No changes. The note stays encrypted.')),
      );
      return;
    }
    if (_mode == _EditorMode.editingDecrypted) {
      final choice = await _askUnlockedSave(allowDiscard: false);
      if (choice != null) await _applyUnlockedChoice(choice);
      return;
    }
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

    if (_isDecrypted) {
      final choice = await _askUnlockedSave(allowDiscard: true);
      if (!mounted || choice == null) return;
      if (choice == _UnlockedSaveChoice.discard) {
        _close(navigator);
        return;
      }
      if (await _applyUnlockedChoice(choice) && mounted) _close(navigator);
      return;
    }

    if (_autoSaveOn) {
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
        if (_mode != _EditorMode.plain) {
          // The colour is not secret: change it without touching the
          // encrypted text.
          _saveColorOnly(value);
          return;
        }
        // An existing note updates on the home screen right away.
        if (_autoSaveOn && !(_isNew && _draftIsEmpty)) _commit();
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
    if (_mode == _EditorMode.locked) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Decrypt the note to share its text.')),
      );
      return;
    }
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
      ('Encryption', _encryptionDescription(note)),
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
      case _EditorMenuAction.decrypt:
        _decrypt();
      case _EditorMenuAction.edit:
        _startEditingDecrypted();
      case _EditorMenuAction.copy:
        _copyText();
      case _EditorMenuAction.lock:
        _lockAgain();
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

  String _encryptionDescription(Note? note) {
    if (note == null || !note.isEncrypted) return 'Not encrypted';
    final key = context.read<KeyProvider>().version(
      note.keyId,
      note.keyVersion,
    );
    final keyText = key == null
        ? 'key unavailable'
        : 'key “${key.name}” v${key.version}';
    return 'Hill Cipher 2×2, $keyText';
  }

  /// Puts text into the fields without it counting as an edit.
  void _setDraftText(String title, String content) {
    _savedTitle = _seenTitle = title;
    _savedContent = _seenContent = content;
    _titleController.text = title;
    _contentController.text = content;
  }

  Future<void> _saveColorOnly(int color) async {
    final id = _noteId;
    if (id == null) return;
    try {
      await _notes.changeColor(id, color);
      _savedColor = color;
    } on AppException catch (error) {
      if (!mounted) return;
      setState(() => _color = _savedColor);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  Future<void> _showError(String title, AppException error) => showInfoDialog(
    context,
    icon: Icons.error_outline_rounded,
    title: title,
    message: '${error.message}\n\nThe stored note has not been changed.',
  );

  /// Decrypts the stored note into the editor. The stored ciphertext is not
  /// changed.
  Future<void> _decrypt() async {
    final note = _note;
    if (_busy || _mode != _EditorMode.locked || note == null) return;
    if (!note.isEncrypted) return;
    final noteId = note.id;
    setState(() => _busy = true);
    try {
      final text = await context.read<NoteEncryptionService>().decrypt(note);
      // Ignore a late result if this editor moved on.
      if (!mounted || _noteId != noteId || _mode != _EditorMode.locked) return;
      setState(() {
        _setDraftText(text.title, text.content);
        _decryptedFrom = note;
        _mode = _EditorMode.decrypted;
      });
    } on AppException catch (error) {
      // Stop the progress indicator before showing the error.
      if (mounted) setState(() => _busy = false);
      if (mounted) await _showError('Could not decrypt', error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Encrypts the current text with a chosen key and stores it, replacing
  /// the stored note in a single write. Returns true on success. If
  /// anything fails, the stored note is unchanged.
  /// True from the moment Encrypt is tapped until the whole flow (save
  /// check, key choice, confirmation, encryption) ends. Blocks double taps.
  bool _encryptFlowActive = false;

  Future<bool> _encrypt() async {
    if (_busy || _encryptFlowActive) return false;
    _encryptFlowActive = true;
    try {
      return await _runEncryptFlow();
    } finally {
      _encryptFlowActive = false;
    }
  }

  Future<bool> _runEncryptFlow() async {
    final messenger = ScaffoldMessenger.of(context);
    final encryption = context.read<NoteEncryptionService>();

    // A plain note is saved first (write → save → encrypt): flush any
    // pending auto-save and continue only if it succeeded.
    if (_mode == _EditorMode.plain) {
      if (_isNew || _draftIsEmpty) return false;
      if (!await _commit()) {
        messenger.showSnackBar(SnackBar(content: Text(_saveErrorMessage)));
        return false;
      }
    }
    if (!mounted || !await _storedNoteIsCurrent()) return false;
    if (!mounted) return false;

    final KeyMetadata? key = await showKeyPicker(
      context,
      preselectedKeyId: _decryptedFrom?.keyId,
      preselectedVersion: _decryptedFrom?.keyVersion,
    );
    if (key == null || !mounted) return false;

    final confirmed = await showConfirmDialog(
      context,
      title: 'Encrypt This Note?',
      message:
          'This will replace the saved readable note content with encrypted '
          'content. You will need the key “${key.name}” (version '
          '${key.version}) to decrypt it.\n\n$hillCipherWarning',
      confirmLabel: 'Encrypt',
    );
    if (!confirmed || !mounted) return false;

    setState(() => _busy = true);
    try {
      // Check again right before encrypting: never encrypt stale content.
      if (!await _storedNoteIsCurrent()) return false;
      final stored = _note!;
      final title = _mode == _EditorMode.plain
          ? stored.title
          : _titleController.text;
      final content = _mode == _EditorMode.plain
          ? stored.content
          : _contentController.text;
      final encrypted = await encryption.encrypt(
        note: stored,
        title: title,
        content: content,
        key: key,
      );
      await _notes.replaceNote(encrypted);
      if (!mounted) return true;
      setState(() {
        _mode = _EditorMode.locked;
        _decryptedFrom = null;
        _setDraftText('', '');
        _savedColor = _color;
        _status = _SaveStatus.idle;
      });
      messenger.showSnackBar(
        SnackBar(content: Text('Note encrypted with “${key.name}”')),
      );
      return true;
    } on AppException catch (error) {
      // Stop the progress indicator before showing the error.
      if (mounted) setState(() => _busy = false);
      if (mounted) await _showError('Could not encrypt', error);
      return false;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Re-reads the note from storage and checks that it is still what this
  /// editor expects: for a plain note, saved and identical to the text on
  /// screen; for a decrypted note, the same encrypted record that was
  /// decrypted. Shows a message and returns false otherwise, so encryption
  /// never runs on stale or concurrently changed data.
  Future<bool> _storedNoteIsCurrent() async {
    final id = _noteId;
    if (id == null) return false;
    final Note? latest;
    try {
      latest = await _notes.reloadNote(id);
    } on AppException catch (error) {
      if (mounted) _snack(error.message);
      return false;
    }
    if (!mounted) return false;
    if (latest == null) {
      _snack('This note no longer exists.');
      return false;
    }
    final ok = _mode == _EditorMode.plain
        ? !latest.isEncrypted &&
              latest.title == _titleController.text &&
              latest.content == _contentController.text
        : latest == _decryptedFrom;
    if (!ok) {
      _snack(
        _mode == _EditorMode.plain
            ? 'The note has unsaved changes. Save it, then try again.'
            : 'The stored note changed. Close it and open it again.',
      );
    }
    return ok;
  }

  void _snack(String message) =>
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));

  void _startEditingDecrypted() {
    if (_mode != _EditorMode.decrypted) return;
    setState(() => _mode = _EditorMode.editingDecrypted);
    _contentFocus.requestFocus();
  }

  Future<void> _copyText() async {
    final text = [
      _titleController.text.trim(),
      _contentController.text.trim(),
    ].where((t) => t.isNotEmpty).join('\n\n');
    if (text.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) _snack('Note copied to clipboard');
  }

  /// Hides the decrypted text again without changing the stored note.
  Future<void> _lockAgain() async {
    if (!_isDecrypted || _busy) return;
    if (_hasUnsavedChanges) {
      final discard = await showConfirmDialog(
        context,
        title: 'Discard changes?',
        message:
            'Your changes have not been saved. Locking the note discards '
            'them; the stored encrypted note is not changed.',
        confirmLabel: 'Discard',
        destructive: true,
      );
      if (!discard || !mounted) return;
    }
    setState(() {
      _setDraftText('', '');
      _decryptedFrom = null;
      _mode = _EditorMode.locked;
    });
  }

  /// Saves a decrypted note as readable text (removes its encryption).
  Future<bool> _saveUnlockedAsPlain() async {
    final stored = _note;
    if (stored == null || _busy) return false;
    final confirmed = await showConfirmDialog(
      context,
      title: 'Save as plain text?',
      message:
          'This note will no longer be encrypted. Anyone who can open the '
          'app will be able to read it.',
      confirmLabel: 'Save as plain text',
    );
    if (!confirmed || !mounted) return false;
    setState(() => _busy = true);
    try {
      if (!await _storedNoteIsCurrent()) return false;
      final title = _titleController.text;
      final content = _contentController.text;
      await _notes.replaceNote(
        stored.toPlain(
          title: title,
          content: content,
          updatedAt: DateTime.now(),
        ),
      );
      if (!mounted) return true;
      setState(() {
        _mode = _EditorMode.plain;
        _decryptedFrom = null;
        _savedTitle = title;
        _savedContent = content;
        _status = _SaveStatus.saved;
      });
      return true;
    } on AppException catch (error) {
      // Stop the progress indicator before showing the error.
      if (mounted) setState(() => _busy = false);
      if (mounted) await _showError('Could not save', error);
      return false;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<_UnlockedSaveChoice?> _askUnlockedSave({required bool allowDiscard}) {
    return showDialog<_UnlockedSaveChoice>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.lock_open_rounded),
        title: const Text('Save changes?'),
        content: const Text(
          'This note is stored encrypted. Your changes are only kept while '
          'it is open. Encrypt it again to keep it locked, or save it as '
          'plain text.',
        ),
        actionsOverflowDirection: VerticalDirection.down,
        actionsOverflowButtonSpacing: 4,
        actions: [
          TextButton(
            onPressed: () =>
                Navigator.of(context).pop(_UnlockedSaveChoice.stay),
            child: const Text('Keep editing'),
          ),
          if (allowDiscard)
            TextButton(
              onPressed: () =>
                  Navigator.of(context).pop(_UnlockedSaveChoice.discard),
              child: const Text('Discard changes'),
            ),
          TextButton(
            onPressed: () =>
                Navigator.of(context).pop(_UnlockedSaveChoice.plain),
            child: const Text('Save as plain text'),
          ),
          FilledButton(
            key: const Key('encrypt-and-save'),
            onPressed: () =>
                Navigator.of(context).pop(_UnlockedSaveChoice.encrypt),
            child: const Text('Encrypt & save'),
          ),
        ],
      ),
    );
  }

  /// Returns true when the note was saved.
  Future<bool> _applyUnlockedChoice(_UnlockedSaveChoice choice) async {
    switch (choice) {
      case _UnlockedSaveChoice.encrypt:
        return _encrypt();
      case _UnlockedSaveChoice.plain:
        return _saveUnlockedAsPlain();
      case _UnlockedSaveChoice.discard:
      case _UnlockedSaveChoice.stay:
        return false;
    }
  }

  PopupMenuItem<_EditorMenuAction> _menuItem(
    _EditorMenuAction value,
    IconData icon,
    String label, {
    bool enabled = true,
    Color? color,
  }) => PopupMenuItem(
    key: ValueKey('menu-${value.name}'),
    value: value,
    enabled: enabled,
    child: ListTile(
      leading: Icon(icon, color: color),
      title: Text(label, style: color == null ? null : TextStyle(color: color)),
      contentPadding: EdgeInsets.zero,
      enabled: enabled,
    ),
  );

  /// The ⋮ menu. Decrypt is only offered here, and only for an encrypted
  /// note that is still locked.
  List<PopupMenuEntry<_EditorMenuAction>> _menuItems(ColorScheme scheme) {
    final idle = !_busy;
    final common = <PopupMenuEntry<_EditorMenuAction>>[
      _menuItem(
        _EditorMenuAction.color,
        Icons.palette_outlined,
        'Change color',
        enabled: idle,
      ),
      _menuItem(
        _EditorMenuAction.info,
        Icons.info_outline_rounded,
        'Note information',
      ),
      _menuItem(
        _EditorMenuAction.delete,
        Icons.delete_outline_rounded,
        'Delete',
        enabled: idle,
        color: scheme.error,
      ),
    ];
    switch (_mode) {
      case _EditorMode.plain:
        return [
          common[0],
          _menuItem(_EditorMenuAction.share, Icons.share_outlined, 'Share'),
          common[1],
          common[2],
        ];
      case _EditorMode.locked:
        return [
          _menuItem(
            _EditorMenuAction.decrypt,
            Icons.lock_open_rounded,
            _busy ? 'Decrypting…' : 'Decrypt Note',
            enabled: idle && _note != null,
          ),
          const PopupMenuDivider(),
          ...common,
        ];
      case _EditorMode.decrypted:
      case _EditorMode.editingDecrypted:
        return [
          if (_mode == _EditorMode.decrypted)
            _menuItem(
              _EditorMenuAction.edit,
              Icons.edit_outlined,
              'Edit',
              enabled: idle,
            ),
          _menuItem(_EditorMenuAction.copy, Icons.copy_rounded, 'Copy'),
          _menuItem(_EditorMenuAction.share, Icons.share_outlined, 'Share'),
          const PopupMenuDivider(),
          _menuItem(
            _EditorMenuAction.lock,
            Icons.lock_outline_rounded,
            'Lock note',
            enabled: idle,
          ),
          const PopupMenuDivider(),
          ...common,
        ];
    }
  }

  /// Bottom Encrypt button for plain notes. Shown only once the note exists
  /// in storage; enabled only when everything on screen is saved.
  Widget? _encryptBar(bool keyboardOpen) {
    if (_mode != _EditorMode.plain || keyboardOpen) return null;
    if (_isNew || _draftIsEmpty) return null;
    final failed = _status == _SaveStatus.failed;
    final pending = _isSaving || (_autoSaveOn && _hasUnsavedChanges);
    final dirty = _hasUnsavedChanges;
    final ready = !_busy && !failed && !pending && !dirty;
    final label = _busy
        ? 'Encrypting…'
        : failed
        ? 'Save failed'
        : pending
        ? 'Saving…'
        : dirty
        ? 'Save to encrypt'
        : 'Encrypt';
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
        // heightFactor 1: the bar is only as tall as the button.
        child: Align(
          heightFactor: 1,
          child: FilledButton.icon(
            key: const Key('encrypt-button'),
            onPressed: ready ? _encrypt : null,
            icon: _busy
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.lock_outline_rounded),
            label: Text(label),
          ),
        ),
      ),
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
    if (_mode == _EditorMode.locked) {
      status = note == null
          ? 'Encrypted'
          : 'Encrypted · Edited ${DateFormatter.full(note.updatedAt)}';
    } else if (_mode == _EditorMode.decrypted) {
      status = 'Decrypted · read only';
    } else if (_mode == _EditorMode.editingDecrypted) {
      status = _hasUnsavedChanges
          ? 'Decrypted · changes not saved yet'
          : 'Decrypted · stored encrypted';
    } else if (_status == _SaveStatus.failed) {
      status = 'Unable to save';
    } else if (_isSaving || (_autoSaveOn && _hasUnsavedChanges && !_closing)) {
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
            switch (_mode) {
              _EditorMode.locked => 'Encrypted note',
              _EditorMode.decrypted => 'Decrypted note',
              _EditorMode.editingDecrypted => 'Editing decrypted note',
              _EditorMode.plain => _isNew ? 'New note' : 'Edit note',
            },
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
              itemBuilder: (context) => _menuItems(scheme),
            ),
            const SizedBox(width: 4),
          ],
        ),
        bottomNavigationBar: _encryptBar(keyboardOpen),
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
                  isError:
                      _mode == _EditorMode.plain &&
                      _status == _SaveStatus.failed,
                  onRetry: _commit,
                ),
                const SizedBox(height: 8),
                if (_mode == _EditorMode.locked)
                  _LockedNoteView(busy: _busy)
                else ...[
                  if (_isDecrypted)
                    _UnlockedBanner(
                      editing: _mode == _EditorMode.editingDecrypted,
                    ),
                  TextField(
                    key: const Key('editor-title'),
                    controller: _titleController,
                    readOnly: _mode == _EditorMode.decrypted,
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
                  Divider(
                    color: AppColors.noteAccent(_color, theme.brightness),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    key: const Key('editor-content'),
                    controller: _contentController,
                    readOnly: _mode == _EditorMode.decrypted,
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

/// Shown instead of the text fields while a note is encrypted. It only
/// states that the note is encrypted: no key details and no Decrypt button
/// (Decrypt Note is in the ⋮ menu).
class _LockedNoteView extends StatelessWidget {
  const _LockedNoteView({required this.busy});

  final bool busy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      key: const Key('locked-view'),
      padding: const EdgeInsets.only(top: 48),
      child: Column(
        children: [
          Container(
            width: 88,
            height: 88,
            decoration: BoxDecoration(
              color: scheme.primary.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: busy
                ? Padding(
                    padding: const EdgeInsets.all(28),
                    child: CircularProgressIndicator(
                      strokeWidth: 3,
                      color: scheme.primary,
                    ),
                  )
                : Icon(Icons.lock_rounded, size: 40, color: scheme.primary),
          ),
          const SizedBox(height: 20),
          Text(
            busy ? 'Decrypting…' : 'Encrypted note',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// Reminds the user that decrypted text is not saved automatically.
class _UnlockedBanner extends StatelessWidget {
  const _UnlockedBanner({required this.editing});

  final bool editing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      key: const Key('unlocked-banner'),
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: scheme.primary.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(Icons.lock_open_rounded, size: 18, color: scheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              editing
                  ? 'Editing decrypted text. Changes are not saved until you '
                        'encrypt again or save as plain text.'
                  : 'Decrypted for reading. The stored note stays encrypted.',
              style: theme.textTheme.bodySmall?.copyWith(height: 1.35),
            ),
          ),
        ],
      ),
    );
  }
}
