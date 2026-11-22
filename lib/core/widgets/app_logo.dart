import 'package:material_ui/material_ui.dart';

/// The CipherNote app mark: a note sheet with scrambled "cipher" lines and a
/// padlock badge, on a blue rounded tile.
///
/// Drawn with a [CustomPainter] so it stays crisp at any size. The geometry
/// mirrors `assets/logo/cipher_note_logo.svg` (a 1024×1024 design grid), which
/// is the source for the launcher icons — keep the two in sync.
class AppLogo extends StatelessWidget {
  const AppLogo({super.key, this.size = 32});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'CipherNote logo',
      image: true,
      child: SizedBox.square(
        dimension: size,
        child: const CustomPaint(painter: _AppLogoPainter()),
      ),
    );
  }
}

class _AppLogoPainter extends CustomPainter {
  const _AppLogoPainter();

  static const _bgStart = Color(0xFF3B82F6);
  static const _bgEnd = Color(0xFF1E40AF);
  static const _paper = Color(0xFFFFF3BF);
  static const _fold = Color(0xFFF2D675);
  static const _ink = Color(0xFF1F2937);
  static const _badge = Color(0xFF0F172A);
  static const _white = Color(0xFFFFFFFF);

  @override
  void paint(Canvas canvas, Size size) {
    // Work in the SVG's 1024-unit design space.
    final s = size.shortestSide / 1024;
    canvas.save();
    canvas.scale(s);

    // Background tile.
    const tile = Rect.fromLTWH(0, 0, 1024, 1024);
    canvas.drawRRect(
      RRect.fromRectAndRadius(tile, const Radius.circular(224)),
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_bgStart, _bgEnd],
        ).createShader(tile),
    );

    // Note sheet with a folded top-right corner.
    final sheet = Path()
      ..moveTo(320, 208)
      ..lineTo(600, 208)
      ..lineTo(712, 320)
      ..lineTo(712, 720)
      ..quadraticBezierTo(712, 768, 664, 768)
      ..lineTo(320, 768)
      ..quadraticBezierTo(272, 768, 272, 720)
      ..lineTo(272, 256)
      ..quadraticBezierTo(272, 208, 320, 208)
      ..close();
    canvas.drawPath(sheet, Paint()..color = _paper);

    final fold = Path()
      ..moveTo(600, 208)
      ..lineTo(600, 288)
      ..quadraticBezierTo(600, 320, 632, 320)
      ..lineTo(712, 320)
      ..close();
    canvas.drawPath(fold, Paint()..color = _fold);

    // One plain line, then scrambled cipher lines.
    void bar(double x, double y, double w, Color color) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, y, w, 32),
          const Radius.circular(16),
        ),
        Paint()..color = color,
      );
    }

    final faded = _ink.withValues(alpha: 0.55);
    bar(336, 384, 272, _ink);
    bar(336, 464, 88, faded);
    bar(448, 464, 56, faded);
    bar(528, 464, 112, faded);
    bar(336, 544, 56, faded);
    bar(416, 544, 104, faded);

    // Padlock badge.
    const badgeCenter = Offset(700, 724);
    canvas.drawCircle(badgeCenter, 170, Paint()..color = _white);
    canvas.drawCircle(badgeCenter, 150, Paint()..color = _badge);

    final shackle = Path()
      ..moveTo(652, 712)
      ..lineTo(652, 668)
      ..arcToPoint(
        const Offset(748, 668),
        radius: const Radius.circular(48),
      )
      ..lineTo(748, 712);
    canvas.drawPath(
      shackle,
      Paint()
        ..color = _white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 26
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(620, 700, 160, 116),
        const Radius.circular(26),
      ),
      Paint()..color = _white,
    );

    // Keyhole.
    final keyhole = Paint()..color = _badge;
    canvas.drawCircle(const Offset(700, 748), 17, keyhole);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(692, 752, 16, 38),
        const Radius.circular(8),
      ),
      keyhole,
    );

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _AppLogoPainter oldDelegate) => false;
}
