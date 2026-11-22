import 'package:hive_ce/hive_ce.dart';

import '../../core/database/database_constants.dart';
import '../../core/errors/app_exceptions.dart';
import '../../core/errors/error_reporter.dart';
import '../models/app_settings.dart';

/// Storage for user preferences.
abstract class SettingsRepository {
  /// Returns stored settings, or [AppSettings.defaults] on first launch.
  Future<AppSettings> load();

  Future<void> save(AppSettings settings);
}

/// In-memory implementation for tests.
class InMemorySettingsRepository implements SettingsRepository {
  InMemorySettingsRepository([this._settings = AppSettings.defaults]);

  AppSettings _settings;

  @override
  Future<AppSettings> load() async => _settings;

  @override
  Future<void> save(AppSettings settings) async => _settings = settings;
}

/// [SettingsRepository] storing one [AppSettings] record in a Hive box.
class HiveSettingsRepository implements SettingsRepository {
  HiveSettingsRepository(this._box);

  final Box<AppSettings> _box;

  @override
  Future<AppSettings> load() async {
    try {
      return _box.get(DatabaseConstants.settingsKey) ?? AppSettings.defaults;
    } catch (error, stack) {
      ErrorReporter.report('HiveSettingsRepository.load', error, stack);
      throw StorageException(
        'Your settings could not be loaded.',
        cause: error,
      );
    }
  }

  @override
  Future<void> save(AppSettings settings) async {
    try {
      await _box.put(DatabaseConstants.settingsKey, settings);
    } catch (error, stack) {
      ErrorReporter.report('HiveSettingsRepository.save', error, stack);
      throw StorageException('Your settings could not be saved.', cause: error);
    }
  }
}
