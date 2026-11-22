import 'package:flutter/foundation.dart';

import '../../../data/models/encryption_key_info.dart';
import '../../../data/repositories/key_repository.dart';

/// Encryption key status, kept separate from note management.
///
/// Phase 1 cannot create real keys. [showDemoKey] only stores mock metadata
/// so that the "key available" screen state can be previewed.
class KeyProvider extends ChangeNotifier {
  KeyProvider(this._repository, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final KeyRepository _repository;
  final DateTime Function() _clock;

  EncryptionKeyInfo? _keyInfo;

  EncryptionKeyInfo? get keyInfo => _keyInfo;
  bool get hasKey => _keyInfo != null;

  Future<void> load() async {
    _keyInfo = await _repository.getKeyInfo();
    notifyListeners();
  }

  /// Stores demo key metadata (no key material) for UI preview purposes.
  Future<void> showDemoKey() async {
    final info = EncryptionKeyInfo(
      id: 'DEMO-2X2-0001',
      createdAt: _clock(),
      isDemo: true,
    );
    _keyInfo = info;
    notifyListeners();
    await _repository.saveKeyInfo(info);
  }

  Future<void> deleteKey() async {
    _keyInfo = null;
    notifyListeners();
    await _repository.deleteKeyInfo();
  }
}
