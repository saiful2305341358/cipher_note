import 'package:material_ui/material_ui.dart';

import '../../../core/theme/app_colors.dart';
import '../../notes/providers/notes_provider.dart';

/// Home screen layout.
enum NoteViewMode {
  list('List'),
  grid('Grid');

  const NoteViewMode(this.label);
  final String label;
}

/// User preferences. Held in memory for the current session in Phase 1.
class SettingsProvider extends ChangeNotifier {
  SettingsProvider({
    this._themeMode = ThemeMode.system,
    this._viewMode = NoteViewMode.list,
    this._sortOrder = NoteSortOrder.modified,
    int? defaultNoteColor,
    this._showContentPreview = true,
    this._autoSave = true,
  }) : _defaultNoteColor = defaultNoteColor ?? AppColors.defaultNoteColor.value;

  ThemeMode _themeMode;
  NoteViewMode _viewMode;
  NoteSortOrder _sortOrder;
  int _defaultNoteColor;
  bool _showContentPreview;
  bool _autoSave;

  ThemeMode get themeMode => _themeMode;
  NoteViewMode get viewMode => _viewMode;
  NoteSortOrder get sortOrder => _sortOrder;
  int get defaultNoteColor => _defaultNoteColor;
  bool get showContentPreview => _showContentPreview;
  bool get autoSave => _autoSave;

  bool get isGridView => _viewMode == NoteViewMode.grid;

  void setThemeMode(ThemeMode mode) => _set(() => _themeMode = mode);

  void setViewMode(NoteViewMode mode) => _set(() => _viewMode = mode);

  void toggleViewMode() =>
      setViewMode(isGridView ? NoteViewMode.list : NoteViewMode.grid);

  void setSortOrder(NoteSortOrder order) => _set(() => _sortOrder = order);

  void setDefaultNoteColor(int color) => _set(() => _defaultNoteColor = color);

  void setShowContentPreview(bool value) =>
      _set(() => _showContentPreview = value);

  void setAutoSave(bool value) => _set(() => _autoSave = value);

  void _set(VoidCallback change) {
    change();
    notifyListeners();
  }
}
