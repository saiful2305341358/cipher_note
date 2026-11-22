import '../../../core/errors/app_exceptions.dart';
import '../../../core/errors/error_reporter.dart';
import '../../../core/utils/id_generator.dart';
import '../../../data/models/key_metadata.dart';
import '../../../data/repositories/key_metadata_repository.dart';
import '../../../data/repositories/note_repository.dart';
import '../../../data/repositories/secure_key_store.dart';
import '../domain/hill_key_matrix.dart';
import '../domain/key_generator.dart';

/// Creates, lists, loads and deletes Hill Cipher keys.
///
/// Key *material* goes only to [SecureKeyStore]; descriptive
/// [KeyMetadata] goes to the metadata repository (Hive). The two are linked
/// by key id and version.
class KeyService {
  KeyService({
    required this._metadata,
    required this._secureStore,
    required this._notes,
    KeyGenerator? generator,
    DateTime Function()? clock,
    String Function()? idGenerator,
  }) : _generator = generator ?? KeyGenerator(),
       _clock = clock ?? DateTime.now,
       _idGenerator = idGenerator ?? (() => IdGenerator.generate('k'));

  final KeyMetadataRepository _metadata;
  final SecureKeyStore _secureStore;
  final NoteRepository _notes;
  final KeyGenerator _generator;
  final DateTime Function() _clock;
  final String Function() _idGenerator;

  /// All keys, the active key first, then newest first.
  Future<List<KeyMetadata>> listKeys() async {
    final keys = (await _metadata.getAll()).toList()
      ..sort((x, y) {
        if (x.isActive != y.isActive) return x.isActive ? -1 : 1;
        return y.createdAt.compareTo(x.createdAt);
      });
    return keys;
  }

  /// Generates a new random key, stores its material securely and its
  /// metadata in Hive, and makes it the active key.
  ///
  /// If storing the metadata fails, the stored material is removed again so
  /// no orphan key is left behind.
  Future<KeyMetadata> createKey(String name) async {
    final String validName;
    try {
      validName = KeyMetadata.validateName(name);
    } on ArgumentError {
      throw const InvalidKeyException(
        'Enter a key name of 1 to ${KeyMetadata.maxNameLength} characters.',
      );
    }
    final matrix = _generator.generate();
    final metadata = KeyMetadata(
      id: _idGenerator(),
      name: validName,
      version: 1,
      algorithm: KeyMetadata.hillCipher2x2,
      createdAt: _clock(),
    );

    await _secureStore.write(
      keyId: metadata.id,
      version: metadata.version,
      material: matrix.toList(),
    );
    try {
      await _metadata.create(metadata);
    } catch (error) {
      try {
        await _secureStore.delete(
          keyId: metadata.id,
          version: metadata.version,
        );
      } catch (cleanupError, stack) {
        ErrorReporter.report(
          'KeyService.createKey cleanup',
          cleanupError,
          stack,
        );
      }
      rethrow;
    }
    await _deactivateOthers(metadata.id);
    return metadata;
  }

  /// Makes [keyId] the key used by default for new encryption.
  Future<void> setActive(String keyId) async {
    final key = await _metadata.getById(keyId);
    if (key == null) {
      throw const KeyUnavailableException('This key no longer exists.');
    }
    if (!key.isActive) await _metadata.update(key.copyWith(isActive: true));
    await _deactivateOthers(keyId);
  }

  Future<void> _deactivateOthers(String activeId) async {
    for (final other in await _metadata.getAll()) {
      if (other.id != activeId && other.isActive) {
        await _metadata.update(other.copyWith(isActive: false));
      }
    }
  }

  /// Loads and validates the key a note needs. Never falls back to a
  /// different key.
  Future<HillKeyMatrix> loadKey(String keyId, int version) async {
    final metadata = await _metadata.getById(keyId);
    if (metadata == null) {
      throw const KeyUnavailableException(
        'The key for this note was not found. It may have been deleted.',
      );
    }
    if (metadata.version != version) {
      throw const KeyUnavailableException(
        'This note needs a different version of its key.',
      );
    }
    if (metadata.algorithm != KeyMetadata.hillCipher2x2) {
      throw const KeyUnavailableException('This key type is not supported.');
    }
    final material = await _secureStore.read(keyId: keyId, version: version);
    if (material == null) {
      throw const KeyUnavailableException(
        'The key for this note is missing from secure storage.',
      );
    }
    try {
      return HillKeyMatrix.fromList(material);
    } on InvalidKeyException catch (error) {
      throw InvalidKeyException('The stored key is damaged.', cause: error);
    }
  }

  /// Number of stored notes encrypted with [keyId] (any version).
  Future<int> countNotesUsing(String keyId) async {
    final notes = await _notes.getAllNotes();
    return notes.where((n) => n.isEncrypted && n.keyId == keyId).length;
  }

  /// Deletes a key that no note uses. Throws [KeyInUseException] otherwise:
  /// a used key is never deleted.
  Future<void> deleteKey(String keyId) async {
    final key = await _metadata.getById(keyId);
    if (key == null) return;
    final count = await countNotesUsing(keyId);
    if (count > 0) {
      throw KeyInUseException(
        count == 1
            ? '1 encrypted note uses this key.'
            : '$count encrypted notes use this key.',
        noteCount: count,
      );
    }
    await _secureStore.delete(keyId: key.id, version: key.version);
    await _metadata.delete(key.id);
  }
}
