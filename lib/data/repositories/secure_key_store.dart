import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../core/errors/app_exceptions.dart';
import '../../core/errors/error_reporter.dart';

/// Where key material (the four cipher matrix values) is kept.
///
/// Key material is never written to Hive; Hive only holds descriptive
/// `KeyMetadata`. Each key version has its own entry, named by
/// [storageKeyFor].
abstract class SecureKeyStore {
  /// Entry name for one key version, e.g. `hill_key_k_abc123_v1`.
  static String storageKeyFor(String keyId, int version) =>
      'hill_key_${keyId}_v$version';

  Future<void> write({
    required String keyId,
    required int version,
    required List<int> material,
  });

  /// Returns key material, or `null` if none is stored.
  Future<List<int>?> read({required String keyId, required int version});

  Future<void> delete({required String keyId, required int version});
}

/// Encodes material as comma-separated byte values.
String _encode(List<int> material) => material.join(',');

List<int> _decode(String value) {
  final parts = value.split(',');
  final bytes = <int>[];
  for (final part in parts) {
    final v = int.tryParse(part);
    if (v == null || v < 0 || v > 255) {
      throw const InvalidKeyException('The stored key is damaged.');
    }
    bytes.add(v);
  }
  return bytes;
}

/// [SecureKeyStore] backed by platform secure storage (`flutter_secure_storage`:
/// Android Keystore-protected encryption on Android).
class FlutterSecureKeyStore implements SecureKeyStore {
  FlutterSecureKeyStore([FlutterSecureStorage? storage])
    : _storage = storage ?? const FlutterSecureStorage(aOptions: _android);

  /// `resetOnError: false` — the plugin's default would wipe *all* stored
  /// keys after a read error, silently making every encrypted note
  /// unreadable. Failing loudly is safer.
  static const AndroidOptions _android = AndroidOptions(resetOnError: false);

  final FlutterSecureStorage _storage;

  Future<T> _guard<T>(String failure, Future<T> Function() action) async {
    try {
      return await action();
    } on AppException {
      rethrow;
    } on PlatformException catch (error, stack) {
      // Report the error code only; messages may echo stored values.
      ErrorReporter.report('SecureKeyStore', error.code, stack);
      throw SecureStorageException(failure, cause: error.code);
    } catch (error, stack) {
      ErrorReporter.report('SecureKeyStore', error.runtimeType, stack);
      throw SecureStorageException(failure, cause: error.runtimeType);
    }
  }

  @override
  Future<void> write({
    required String keyId,
    required int version,
    required List<int> material,
  }) => _guard(
    'The key could not be stored securely.',
    () => _storage.write(
      key: SecureKeyStore.storageKeyFor(keyId, version),
      value: _encode(material),
    ),
  );

  @override
  Future<List<int>?> read({required String keyId, required int version}) =>
      _guard('The key could not be read from secure storage.', () async {
        final value = await _storage.read(
          key: SecureKeyStore.storageKeyFor(keyId, version),
        );
        return value == null ? null : _decode(value);
      });

  @override
  Future<void> delete({required String keyId, required int version}) => _guard(
    'The key could not be removed from secure storage.',
    () => _storage.delete(key: SecureKeyStore.storageKeyFor(keyId, version)),
  );
}

/// In-memory [SecureKeyStore] for tests. Can be told to fail.
class InMemorySecureKeyStore implements SecureKeyStore {
  final Map<String, String> entries = {};
  bool failReads = false;
  bool failWrites = false;

  @override
  Future<void> write({
    required String keyId,
    required int version,
    required List<int> material,
  }) async {
    if (failWrites) {
      throw const SecureStorageException(
        'The key could not be stored securely.',
      );
    }
    entries[SecureKeyStore.storageKeyFor(keyId, version)] = _encode(material);
  }

  @override
  Future<List<int>?> read({required String keyId, required int version}) async {
    if (failReads) {
      throw const SecureStorageException(
        'The key could not be read from secure storage.',
      );
    }
    final value = entries[SecureKeyStore.storageKeyFor(keyId, version)];
    return value == null ? null : _decode(value);
  }

  @override
  Future<void> delete({required String keyId, required int version}) async {
    entries.remove(SecureKeyStore.storageKeyFor(keyId, version));
  }
}
