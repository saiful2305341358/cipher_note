import 'package:flutter/foundation.dart';

import '../../../core/errors/app_exceptions.dart';
import '../../../core/errors/error_reporter.dart';
import '../../../core/utils/id_generator.dart';
import '../../../core/utils/note_search.dart';
import '../../../core/utils/text_utils.dart';
import '../../../data/models/app_settings.dart';
import '../../../data/models/note_model.dart';
import '../../../data/repositories/note_repository.dart';

export '../../../data/models/app_settings.dart' show NoteSortOrder;

/// App-facing note state. Screens read and change notes only through this
/// class; persistence is delegated to a [NoteRepository].
///
/// Every change is written to the repository first. The in-memory list and
/// the UI are updated only after the write succeeds, so the app never shows
/// a change as saved when it was not. Failed writes throw an
/// [AppException] for the caller to report.
class NotesProvider extends ChangeNotifier {
  NotesProvider(
    this._repository, {
    DateTime Function()? clock,
    String Function()? idGenerator,
  }) : _clock = clock ?? DateTime.now,
       _idGenerator = idGenerator ?? IdGenerator.generate;

  final NoteRepository _repository;
  final DateTime Function() _clock;
  final String Function() _idGenerator;

  final Map<String, Note> _notes = {};
  bool _isLoaded = false;
  bool _isLoading = false;
  AppException? _loadError;

  bool get isLoaded => _isLoaded;
  bool get isLoading => _isLoading;

  /// Set when the last [load] failed.
  AppException? get loadError => _loadError;

  /// All notes, most recently modified first.
  List<Note> get notes => sorted(NoteSortOrder.modified);

  int get count => _notes.length;

  bool get isEmpty => _notes.isEmpty;

