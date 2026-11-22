import 'package:material_ui/material_ui.dart';

import '../../../core/theme/app_colors.dart';

/// Reusable row of note colour swatches.
///
/// The current colour is outlined and marked with a check icon. Tapping a
/// swatch calls [onSelected] immediately.
class NoteColorPicker extends StatelessWidget {
  const NoteColorPicker({
    super.key,
    required this.selected,
    required this.onSelected,
    this.swatchSize = 44,
  });

  final int selected;
  final ValueChanged<int> onSelected;
  final double swatchSize;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final scheme = Theme.of(context).colorScheme;
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 14,
      runSpacing: 14,
      children: [
        for (final option in AppColors.noteColors)
          _Swatch(
            key: ValueKey('note-color-${option.name}'),
            option: option,
            size: swatchSize,
            isSelected: option.value == selected,
            fill: option.resolve(brightness),
            border: AppColors.noteAccent(option.value, brightness),
            selectedRing: scheme.primary,
            onTap: () => onSelected(option.value),
          ),
      ],
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({
    super.key,
    required this.option,
    required this.size,
    required this.isSelected,
    required this.fill,
    required this.border,
    required this.selectedRing,
    required this.onTap,
  });

  final NoteColorOption option;
  final double size;
  final bool isSelected;
  final Color fill;
  final Color border;
  final Color selectedRing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: isSelected,
      label: '${option.name} note color',
      child: Tooltip(
        message: option.name,
        child: InkResponse(
          onTap: onTap,
          radius: size * 0.6,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: fill,
              shape: BoxShape.circle,
              border: Border.all(
                color: isSelected ? selectedRing : border,
                width: isSelected ? 3 : 1,
              ),
            ),
            child: isSelected
                ? Icon(
                    Icons.check_rounded,
                    size: size * 0.5,
                    color: selectedRing,
                  )
                : null,
          ),
        ),
      ),
    );
  }
}

/// Opens a compact bottom sheet with the colour picker.
///
/// [onSelected] runs on every tap so that the caller can apply the colour
/// immediately (for example to preview it in the editor). The sheet stays
/// open until the user taps Done or dismisses it.
Future<void> showNoteColorPickerSheet(
  BuildContext context, {
  required int selected,
  required ValueChanged<int> onSelected,
  String title = 'Note color',
}) {
  return showModalBottomSheet<void>(
    context: context,
    builder: (context) {
      var current = selected;
      return StatefulBuilder(
        builder: (context, setState) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                Text(
                  AppColors.noteColorFor(current).name,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 20),
                NoteColorPicker(
                  selected: current,
                  onSelected: (value) {
                    setState(() => current = value);
                    onSelected(value);
                  },
                ),
                const SizedBox(height: 16),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Done'),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}
