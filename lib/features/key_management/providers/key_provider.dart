import 'package:flutter/foundation.dart';

import '../../../core/errors/app_exceptions.dart';
import '../../../core/errors/error_reporter.dart';
import '../../../data/models/key_metadata.dart';
import '../../../data/repositories/key_metadata_repository.dart';

/// Encryption key status, kept separate from note management.
///
/// Reads stored key metadata. Real keys cannot be created yet, so normally
/// there is none. [showDemoKey] shows clearly labelled example metadata to
/// preview the screen; the demo is never saved.
class KeyProvider extends ChangeNotifier {
  KeyProvider(this._repository, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final KeyMetadataRepository _repository;
  final DateTime Function() _clock;

  KeyMetadata? _activeKey;
  KeyMetadata? _demoKey;
  AppException? _error;

  /// The key shown on screen: the stored active key, or the demo preview.
  KeyMetadata? get keyInfo => _activeKey ?? _demoKey;

  bool get hasKey => keyInfo != null;

  /// True when the shown key is the unsaved demo preview.
  bool get isDemo => _activeKey == null && _demoKey != null;

  /// Set when loading or deleting key metadata failed.
  AppException? get error => _error;

  Future<void> load() async {
    try {
      _activeKey = await _repository.getActive();
      _error = null;
    } on AppException catch (error) {
      _error = error;
    } catch (error, stack) {
      ErrorReporter.report('KeyProvider.load', error, stack);
      _error = StorageException(
        'Key information could not be loaded.',
        cause: error,
      );
    }
    notifyListeners();
  }

  /// Shows example metadata (no key material, not saved).
  void showDemoKey() {
    _demoKey = KeyMetadata(
      id: 'DEMO-2X2-0001',
      name: 'Demo key',
      version: 1,
      algorithm: KeyMetadata.hillCipher2x2,
      createdAt: _clock(),
    );
    notifyListeners();
  }

  /// Removes the demo preview, or deletes the stored active key metadata.
  /// Throws [AppException] if a stored record could not be deleted.
  Future<void> deleteKey() async {
    if (isDemo) {
      _demoKey = null;
      notifyListeners();
      return;
    }
    final active = _activeKey;
    if (active == null) return;
    await _repository.delete(active.id);
    _activeKey = await _repository.getActive();
    notifyListeners();
  }
}
