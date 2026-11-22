import '../models/note_model.dart';

/// Storage abstraction for notes.
///
/// The UI talks only to `NotesProvider`, which talks only to this interface.
/// Phase 1 uses [InMemoryNoteRepository]; a Hive-backed implementation can
/// replace it later without touching any screen.
abstract class NoteRepository {
  /// Returns every stored note (in no particular order).
  Future<List<Note>> getAll();

  /// Returns the note with [id], or `null` if it does not exist.
  Future<Note?> getById(String id);

  /// Inserts [note], or replaces the stored note with the same id.
  Future<void> save(Note note);

  /// Removes the note with [id]. Does nothing if it does not exist.
  Future<void> delete(String id);
}

/// Keeps notes in memory for the current app session only.
/// Nothing is written to disk.
class InMemoryNoteRepository implements NoteRepository {
  InMemoryNoteRepository([Iterable<Note> initialNotes = const []]) {
    for (final note in initialNotes) {
      _notes[note.id] = note;
    }
  }

  final Map<String, Note> _notes = {};

  @override
  Future<List<Note>> getAll() async => List.unmodifiable(_notes.values);

  @override
  Future<Note?> getById(String id) async => _notes[id];

  @override
  Future<void> save(Note note) async => _notes[note.id] = note;

  @override
  Future<void> delete(String id) async => _notes.remove(id);
}
