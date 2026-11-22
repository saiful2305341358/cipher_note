import 'package:material_ui/material_ui.dart';

import '../../../core/errors/app_exceptions.dart';
import '../../../core/errors/error_reporter.dart';
import '../../../data/models/app_settings.dart';
import '../../../data/repositories/settings_repository.dart';

export '../../../data/models/app_settings.dart'
    show AppSettings, NoteSortOrder, NoteViewMode;

/// User preferences.
///
/// Changes apply immediately and are then saved through the
/// [SettingsRepository]. If saving fails, the change stays active for this
/// session and [saveError] is set so the UI can say it was not stored.
class SettingsProvider extends ChangeNotifier {
  SettingsProvider({
    this._repository,
    AppSettings? initial,
    ThemeMode? themeMode,
    NoteViewMode? viewMode,
    NoteSortOrder? sortOrder,
    int? defaultNoteColor,
    bool? showContentPreview,
    bool? autoSave,
  }) : _settings = (initial ?? AppSettings.defaults).copyWith(
         themeMode: themeMode,
         viewMode: viewMode,
         sortOrder: sortOrder,
         defaultNoteColor: defaultNoteColor,
         showContentPreview: showContentPreview,
         autoSave: autoSave,
       );

  final SettingsRepository? _repository;
  AppSettings _settings;
  AppException? _saveError;
  Future<void> _pendingSave = Future.value();

  AppSettings get settings => _settings;
  ThemeMode get themeMode => _settings.themeMode;
  NoteViewMode get viewMode => _settings.viewMode;
  NoteSortOrder get sortOrder => _settings.sortOrder;
  int get defaultNoteColor => _settings.defaultNoteColor;
  bool get showContentPreview => _settings.showContentPreview;
  bool get autoSave => _settings.autoSave;
  bool get isGridView => _settings.viewMode == NoteViewMode.grid;

  /// Set when the last save failed; cleared by the next successful save.
  AppException? get saveError => _saveError;

  /// Completes when all requested saves have finished.
  Future<void> get pendingSave => _pendingSave;

  void setThemeMode(ThemeMode mode) =>
      _update(_settings.copyWith(themeMode: mode));

  void setViewMode(NoteViewMode mode) =>
      _update(_settings.copyWith(viewMode: mode));

  void toggleViewMode() =>
      setViewMode(isGridView ? NoteViewMode.list : NoteViewMode.grid);

  void setSortOrder(NoteSortOrder order) =>
      _update(_settings.copyWith(sortOrder: order));

  void setDefaultNoteColor(int color) =>
      _update(_settings.copyWith(defaultNoteColor: color));

  void setShowContentPreview(bool value) =>
      _update(_settings.copyWith(showContentPreview: value));

  void setAutoSave(bool value) => _update(_settings.copyWith(autoSave: value));

  void _update(AppSettings next) {
    if (next == _settings) return;
    _settings = next;
    notifyListeners();
    final repository = _repository;
    if (repository == null) return;
    // Saves run one after another so the last change always wins.
    _pendingSave = _pendingSave.then((_) => _persist(repository));
  }

  Future<void> _persist(SettingsRepository repository) async {
    final snapshot = _settings;
    try {
      await repository.save(snapshot);
      if (_saveError != null) {
        _saveError = null;
        notifyListeners();
      }
    } catch (error, stack) {
      ErrorReporter.report('SettingsProvider.save', error, stack);
      _saveError = error is AppException
          ? error
          : StorageException('Your settings could not be saved.', cause: error);
      notifyListeners();
    }
  }
}
