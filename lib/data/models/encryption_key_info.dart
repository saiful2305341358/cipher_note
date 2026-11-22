import 'package:flutter/foundation.dart';

/// Metadata describing the user's encryption key.
///
/// This deliberately contains no key material. In Phase 1 only demo
/// metadata exists ([isDemo] is `true`); real keys arrive in a later phase.
@immutable
class EncryptionKeyInfo {
  const EncryptionKeyInfo({
    required this.id,
    required this.createdAt,
    this.isDemo = false,
  });

  /// Public, non-secret identifier shown to the user.
  final String id;
  final DateTime createdAt;
  final bool isDemo;
}
