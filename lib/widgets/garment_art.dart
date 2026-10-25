import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show listEquals;
import '../models/style_models.dart';

enum GarmentKind { shirt, pants, shoes, jacket }

/// Resolution-independent wardrobe illustrations, tinted to the actual outfit.
class GarmentArt extends StatelessWidget {
  const GarmentArt({
    super.key,
    required this.kind,
    required this.color,
    this.size = 130,
    this.details = const GarmentDetails(),
  });
  final GarmentKind kind;
  final Color color;
  final double size;
  final GarmentDetails details;
  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: CustomPaint(painter: _GarmentPainter(kind, color, details)),
  );
}

class _GarmentPainter extends CustomPainter {
  _GarmentPainter(this.kind, this.color, this.details);
  final GarmentKind kind;
  final Color color;
  final GarmentDetails details;

  void _pattern(Canvas canvas, Path shape) {
    if (details.pattern == GarmentPattern.solid) return;
    final accents = details.accentColors.map((c) => Color(c.argb)).toList();
    final contrast = color.computeLuminance() > .4
        ? const Color(0xFF26382F)
        : const Color(0xFFF2EFE5);
    final first = accents.isEmpty ? contrast : accents.first;
    final second = accents.length > 1 ? accents[1] : first;
    canvas.save();
    canvas.clipPath(shape);
    switch (details.pattern) {
      case GarmentPattern.solid:
        break;
      case GarmentPattern.checks:
        for (double p = 0; p < 160; p += 24) {
          canvas.drawRect(
            Rect.fromLTWH(p, 0, 10, 160),
            Paint()..color = first.withValues(alpha: .65),
          );
          canvas.drawRect(
            Rect.fromLTWH(0, p, 160, 9),
            Paint()..color = second.withValues(alpha: .65),
          );
        }
      case GarmentPattern.stripes:
        for (double p = 0; p < 160; p += 17) {
          canvas.drawRect(
            Rect.fromLTWH(0, p, 160, 5),
            Paint()..color = first.withValues(alpha: .8),
          );
        }
      case GarmentPattern.print:
        for (double x = 20; x < 145; x += 26) {
          for (double y = 20; y < 150; y += 25) {
            canvas.drawCircle(
              Offset(x, y),
              3.5,
              Paint()..color = first.withValues(alpha: .85),
            );
            canvas.drawCircle(
              Offset(x + 8, y + 8),
              2.5,
              Paint()..color = second.withValues(alpha: .85),
            );
          }
        }
      case GarmentPattern.colorBlock:
        canvas.drawRect(
          const Rect.fromLTWH(0, 60, 160, 45),
          Paint()..color = first,
        );
        if (accents.length > 1) {
          canvas.drawRect(
            const Rect.fromLTWH(0, 105, 160, 55),
            Paint()..color = second,
          );
        }
    }
    canvas.restore();
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 160, size.height / 160);
    final fill = Paint()..color = color;
    final seam = Paint()
      ..color = Color.lerp(color, const Color(0xFF27382E), .24)!
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..strokeJoin = StrokeJoin.round;
    final highlight = Paint()..color = Colors.white.withValues(alpha: .16);
    Path shape;
    switch (kind) {
      case GarmentKind.shirt:
      case GarmentKind.jacket:
        final jacket = kind == GarmentKind.jacket;
        final crew =
            !jacket &&
            (details.type == GarmentType.tShirt ||
                details.type == GarmentType.knit);
        final longSleeve =
            jacket ||
            details.type == GarmentType.flannel ||
            details.type == GarmentType.knit;
        shape = Path()
          ..moveTo(57, 20)
          ..lineTo(36, 28)
          ..lineTo(longSleeve ? 13 : 17, longSleeve ? 121 : 63)
          ..lineTo(longSleeve ? 34 : 40, longSleeve ? 127 : 75)
          ..lineTo(44, 59)
          ..lineTo(42, 137)
          ..quadraticBezierTo(80, 144, 118, 137)
          ..lineTo(116, 59)
          ..lineTo(longSleeve ? 126 : 120, longSleeve ? 127 : 75)
          ..lineTo(longSleeve ? 147 : 143, longSleeve ? 121 : 63)
          ..lineTo(124, 28)
          ..lineTo(103, 20)
          ..quadraticBezierTo(80, 31, 57, 20)
          ..close();
        canvas.drawShadow(
          shape,
          const Color(0xFF34472B).withValues(alpha: .22),
          5,
          false,
        );
        canvas.drawPath(shape, fill);
        _pattern(canvas, shape);
        canvas.drawPath(shape, seam);
        if (crew) {
          canvas.drawPath(
            Path()
              ..moveTo(57, 20)
              ..quadraticBezierTo(80, 56, 103, 20),
            seam,
          );
          break;
        }
        canvas.drawPath(
          Path()
            ..moveTo(57, 20)
            ..lineTo(64, 43)
            ..lineTo(80, 31)
            ..lineTo(96, 43)
            ..lineTo(103, 20),
          seam,
        );
        canvas.drawLine(const Offset(80, 32), const Offset(80, 138), seam);
        canvas.drawPath(
          Path()
            ..moveTo(93, 57)
            ..lineTo(109, 57)
            ..lineTo(108, 75)
            ..quadraticBezierTo(100, 81, 93, 75)
            ..close(),
          seam,
        );
        canvas.drawPath(
          Path()
            ..moveTo(47, 61)
            ..lineTo(52, 130)
            ..lineTo(72, 135)
            ..lineTo(50, 129)
            ..close(),
          highlight,
        );
        for (double y = 49; y < 131; y += 16) {
          canvas.drawCircle(
            Offset(83, y),
            1.3,
            seam..style = PaintingStyle.fill,
          );
        }
        break;
      case GarmentKind.pants:
        final shorts = details.type == GarmentType.shorts;
        shape = Path()
          ..moveTo(43, 16)
          ..lineTo(117, 16)
          ..lineTo(shorts ? 122 : 125, shorts ? 93 : 141)
          ..lineTo(91, shorts ? 94 : 144)
          ..lineTo(80, 65)
          ..lineTo(69, shorts ? 94 : 144)
          ..lineTo(shorts ? 38 : 35, shorts ? 93 : 141)
          ..close();
        canvas.drawShadow(shape, Colors.black.withValues(alpha: .16), 4, false);
        canvas.drawPath(shape, fill);
        _pattern(canvas, shape);
        canvas.drawPath(shape, seam);
        canvas.drawLine(const Offset(43, 26), const Offset(117, 26), seam);
        canvas.drawPath(
          Path()
            ..moveTo(80, 26)
            ..lineTo(80, 52)
            ..quadraticBezierTo(88, 56, 89, 46)
            ..lineTo(89, 26),
          seam,
        );
        canvas.drawPath(
          Path()
            ..moveTo(61, 27)
            ..quadraticBezierTo(60, 42, 42, 48),
          seam,
        );
        canvas.drawPath(
          Path()
            ..moveTo(99, 27)
            ..quadraticBezierTo(100, 42, 118, 48),
          seam,
        );
        canvas.drawLine(
          const Offset(57, 60),
          Offset(52, shorts ? 88 : 135),
          seam..color = seam.color.withValues(alpha: .3),
        );
        canvas.drawLine(
          const Offset(103, 60),
          Offset(108, shorts ? 88 : 135),
          seam,
        );
        break;
      case GarmentKind.shoes:
        for (var i = 0; i < 2; i++) {
          canvas.save();
          canvas.translate(i * 8.0, i * 43.0);
          shape = Path()
            ..moveTo(24, 45)
            ..quadraticBezierTo(29, 33, 47, 39)
            ..lineTo(67, 53)
            ..lineTo(104, 62)
            ..quadraticBezierTo(130, 62, 137, 78)
            ..lineTo(136, 87)
            ..quadraticBezierTo(76, 94, 23, 82)
            ..close();
          canvas.drawShadow(
            shape,
            Colors.black.withValues(alpha: .16),
            3,
            false,
          );
          canvas.drawPath(shape, fill);
          canvas.drawPath(shape, seam);
          canvas.drawPath(
            Path()
              ..moveTo(24, 77)
              ..quadraticBezierTo(79, 88, 136, 81)
              ..lineTo(136, 87)
              ..quadraticBezierTo(76, 94, 23, 82)
              ..close(),
            Paint()..color = const Color(0xFFE8E5DB),
          );
          for (var l = 0; l < 4; l++) {
            canvas.drawLine(
              Offset(65 + l * 8, 54 + l * 2),
              Offset(59 + l * 8, 65 + l * 2),
              Paint()
                ..color = const Color(0xFFF3F0E6)
                ..strokeWidth = 2,
            );
          }
          canvas.restore();
        }
        break;
    }
  }

  @override
  bool shouldRepaint(_GarmentPainter oldDelegate) =>
      oldDelegate.kind != kind ||
      oldDelegate.color != color ||
      oldDelegate.details.signature != details.signature ||
      !listEquals(
        oldDelegate.details.accentColors.map((c) => c.argb).toList(),
        details.accentColors.map((c) => c.argb).toList(),
      );
}

