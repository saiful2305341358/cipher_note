import '../../core/errors/app_exceptions.dart';
import '../../core/utils/note_search.dart';
import '../models/note_model.dart';

/// Storage abstraction for notes.
///
/// The UI talks only to `NotesProvider`, which talks only to this interface.
/// The app uses `HiveNoteRepository`; [InMemoryNoteRepository] is used by
/// tests.
///
/// Implementations throw [StorageException] when the storage fails,
/// [DuplicateRecordException] when creating an id that already exists, and
/// [RecordNotFoundException] when updating a note that does not exist.
abstract class NoteRepository {
  /// Returns every stored note (in no particular order).
  Future<List<Note>> getAllNotes();

  /// Returns the note with [id], or `null` if it does not exist.
  Future<Note?> getNoteById(String id);

  /// Stores a new note. Its id must not exist yet.
  Future<void> createNote(Note note);

  /// Replaces an existing note with the same id.
  Future<void> updateNote(Note note);

  /// Removes the note with [id]. Does nothing if it does not exist.
  Future<void> deleteNote(String id);

  /// Removes every note.
  Future<void> deleteAllNotes();

  /// Notes whose title or content contains [query]. See [NoteSearch].
  Future<List<Note>> searchNotes(String query);
}

/// Keeps notes in memory only. Used by tests; nothing is written to disk.
class InMemoryNoteRepository implements NoteRepository {
  InMemoryNoteRepository([Iterable<Note> initialNotes = const []]) {
    for (final note in initialNotes) {
      _notes[note.id] = note;
    }
  }

  final Map<String, Note> _notes = {};

  @override
  Future<List<Note>> getAllNotes() async => List.unmodifiable(_notes.values);

  @override
  Future<Note?> getNoteById(String id) async => _notes[id];

  @override
  Future<void> createNote(Note note) async {
    if (_notes.containsKey(note.id)) {
      throw const DuplicateRecordException('This note already exists.');
    }
    _notes[note.id] = note;
  }

  @override
  Future<void> updateNote(Note note) async {
    if (!_notes.containsKey(note.id)) {
      throw const RecordNotFoundException('This note no longer exists.');
    }
    _notes[note.id] = note;
  }

  @override
  Future<void> deleteNote(String id) async => _notes.remove(id);

  @override
  Future<void> deleteAllNotes() async => _notes.clear();

  @override
  Future<List<Note>> searchNotes(String query) async =>
      NoteSearch.filter(_notes.values, query);
}