  /// Loads notes from the repository. On failure [loadError] is set and the
  /// current list is kept.
  Future<void> load() async {
    _isLoading = true;
    _loadError = null;
    notifyListeners();
    try {
      final stored = await _repository.getAllNotes();
      _notes
        ..clear()
        ..addEntries(stored.map((n) => MapEntry(n.id, n)));
      _isLoaded = true;
    } on AppException catch (error) {
      _loadError = error;
    } catch (error, stack) {
      ErrorReporter.report('NotesProvider.load', error, stack);
      _loadError = StorageException(
        'Your notes could not be loaded.',
        cause: error,
      );
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Note? getById(String id) => _notes[id];

  /// Sorted lists by order, reused across rebuilds until the notes change.
  final Map<NoteSortOrder, List<Note>> _sortedCache = {};

  @override
  void notifyListeners() {
    // Every change to [_notes] is followed by a notification.
    _sortedCache.clear();
    super.notifyListeners();
  }

  /// Returns the notes ordered by [order]. The list is cached and must not
  /// be modified.
  List<Note> sorted(NoteSortOrder order) =>
      _sortedCache[order] ??= List.unmodifiable(_sort(order));

  List<Note> _sort(NoteSortOrder order) {
    final list = _notes.values.toList();
    switch (order) {
      case NoteSortOrder.modified:
        list.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      case NoteSortOrder.created:
        list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      case NoteSortOrder.title:
        // Normalise each title once, not on every comparison.
        final keys = {
          for (final n in list) n.id: TextUtils.searchKey(n.displayTitle),
        };
        list.sort((a, b) => keys[a.id]!.compareTo(keys[b.id]!));
      case NoteSortOrder.color:
        list.sort((a, b) {
          final byColor = a.color.compareTo(b.color);
          return byColor != 0 ? byColor : b.updatedAt.compareTo(a.updatedAt);
        });
    }
    return list;
  }

  /// Wraps unexpected errors so callers only ever see [AppException].
  Future<T> _write<T>(String failure, Future<T> Function() action) async {
    try {
      return await action();
    } on AppException {
      rethrow;
    } catch (error, stack) {
      ErrorReporter.report('NotesProvider', error, stack);
      throw StorageException(failure, cause: error);
    }
  }

  /// Creates and stores a new note with a new unique id.
  Future<Note> createNote({
    String title = '',
    String content = '',
    required int color,
  }) => _write('The note could not be saved.', () async {
    final now = _clock();
    final note = Note(
      id: _idGenerator(),
      title: title,
      content: content,
      color: color,
      createdAt: now,
      updatedAt: now,
    );
    await _repository.createNote(note);
    _notes[note.id] = note;
    notifyListeners();
    return note;
  });

  /// Updates an existing note. Only the given fields change; the id and
  /// creation time never change. The modified time is updated only when
  /// something actually changed.
  Future<Note> updateNote(
    String id, {
    String? title,
    String? content,
    int? color,
  }) => _write('The note could not be saved.', () async {
    final existing = _notes[id];
    if (existing == null) {
      throw const RecordNotFoundException('This note no longer exists.');
    }
    if (existing.isEncrypted && (title != null || content != null)) {
      // Writing readable text into an encrypted note would mix plaintext
      // and ciphertext. Use [replaceNote] with a fully encrypted or fully
      // plain note instead.
      throw const EncryptedNoteLockedException(
        'Decrypt this note before editing it.',
      );
    }
    final changed =
        (title != null && title != existing.title) ||
        (content != null && content != existing.content) ||
        (color != null && color != existing.color);
    if (!changed) return existing;

    final updated = existing.copyWith(
      title: title,
      content: content,
      color: color,
      updatedAt: _clock(),
    );
    await _repository.updateNote(updated);
    _notes[id] = updated;
    notifyListeners();
    return updated;
  });

  /// Stores [note] in place of the existing note with the same id, in one
  /// write. Used to switch a note between plain and encrypted: the previous
  /// version stays stored unless this write succeeds.
  Future<Note> replaceNote(Note note) =>
      _write('The note could not be saved.', () async {
        if (!_notes.containsKey(note.id)) {
          throw const RecordNotFoundException('This note no longer exists.');
        }
        await _repository.updateNote(note);
        _notes[note.id] = note;
        notifyListeners();
        return note;
      });

  /// Re-reads one note from storage (the source of truth) and updates the
  /// in-memory copy. Returns `null` if it no longer exists.
  Future<Note?> reloadNote(String id) =>
      _write('The note could not be loaded.', () async {
        final stored = await _repository.getNoteById(id);
        if (stored == null) {
          if (_notes.remove(id) != null) notifyListeners();
          return null;
        }
        if (_notes[id] != stored) {
          _notes[id] = stored;
          notifyListeners();
        }
        return stored;
      });

  /// Number of encrypted notes using exactly this key version.
  int notesUsingKey(String keyId, int version) => _notes.values
      .where(
        (n) => n.isEncrypted && n.keyId == keyId && n.keyVersion == version,
      )
      .length;

  /// Number of encrypted notes (they are not included in search).
  int get encryptedCount => _notes.values.where((n) => n.isEncrypted).length;

  /// Changes the colour of a note.
  Future<Note> changeColor(String id, int color) =>
      updateNote(id, color: color);

  /// Deletes a note and returns it (so it can be restored), or `null` if it
  /// did not exist.
  Future<Note?> deleteNote(String id) =>
      _write('The note could not be deleted.', () async {
        final existing = _notes[id];
        if (existing == null) return null;
        await _repository.deleteNote(id);
        _notes.remove(id);
        notifyListeners();
        return existing;
      });

  /// Puts a previously deleted note back, unchanged.
  Future<void> restoreNote(Note note) =>
      _write('The note could not be restored.', () async {
        if (_notes.containsKey(note.id)) {
          await _repository.updateNote(note);
        } else {
          await _repository.createNote(note);
        }
        _notes[note.id] = note;
        notifyListeners();
      });

  /// Deletes every note.
  Future<void> deleteAllNotes() =>
      _write('Your notes could not be deleted.', () async {
        await _repository.deleteAllNotes();
        _notes.clear();
        notifyListeners();
      });

  /// Notes whose title or content contains [query]. Runs on the loaded
  /// notes so results update instantly while typing; uses the same rules as
  /// [NoteRepository.searchNotes]. Encrypted notes are never matched.
  List<Note> search(String query) => NoteSearch.filter(_notes.values, query);
}
