import 'package:flutter/foundation.dart';

import '../../../core/errors/app_exceptions.dart';
import '../../../core/errors/error_reporter.dart';
import '../../../data/models/key_metadata.dart';
import '../../encryption/data/key_service.dart';

/// One logical key and its versions (newest first).
class KeyGroup {
  const KeyGroup(this.versions);

  final List<KeyMetadata> versions;

  String get id => versions.first.id;
  String get name => versions.first.name;
  KeyMetadata get latest => versions.first;
  bool get hasActiveVersion => versions.any((v) => v.isActive);
}

/// Key list state for the UI. All work is done by [KeyService]; this class
/// only holds loaded metadata (never key material).
class KeyProvider extends ChangeNotifier {
  KeyProvider(this._service);

  final KeyService _service;

  List<KeyMetadata> _keys = const [];
  bool _isLoaded = false;
  bool _busy = false;
  AppException? _error;

  /// Every key version, grouped by key, newest version first.
  List<KeyMetadata> get keys => _keys;

  /// Keys with their versions, in display order.
  List<KeyGroup> get groups {
    final order = <String>[];
    final byId = <String, List<KeyMetadata>>{};
    for (final k in _keys) {
      byId
          .putIfAbsent(k.id, () {
            order.add(k.id);
            return [];
          })
          .add(k);
    }
    return [for (final id in order) KeyGroup(byId[id]!)];
  }

  bool get isLoaded => _isLoaded;
  bool get hasKeys => _keys.isNotEmpty;

  /// True while a create, version, activate or delete operation runs.
  bool get isBusy => _busy;

  /// Set when loading key information failed.
  AppException? get error => _error;

  /// The version used by default for new encryption.
  KeyMetadata? get activeKey {
    for (final k in _keys) {
      if (k.isActive) return k;
    }
    return _keys.isEmpty ? null : _keys.first;
  }

  /// Exactly this key version, or `null`.
  KeyMetadata? version(String? keyId, int? version) {
    if (keyId == null || version == null) return null;
    for (final k in _keys) {
      if (k.id == keyId && k.version == version) return k;
    }
    return null;
  }

  /// Name of a key (any version), or `null` if no version exists.
  String? nameOf(String? keyId) {
    for (final k in _keys) {
      if (k.id == keyId) return k.name;
    }
    return null;
  }

  /// Whether metadata exists for exactly this key id and version.
  bool isAvailable(String? keyId, int? version) =>
      this.version(keyId, version) != null;

  Future<void> load() async {
    try {
      _keys = await _service.listKeys();
      _error = null;
      _isLoaded = true;
    } on AppException catch (error) {
      _error = error;
    } catch (error, stack) {
      ErrorReporter.report('KeyProvider.load', error.runtimeType, stack);
      _error = StorageException(
        'Key information could not be loaded.',
        cause: error.runtimeType,
      );
    }
    notifyListeners();
  }

  /// Checks that a key version can be used (does not throw).
  Future<KeyValidationStatus> validate(String keyId, int version) =>
      _service.validate(keyId, version);

  /// Creates a new key (version 1) and makes it active.
  Future<KeyMetadata> createKey(String name) =>
      _run(() => _service.createKey(name));

  /// Adds a new version to [keyId] and makes it active.
  Future<KeyMetadata> createNewVersion(String keyId) =>
      _run(() => _service.createNewVersion(keyId));

  /// Makes this key version the default for encryption.
  Future<void> setActive(String keyId, int version) =>
      _run(() => _service.setActive(keyId, version));

  /// Deletes one unused version. Throws [KeyInUseException] if notes use it.
  Future<void> deleteVersion(String keyId, int version) =>
      _run(() => _service.deleteVersion(keyId, version));

  Future<T> _run<T>(Future<T> Function() action) async {
    if (_busy) {
      throw const StorageException('Please wait for the current action.');
    }
    _busy = true;
    notifyListeners();
    try {
      final result = await action();
      return result;
    } on AppException {
      rethrow;
    } catch (error, stack) {
      ErrorReporter.report('KeyProvider', error.runtimeType, stack);
      throw StorageException(
        'Key information could not be saved.',
        cause: error.runtimeType,
      );
    } finally {
      // Always reload, so the list matches storage even after a failure.
      try {
        _keys = await _service.listKeys();
        _error = null;
      } on AppException catch (error) {
        _error = error;
      }
      _busy = false;
      notifyListeners();
    }
  }
}
