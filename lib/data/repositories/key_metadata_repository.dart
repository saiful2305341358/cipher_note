import 'package:hive_ce/hive_ce.dart';

import '../../core/errors/app_exceptions.dart';
import '../../core/errors/error_reporter.dart';
import '../models/key_metadata.dart';

/// Storage for key metadata. Kept separate from notes so key handling can
/// evolve on its own. It never stores key material; see `SecureKeyStore`.
abstract class KeyMetadataRepository {
  Future<List<KeyMetadata>> getAll();

  Future<KeyMetadata?> getById(String id);

  /// The key currently used for new encrypted notes, if any.
  Future<KeyMetadata?> getActive();

  /// Stores a new record. Its id must not exist yet.
  Future<void> create(KeyMetadata metadata);

  /// Replaces an existing record with the same id.
  Future<void> update(KeyMetadata metadata);

  Future<void> delete(String id);
}

KeyMetadata? _pickActive(Iterable<KeyMetadata> all) {
  final active = all.where((k) => k.isActive).toList()
    ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  return active.isEmpty ? null : active.first;
}

/// In-memory implementation for tests.
class InMemoryKeyMetadataRepository implements KeyMetadataRepository {
  InMemoryKeyMetadataRepository([Iterable<KeyMetadata> initial = const []]) {
    for (final k in initial) {
      _items[k.id] = k;
    }
  }

  final Map<String, KeyMetadata> _items = {};

  @override
  Future<List<KeyMetadata>> getAll() async => List.unmodifiable(_items.values);

  @override
  Future<KeyMetadata?> getById(String id) async => _items[id];

  @override
  Future<KeyMetadata?> getActive() async => _pickActive(_items.values);

  @override
  Future<void> create(KeyMetadata metadata) async {
    if (_items.containsKey(metadata.id)) {
      throw const DuplicateRecordException('This key already exists.');
    }
    _items[metadata.id] = metadata;
  }

  @override
  Future<void> update(KeyMetadata metadata) async {
    if (!_items.containsKey(metadata.id)) {
      throw const RecordNotFoundException('This key no longer exists.');
    }
    _items[metadata.id] = metadata;
  }

  @override
  Future<void> delete(String id) async => _items.remove(id);
}

/// [KeyMetadataRepository] backed by a Hive box, keyed by metadata id.
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
  Future<KeyMetadata?> getById(String id) =>
      _guard('Key information could not be loaded.', () async => _box.get(id));

  @override
  Future<KeyMetadata?> getActive() async => _pickActive(await getAll());

  @override
  Future<void> create(KeyMetadata metadata) =>
      _guard('Key information could not be saved.', () async {
        if (_box.containsKey(metadata.id)) {
          throw const DuplicateRecordException('This key already exists.');
        }
        await _box.put(metadata.id, metadata);
      });

  @override
  Future<void> update(KeyMetadata metadata) =>
      _guard('Key information could not be saved.', () async {
        if (!_box.containsKey(metadata.id)) {
          throw const RecordNotFoundException('This key no longer exists.');
        }
        await _box.put(metadata.id, metadata);
      });

  @override
  Future<void> delete(String id) =>
      _guard('Key information could not be deleted.', () => _box.delete(id));
}
