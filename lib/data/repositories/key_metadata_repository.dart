import 'package:hive_ce/hive_ce.dart';

import '../../core/errors/app_exceptions.dart';
import '../../core/errors/error_reporter.dart';
import '../models/key_metadata.dart';

/// Storage for key metadata. One record per key **version**: a logical key
/// (same `id`, same name) can have versions 1, 2, 3 … each with its own
/// record here and its own key material in `SecureKeyStore`.
///
/// Never stores key material.
abstract class KeyMetadataRepository {
  /// Storage key of one version's record, e.g. `k_abc@v2`.
  static String recordKey(String id, int version) => '$id@v$version';

  /// Every version of every key.
  Future<List<KeyMetadata>> getAll();

  /// Exactly this version of a key, or `null`.
  Future<KeyMetadata?> getVersion(String id, int version);

  /// All versions of one logical key, newest first.
  Future<List<KeyMetadata>> getVersions(String id);

  /// The version currently used by default for new encryption, if any.
  Future<KeyMetadata?> getActive();

  /// Stores a new version. The id + version pair must not exist yet.
  Future<void> create(KeyMetadata metadata);

  /// Replaces the existing record with the same id + version.
  Future<void> update(KeyMetadata metadata);

  /// Removes one version. Does nothing if it does not exist.
  Future<void> delete(String id, int version);
}

KeyMetadata? _pickActive(Iterable<KeyMetadata> all) {
  final active = all.where((k) => k.isActive).toList()
    ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  return active.isEmpty ? null : active.first;
}

List<KeyMetadata> _versionsOf(Iterable<KeyMetadata> all, String id) =>
    all.where((k) => k.id == id).toList()
      ..sort((a, b) => b.version.compareTo(a.version));

/// In-memory implementation for tests.
class InMemoryKeyMetadataRepository implements KeyMetadataRepository {
  InMemoryKeyMetadataRepository([Iterable<KeyMetadata> initial = const []]) {
    for (final k in initial) {
      _items[KeyMetadataRepository.recordKey(k.id, k.version)] = k;
    }
  }

  final Map<String, KeyMetadata> _items = {};

  @override
  Future<List<KeyMetadata>> getAll() async => List.unmodifiable(_items.values);

  @override
  Future<KeyMetadata?> getVersion(String id, int version) async =>
      _items[KeyMetadataRepository.recordKey(id, version)];

  @override
  Future<List<KeyMetadata>> getVersions(String id) async =>
      _versionsOf(_items.values, id);

  @override
  Future<KeyMetadata?> getActive() async => _pickActive(_items.values);

  @override
  Future<void> create(KeyMetadata metadata) async {
    final key = KeyMetadataRepository.recordKey(metadata.id, metadata.version);
    if (_items.containsKey(key)) {
      throw const DuplicateRecordException('This key version already exists.');
    }
    _items[key] = metadata;
  }

  @override
  Future<void> update(KeyMetadata metadata) async {
    final key = KeyMetadataRepository.recordKey(metadata.id, metadata.version);
    if (!_items.containsKey(key)) {
      throw const RecordNotFoundException('This key no longer exists.');
    }
    _items[key] = metadata;
  }

  @override
  Future<void> delete(String id, int version) async =>
      _items.remove(KeyMetadataRepository.recordKey(id, version));
}

/// [KeyMetadataRepository] backed by a Hive box. Records are stored under
/// [KeyMetadataRepository.recordKey] (schema v3 and later).
class HiveKeyMetadataRepository implements KeyMetadataRepository {
  HiveKeyMetadataRepository(this._box);

  final Box<KeyMetadata> _box;

  Future<T> _guard<T>(String failure, Future<T> Function() action) async {
    try {
      return await action();
    } on AppException {
      rethrow;
    } catch (error, stack) {
      ErrorReporter.report('HiveKeyMetadataRepository', error, stack);
      throw StorageException(failure, cause: error);
    }
  }

  @override
  Future<List<KeyMetadata>> getAll() => _guard(
    'Key information could not be loaded.',
    () async => _box.values.toList(),
  );

  @override
  Future<KeyMetadata?> getVersion(String id, int version) => _guard(
    'Key information could not be loaded.',
    () async => _box.get(KeyMetadataRepository.recordKey(id, version)),
  );

  @override
  Future<List<KeyMetadata>> getVersions(String id) async =>
      _versionsOf(await getAll(), id);

  @override
  Future<KeyMetadata?> getActive() async => _pickActive(await getAll());

  @override
  Future<void> create(
    KeyMetadata metadata,
  ) => _guard('Key information could not be saved.', () async {
    final key = KeyMetadataRepository.recordKey(metadata.id, metadata.version);
    if (_box.containsKey(key)) {
      throw const DuplicateRecordException('This key version already exists.');
    }
    await _box.put(key, metadata);
  });

  @override
  Future<void> update(KeyMetadata metadata) =>
      _guard('Key information could not be saved.', () async {
        final key = KeyMetadataRepository.recordKey(
          metadata.id,
          metadata.version,
        );
        if (!_box.containsKey(key)) {
          throw const RecordNotFoundException('This key no longer exists.');
        }
        await _box.put(key, metadata);
      });

  @override
  Future<void> delete(String id, int version) => _guard(
    'Key information could not be deleted.',
    () => _box.delete(KeyMetadataRepository.recordKey(id, version)),
  );
}
