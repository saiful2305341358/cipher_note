import 'package:flutter/foundation.dart';

import '../../../core/errors/app_exceptions.dart';
import '../../../core/errors/error_reporter.dart';
import '../../../data/models/key_metadata.dart';
import '../../encryption/data/key_service.dart';

/// Key list state for the UI. All work is done by [KeyService]; this class
/// only holds the loaded metadata (never key material).
class KeyProvider extends ChangeNotifier {
  KeyProvider(this._service);

  final KeyService _service;

  List<KeyMetadata> _keys = const [];
  bool _isLoaded = false;
  bool _busy = false;
  AppException? _error;

  /// Every key, the active key first.
  List<KeyMetadata> get keys => _keys;
  bool get isLoaded => _isLoaded;
  bool get hasKeys => _keys.isNotEmpty;

  /// True while a create, activate or delete operation runs.
  bool get isBusy => _busy;

  /// Set when loading key information failed.
  AppException? get error => _error;

  KeyMetadata? get activeKey {
    for (final k in _keys) {
      if (k.isActive) return k;
    }
    return _keys.isEmpty ? null : _keys.first;
  }

  KeyMetadata? keyById(String? id) {
    if (id == null) return null;
    for (final k in _keys) {
      if (k.id == id) return k;
    }
    return null;
  }

  /// Whether metadata exists for exactly this key id and version.
  bool isAvailable(String? keyId, int? version) {
    final key = keyById(keyId);
    return key != null && key.version == version;
  }

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

  /// Creates a new key and makes it active. Throws [AppException].
  Future<KeyMetadata> createKey(String name) =>
      _run(() => _service.createKey(name));

  /// Makes [keyId] the default key for encryption. Throws [AppException].
  Future<void> setActive(String keyId) => _run(() => _service.setActive(keyId));

  /// Deletes an unused key. Throws [KeyInUseException] if notes use it.
  Future<void> deleteKey(String keyId) => _run(() => _service.deleteKey(keyId));

  Future<T> _run<T>(Future<T> Function() action) async {
    if (_busy) {
      throw const StorageException('Please wait for the current action.');
    }
    _busy = true;
    notifyListeners();
    try {
      final result = await action();
      _keys = await _service.listKeys();
      _error = null;
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
      _busy = false;
      notifyListeners();
    }
  }
}
