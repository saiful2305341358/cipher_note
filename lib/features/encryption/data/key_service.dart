import '../../../core/errors/app_exceptions.dart';
import '../../../core/errors/error_reporter.dart';
import '../../../core/utils/id_generator.dart';
import '../../../data/models/key_metadata.dart';
import '../../../data/repositories/key_metadata_repository.dart';
import '../../../data/repositories/note_repository.dart';
import '../../../data/repositories/secure_key_store.dart';
import '../domain/hill_key_matrix.dart';
import '../domain/key_generator.dart';

/// Result of checking whether a key version can be used.
enum KeyValidationStatus {
  valid('Ready to use'),
  missingMetadata('This key version no longer exists.'),
  unsupportedAlgorithm('This key type is not supported.'),
  missingMaterial('The key is missing from secure storage.'),
  invalidMatrix('The stored key is damaged and cannot be used.'),
  storageFailure('Secure storage could not be read.');

  const KeyValidationStatus(this.message);

  /// Short, user-facing explanation (never contains key values).
  final String message;

  bool get isValid => this == valid;
}

/// Creates, versions, validates, loads and deletes Hill Cipher keys.
///
/// A *logical key* has one id and name and one or more *versions*. Each
/// version has its own random matrix in [SecureKeyStore]
/// (`hill_key_<id>_v<version>`) and its own metadata record (Hive). Older
/// versions are never overwritten, so notes encrypted with them stay
/// readable. Exactly one version (of any key) is *active*: the default for
/// new encryption.
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

  /// Algorithms this app can use.
  static const Set<String> supportedAlgorithms = {KeyMetadata.hillCipher2x2};

  /// Every key version: grouped by key (newest key first), versions
  /// newest first.
  Future<List<KeyMetadata>> listKeys() async {
    final all = await _metadata.getAll();
    final newestByKey = <String, DateTime>{};
    for (final k in all) {
      final current = newestByKey[k.id];
      if (current == null || k.createdAt.isAfter(current)) {
        newestByKey[k.id] = k.createdAt;
      }
    }
    return all.toList()..sort((x, y) {
      if (x.id != y.id) {
        return newestByKey[y.id]!.compareTo(newestByKey[x.id]!);
      }
      return y.version.compareTo(x.version);
    });
  }

  /// Creates a new logical key (version 1) and makes it active.
  Future<KeyMetadata> createKey(String name) async {
    final String validName;
    try {
      validName = KeyMetadata.validateName(name);
    } on ArgumentError {
      throw const InvalidKeyException(
        'Enter a key name of 1 to ${KeyMetadata.maxNameLength} characters.',
      );
    }
    return _storeNewVersion(
      KeyMetadata(
        id: _idGenerator(),
        name: validName,
        version: 1,
        algorithm: KeyMetadata.hillCipher2x2,
        createdAt: _clock(),
      ),
    );
  }

  /// Adds the next version to an existing key, with a new random matrix,
  /// and makes it active. Older versions are kept unchanged.
  Future<KeyMetadata> createNewVersion(String keyId) async {
    final versions = await _metadata.getVersions(keyId);
    if (versions.isEmpty) {
      throw const KeyUnavailableException('This key no longer exists.');
    }
    final latest = versions.first;
    return _storeNewVersion(
      KeyMetadata(
        id: keyId,
        name: latest.name,
        version: latest.version + 1,
        algorithm: latest.algorithm,
        createdAt: _clock(),
      ),
    );
  }

  /// Stores material first, then metadata, then switches the active key.
  /// A failure at any step leaves no partial version behind.
  Future<KeyMetadata> _storeNewVersion(KeyMetadata metadata) async {
    // Never overwrite existing material for this id + version.
    final existing = await _secureStore.read(
      keyId: metadata.id,
      version: metadata.version,
    );
    if (existing != null ||
        await _metadata.getVersion(metadata.id, metadata.version) != null) {
      throw const DuplicateRecordException('This key version already exists.');
    }

    final matrix = _generator.generate();
    await _secureStore.write(
      keyId: metadata.id,
      version: metadata.version,
      material: matrix.toList(),
    );
    try {
      await _metadata.create(metadata);
    } catch (error) {
      await _removeMaterialQuietly(metadata.id, metadata.version);
      rethrow;
    }
    await _deactivateOthers(metadata.id, metadata.version);
    return metadata;
  }

  Future<void> _removeMaterialQuietly(String id, int version) async {
    try {
      await _secureStore.delete(keyId: id, version: version);
    } catch (error, stack) {
      ErrorReporter.report('KeyService cleanup', error.runtimeType, stack);
    }
  }

  /// Makes this exact key version the default for new encryption.
  Future<void> setActive(String keyId, int version) async {
    final key = await _metadata.getVersion(keyId, version);
    if (key == null) {
      throw const KeyUnavailableException('This key version no longer exists.');
    }
    if (!key.isActive) await _metadata.update(key.copyWith(isActive: true));
    await _deactivateOthers(keyId, version);
  }

  Future<void> _deactivateOthers(String activeId, int activeVersion) async {
    for (final other in await _metadata.getAll()) {
      final isTarget = other.id == activeId && other.version == activeVersion;
      if (!isTarget && other.isActive) {
        await _metadata.update(other.copyWith(isActive: false));
      }
    }
  }

  /// Checks that a key version can be used, without throwing.
  Future<KeyValidationStatus> validate(String keyId, int version) async {
    try {
      await loadKey(keyId, version);
      return KeyValidationStatus.valid;
    } on SecureStorageException {
      return KeyValidationStatus.storageFailure;
    } on InvalidKeyException {
      return KeyValidationStatus.invalidMatrix;
    } on KeyUnavailableException catch (error) {
      return switch (error.reason) {
        KeyUnavailableReason.unsupportedAlgorithm =>
          KeyValidationStatus.unsupportedAlgorithm,
        KeyUnavailableReason.missingMaterial =>
          KeyValidationStatus.missingMaterial,
        _ => KeyValidationStatus.missingMetadata,
      };
    } on AppException {
      return KeyValidationStatus.storageFailure;
    }
  }

  /// Loads and fully validates exactly [keyId] version [version]:
  /// metadata exists and matches, the algorithm is supported, the material
  /// exists in secure storage, has four values in 0–255, and is invertible
  /// modulo 256. Never falls back to a different key or version.
  Future<HillKeyMatrix> loadKey(String keyId, int version) async {
    final metadata = await _metadata.getVersion(keyId, version);
    if (metadata == null) {
      final others = await _metadata.getVersions(keyId);
      throw KeyUnavailableException(
        others.isEmpty
            ? 'The key for this note was not found. It may have been deleted.'
            : 'Version $version of the key “${others.first.name}” is not '
                  'on this device.',
        reason: KeyUnavailableReason.missingMetadata,
      );
    }
    if (metadata.id != keyId || metadata.version != version) {
      throw const KeyUnavailableException(
        'The key information does not match this note.',
        reason: KeyUnavailableReason.missingMetadata,
      );
    }
    if (!supportedAlgorithms.contains(metadata.algorithm)) {
      throw const KeyUnavailableException(
        'This key type is not supported.',
        reason: KeyUnavailableReason.unsupportedAlgorithm,
      );
    }
    final material = await _secureStore.read(keyId: keyId, version: version);
    if (material == null) {
      throw const KeyUnavailableException(
        'The key is missing from secure storage.',
        reason: KeyUnavailableReason.missingMaterial,
      );
    }
    try {
      final matrix = HillKeyMatrix.fromList(material);
      matrix.inverse(); // must be computable
      return matrix;
    } on InvalidKeyException catch (error) {
      throw InvalidKeyException('The stored key is damaged.', cause: error);
    } on ArgumentError catch (error) {
      throw InvalidKeyException(
        'The stored key is damaged.',
        cause: error.runtimeType,
      );
    }
  }

  /// Number of stored encrypted notes that need exactly this key version.
  Future<int> countNotesUsing(String keyId, int version) async {
    final notes = await _notes.getAllNotes();
    return notes
        .where(
          (n) => n.isEncrypted && n.keyId == keyId && n.keyVersion == version,
        )
        .length;
  }

  /// Deletes one unused key version (material and metadata). Other
  /// versions of the same key are kept. Throws [KeyInUseException] if any
  /// note uses this version.
  Future<void> deleteVersion(String keyId, int version) async {
    final key = await _metadata.getVersion(keyId, version);
    if (key == null) return;
    final count = await countNotesUsing(keyId, version);
    if (count > 0) {
      throw KeyInUseException(
        count == 1
            ? '1 encrypted note uses this key version.'
            : '$count encrypted notes use this key version.',
        noteCount: count,
      );
    }
    await _secureStore.delete(keyId: keyId, version: version);
    await _metadata.delete(keyId, version);

    // If the active version was removed, the newest remaining version of
    // the same key becomes active.
    if (key.isActive) {
      final remaining = await _metadata.getVersions(keyId);
      if (remaining.isNotEmpty) {
        await setActive(keyId, remaining.first.version);
      }
    }
  }
}
