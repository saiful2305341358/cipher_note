import 'package:material_ui/material_ui.dart';

import '../theme/app_colors.dart';

/// Simple app mark: a rounded note tile with a small lock.
class AppLogo extends StatelessWidget {
  const AppLogo({super.key, this.size = 32});

  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: AppColors.yellow.light,
        borderRadius: BorderRadius.circular(size * 0.28),
        border: Border.all(
          color: AppColors.noteAccent(AppColors.yellow.value, Brightness.light),
        ),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Icon(
            Icons.sticky_note_2_outlined,
            size: size * 0.62,
            color: AppColors.textPrimary,
          ),
          Positioned(
            right: size * 0.06,
            bottom: size * 0.06,
            child: Container(
              padding: EdgeInsets.all(size * 0.04),
              decoration: BoxDecoration(
                color: scheme.primary,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.lock_rounded,
                size: size * 0.22,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
