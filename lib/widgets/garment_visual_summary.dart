import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/garment_visual_profile.dart';

/// Describes measured photo cues without assigning a semantic pattern label.
class GarmentVisualSummary extends StatelessWidget {
  const GarmentVisualSummary({
    super.key,
    required this.profile,
    this.compact = false,
  });

  final GarmentVisualProfile profile;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = profile.palette
        .where(
          (entry) =>
              entry.share.isFinite && entry.share > 0 && entry.share <= 1,
        )
        .take(6)
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!compact && profile.previewArgb.length == 256) ...[
              Semantics(
                label:
                    'Small color and texture sample from the selected garment area',
                image: true,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: SizedBox.square(
                    dimension: 52,
                    child: CustomPaint(
                      painter: _SamplePainter(profile.previewArgb),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Photo estimate', style: theme.textTheme.labelMedium),
                  const SizedBox(height: 3),
                  Text(
                    profile.shortDescription,
                    style: theme.textTheme.titleSmall,
                  ),
                ],
              ),
            ),
          ],
        ),
        if (palette.isNotEmpty) ...[
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(5),
            child: SizedBox(
              height: compact ? 10 : 14,
              child: Row(
                children: [
                  for (final entry in palette)
                    Expanded(
                      flex: math.max(1, (entry.share * 1000).round()),
                      child: ColoredBox(
                        color: Color(entry.color.argb),
                        child: const SizedBox.expand(),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 10,
            runSpacing: 4,
            children: [
              for (final entry in palette)
                Text(
                  '${entry.color.name} ${(entry.share * 100).round()}%',
                  style: theme.textTheme.bodySmall,
                ),
            ],
          ),
        ],
        if (!compact) ...[
          const SizedBox(height: 8),
          Text(profile.stylingDescription, style: theme.textTheme.bodySmall),
          const SizedBox(height: 4),
          Text(
            'Approximate colors and visual detail from this area. Light, folds and crop can change the result.',
            style: theme.textTheme.bodySmall,
          ),
        ],
        if (!profile.isReliable) ...[
          const SizedBox(height: 6),
          Text(
            'This area is unclear. Try a larger, evenly lit part of the garment.',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ],
    );
  }
}

class _SamplePainter extends CustomPainter {
  const _SamplePainter(this.pixels);
  final List<int> pixels;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..isAntiAlias = false;
    for (var i = 0; i < math.min(256, pixels.length); i++) {
      paint.color = Color(pixels[i]);
      canvas.drawRect(
        Rect.fromLTWH(
          (i % 16) * size.width / 16,
          (i ~/ 16) * size.height / 16,
          size.width / 16,
          size.height / 16,
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _SamplePainter oldDelegate) =>
      pixels != oldDelegate.pixels;
}
