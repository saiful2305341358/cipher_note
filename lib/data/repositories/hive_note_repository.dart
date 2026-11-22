import 'package:hive_ce/hive_ce.dart';

import '../../core/errors/app_exceptions.dart';
import '../../core/errors/error_reporter.dart';
import '../../core/utils/note_search.dart';
import '../models/note_model.dart';
import 'note_repository.dart';

/// [NoteRepository] backed by a Hive box. Each note is stored under its id.
class HiveNoteRepository implements NoteRepository {
  HiveNoteRepository(this._box);

  final Box<Note> _box;

  /// Runs [action] and converts storage errors into [StorageException].
  Future<T> _guard<T>(String failure, Future<T> Function() action) async {
    try {
      return await action();
    } on AppException {
      rethrow;
    } catch (error, stack) {
      ErrorReporter.report('HiveNoteRepository', error, stack);
      throw StorageException(failure, cause: error);
    }
  }

  /// Ensures the note's id matches the key it is stored under (repairs
  /// records whose id field was lost).
  Note _withKey(dynamic key, Note note) =>
      key is String && note.id != key ? note.copyWith(id: key) : note;

  static void _checkId(String id) {
    if (id.trim().isEmpty) {
      throw const StorageException('This note has no id and cannot be saved.');
    }
  }

  @override
  Future<List<Note>> getAllNotes() =>
      _guard('Your notes could not be loaded.', () async {
        final notes = <Note>[];
        for (final key in _box.keys) {
          final note = _box.get(key);
          if (note != null) notes.add(_withKey(key, note));
        }
        return notes;
      });

  @override
  Future<Note?> getNoteById(String id) =>
      _guard('This note could not be loaded.', () async {
        final note = _box.get(id);
        return note == null ? null : _withKey(id, note);
      });

  @override
  Future<void> createNote(Note note) =>
      _guard('The note could not be saved.', () async {
        _checkId(note.id);
        if (_box.containsKey(note.id)) {
          throw const DuplicateRecordException('This note already exists.');
        }
        await _box.put(note.id, note);
      });

  @override
  Future<void> updateNote(Note note) =>
      _guard('The note could not be saved.', () async {
        _checkId(note.id);
        if (!_box.containsKey(note.id)) {
          throw const RecordNotFoundException('This note no longer exists.');
        }
        await _box.put(note.id, note);
      });

  @override
  Future<void> deleteNote(String id) =>
      _guard('The note could not be deleted.', () => _box.delete(id));

  @override
  Future<void> deleteAllNotes() =>
      _guard('Your notes could not be deleted.', () => _box.clear());

  @override
  Future<List<Note>> searchNotes(String query) async {
    if (NoteSearch.isBlank(query)) return const [];
    return NoteSearch.filter(await getAllNotes(), query);
  }
}
