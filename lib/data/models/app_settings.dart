import 'package:material_ui/material_ui.dart';

import '../../core/theme/app_colors.dart';

/// Home screen layout.
enum NoteViewMode {
  list('List'),
  grid('Grid');

  const NoteViewMode(this.label);
  final String label;
}

/// How notes are ordered on the home screen.
enum NoteSortOrder {
  modified('Modified time'),
  created('Created time'),
  title('Title'),
  color('Color');

  const NoteSortOrder(this.label);
  final String label;
}

/// All user preferences, stored as one record.
@immutable
class AppSettings {
  const AppSettings({
    this.themeMode = ThemeMode.system,
    this.viewMode = NoteViewMode.list,
    this.sortOrder = NoteSortOrder.modified,
    this.defaultNoteColor = defaultColorValue,
    this.showContentPreview = true,
    this.autoSave = true,
  });

  static const int defaultColorValue = 0xFFFFF3BF;

  /// Settings used on first launch.
  static const AppSettings defaults = AppSettings();

  final ThemeMode themeMode;
  final NoteViewMode viewMode;
  final NoteSortOrder sortOrder;
  final int defaultNoteColor;
  final bool showContentPreview;
  final bool autoSave;

  AppSettings copyWith({
    ThemeMode? themeMode,
    NoteViewMode? viewMode,
    NoteSortOrder? sortOrder,
    int? defaultNoteColor,
    bool? showContentPreview,
    bool? autoSave,
  }) => AppSettings(
    themeMode: themeMode ?? this.themeMode,
    viewMode: viewMode ?? this.viewMode,
    sortOrder: sortOrder ?? this.sortOrder,
    defaultNoteColor: defaultNoteColor ?? this.defaultNoteColor,
    showContentPreview: showContentPreview ?? this.showContentPreview,
    autoSave: autoSave ?? this.autoSave,
  );

  /// Replaces values that are no longer valid (for example a colour that was
  /// removed from the palette) with defaults.
  AppSettings sanitized() {
    final colorIsKnown = AppColors.noteColors.any(
      (c) => c.value == defaultNoteColor,
    );
    return colorIsKnown ? this : copyWith(defaultNoteColor: defaultColorValue);
  }

  @override
  bool operator ==(Object other) =>
      other is AppSettings &&
      other.themeMode == themeMode &&
      other.viewMode == viewMode &&
      other.sortOrder == sortOrder &&
      other.defaultNoteColor == defaultNoteColor &&
      other.showContentPreview == showContentPreview &&
      other.autoSave == autoSave;

  @override
  int get hashCode => Object.hash(
    themeMode,
    viewMode,
    sortOrder,
    defaultNoteColor,
    showContentPreview,
    autoSave,
  );
}