class OutfitArt extends StatelessWidget {
  const OutfitArt({
    super.key,
    required this.shirt,
    required this.pants,
    required this.shoes,
    this.layer,
    this.height = 240,
    this.topDetails = const GarmentDetails(),
    this.pantsDetails = const GarmentDetails(),
  });
  final Color shirt, pants, shoes;
  final Color? layer;
  final double height;
  final GarmentDetails topDetails, pantsDetails;
  @override
  Widget build(BuildContext context) => SizedBox(
    height: height,
    child: LayoutBuilder(
      builder: (context, constraints) {
        final widthScale = (constraints.maxWidth / 320).clamp(.6, 1.3);
        final heightScale = ((constraints.maxHeight - 48) / 180).clamp(.3, 1.3);
        final scale = widthScale < heightScale ? widthScale : heightScale;
        return Stack(
          alignment: Alignment.center,
          children: [
            Positioned(
              top: 18,
              left: constraints.maxWidth * .10,
              child: Transform.rotate(
                angle: -.09,
                child: GarmentArt(
                  kind: GarmentKind.shirt,
                  color: shirt,
                  details: topDetails,
                  size: 153 * scale,
                ),
              ),
            ),
            Positioned(
              top: 34,
              right: constraints.maxWidth * .07,
              child: Transform.rotate(
                angle: .10,
                child: GarmentArt(
                  kind: GarmentKind.pants,
                  color: pants,
                  details: pantsDetails,
                  size: 161 * scale,
                ),
              ),
            ),
            Positioned(
              bottom: 7,
              left: constraints.maxWidth * .16,
              child: Transform.rotate(
                angle: -.15,
                child: GarmentArt(
                  kind: GarmentKind.shoes,
                  color: shoes,
                  size: 111 * scale,
                ),
              ),
            ),
            if (layer != null && layer!.a > 0)
              Positioned(
                bottom: 8,
                right: constraints.maxWidth * .08,
                child: Transform.rotate(
                  angle: .13,
                  child: GarmentArt(
                    kind: GarmentKind.jacket,
                    color: layer!,
                    size: 93 * scale,
                  ),
                ),
              ),
          ],
        );
      },
    ),
  );
}
