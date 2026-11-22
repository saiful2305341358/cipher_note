import 'package:material_ui/material_ui.dart';

/// A single note colour in the palette.
///
/// [value] is the ARGB value stored in [Note.color]. It is the light-mode
/// colour and acts as the colour's stable identity. [dark] is the matching
/// background used in dark mode.
class NoteColorOption {
  const NoteColorOption({
    required this.name,
    required this.light,
    required this.dark,
  });

  final String name;
  final Color light;
  final Color dark;

  int get value => light.toARGB32();

  Color resolve(Brightness brightness) =>
      brightness == Brightness.dark ? dark : light;
}

/// Centralised colour definitions. Screens should read colours from here or
/// from the active [ThemeData], never hard-code them.
class AppColors {
  AppColors._();

  // Light application colours.
  static const Color primary = Color(0xFF3B82F6);
  static const Color background = Color(0xFFF8FAFC);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color textPrimary = Color(0xFF1F2937);
  static const Color textSecondary = Color(0xFF6B7280);
  static const Color divider = Color(0xFFE5E7EB);
  static const Color danger = Color(0xFFDC2626);

  // Dark application colours.
  static const Color primaryDark = Color(0xFF60A5FA);
  static const Color backgroundDark = Color(0xFF0F172A);
  static const Color surfaceDark = Color(0xFF1E293B);
  static const Color textPrimaryDark = Color(0xFFE5E7EB);
  static const Color textSecondaryDark = Color(0xFF9CA3AF);
  static const Color dividerDark = Color(0xFF334155);
  static const Color dangerDark = Color(0xFFF87171);

  // Note palette.
  static const NoteColorOption yellow = NoteColorOption(
    name: 'Yellow',
    light: Color(0xFFFFF3BF),
    dark: Color(0xFF3D3720),
  );
  static const NoteColorOption blue = NoteColorOption(
    name: 'Blue',
    light: Color(0xFFDCEBFA),
    dark: Color(0xFF1E3449),
  );
  static const NoteColorOption green = NoteColorOption(
    name: 'Green',
    light: Color(0xFFDDF3E4),
    dark: Color(0xFF1F3A2C),
  );
  static const NoteColorOption pink = NoteColorOption(
    name: 'Pink',
    light: Color(0xFFFCE1E8),
    dark: Color(0xFF452632),
  );
  static const NoteColorOption purple = NoteColorOption(
    name: 'Purple',
    light: Color(0xFFE9E1FA),
    dark: Color(0xFF342A4B),
  );
  static const NoteColorOption white = NoteColorOption(
    name: 'White',
    light: Color(0xFFFFFFFF),
    dark: Color(0xFF1E293B),
  );

  static const List<NoteColorOption> noteColors = [
    yellow,
    blue,
    green,
    pink,
    purple,
    white,
  ];

  static NoteColorOption get defaultNoteColor => yellow;

  /// Finds the palette entry for a stored colour value. Unknown values fall
  /// back to the default colour so that bad data never breaks the UI.
  static NoteColorOption noteColorFor(int value) {
    for (final option in noteColors) {
      if (option.value == value) return option;
    }
    return defaultNoteColor;
  }

  /// Background colour for a note in the given [brightness].
  static Color noteBackground(int value, Brightness brightness) =>
      noteColorFor(value).resolve(brightness);

  /// A slightly stronger edge colour used for note card borders and the
  /// selected ring in the colour picker.
  static Color noteAccent(int value, Brightness brightness) {
    final base = noteColorFor(value).resolve(brightness);
    final hsl = HSLColor.fromColor(base);
    if (brightness == Brightness.dark) {
      return hsl.withLightness((hsl.lightness + 0.12).clamp(0, 1)).toColor();
    }
    return hsl.withLightness((hsl.lightness - 0.12).clamp(0, 1)).toColor();
  }
}
