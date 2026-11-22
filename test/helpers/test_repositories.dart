import 'package:cipher_note/core/errors/app_exceptions.dart';
import 'package:cipher_note/data/models/app_settings.dart';
import 'package:cipher_note/data/models/note_model.dart';
import 'package:cipher_note/data/repositories/note_repository.dart';
import 'package:cipher_note/data/repositories/settings_repository.dart';

/// In-memory note repository whose failures and calls can be controlled.
class ControllableNoteRepository extends InMemoryNoteRepository {
  ControllableNoteRepository([super.initialNotes]);

  bool failLoad = false;
  bool failWrites = false;
  bool failDeletes = false;
  int createCalls = 0;
  int updateCalls = 0;

  static const _writeError = StorageException('The note could not be saved.');

  @override
  Future<List<Note>> getAllNotes() async {
    if (failLoad) {
      throw const StorageException('Your notes could not be loaded.');
    }
    return super.getAllNotes();
  }

  @override
  Future<void> createNote(Note note) async {
    createCalls++;
    if (failWrites) throw _writeError;
    return super.createNote(note);
  }

  @override
  Future<void> updateNote(Note note) async {
    updateCalls++;
    if (failWrites) throw _writeError;
    return super.updateNote(note);
  }

  @override
  Future<void> deleteNote(String id) async {
    if (failDeletes) {
      throw const StorageException('The note could not be deleted.');
    }
    return super.deleteNote(id);
  }
}

/// Settings repository that can be told to fail and records saves.
class RecordingSettingsRepository implements SettingsRepository {
  RecordingSettingsRepository([this.stored = AppSettings.defaults]);

  AppSettings stored;
  bool failSaves = false;
  int saveCalls = 0;

  @override
  Future<AppSettings> load() async => stored;

  @override
  Future<void> save(AppSettings settings) async {
    saveCalls++;
    if (failSaves) {
      throw const StorageException('Your settings could not be saved.');
    }
    stored = settings;
  }
}
