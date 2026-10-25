import 'style_models.dart' show ShirtColor;

/// A colour's observed proportion within the user's selected garment region.
class VisualColorShare {
  const VisualColorShare({required this.color, required this.share});

  final ShirtColor color;
  final double share;

  Map<String, dynamic> toJson() => {'color': color.toJson(), 'share': share};

  factory VisualColorShare.fromJson(Object? raw) {
    if (raw is Map && raw['color'] is Map) {
      final color = raw['color'] as Map;
      final argb = color['argb'];
      final name = color['name'];
      final share = _unit(raw['share']);
      if (argb is int &&
          argb >= 0xFF000000 &&
          argb <= 0xFFFFFFFF &&
          name is String &&
          name.trim().isNotEmpty &&
          name.length <= 80 &&
          share > 0) {
        return VisualColorShare(
          color: ShirtColor(name: name.trim(), argb: argb),
          share: share,
        );
      }
    }
    return const VisualColorShare(
      color: ShirtColor(name: 'Unknown', argb: 0xFF808080),
      share: 0,
    );
  }
}

/// Continuous, local observations of a selected fabric design, not a prediction
/// of garment category, fabric composition, or a named semantic pattern.
///
/// Metrics are normalized to [0, 1]. [dominantAngle] describes the strongest
/// visible line direction in image coordinates (clockwise from horizontal,
/// modulo 180 degrees), and is meaningful only with clear directionality.
/// [previewArgb] is an optional 16x16 row-major thumbnail of this garment crop.
class GarmentVisualProfile {
  const GarmentVisualProfile({
    this.contrast = 0,
    this.detailDensity = 0,
    this.directionality = 0,
    this.dominantAngle = 0,
    this.regularity = 0,
    this.palette = const [],
    this.previewArgb = const [],
    this.sampleWidth = 0,
    this.sampleHeight = 0,
    this.opaqueCoverage = 0,
  });

  final double contrast;
  final double detailDensity;
  final double directionality;
  final double dominantAngle;
  final double regularity;
  final List<VisualColorShare> palette;
  final List<int> previewArgb;
  final int sampleWidth;
  final int sampleHeight;
  final double opaqueCoverage;

  /// Reliability means enough readable pixels for these simple observations;
  /// it is not a calibrated recognition confidence or an accuracy guarantee.
  bool get isReliable =>
      sampleWidth >= 12 &&
      sampleWidth <= 96 &&
      sampleHeight >= 12 &&
      sampleHeight <= 96 &&
      opaqueCoverage.isFinite &&
      opaqueCoverage >= .75 &&
      opaqueCoverage <= 1 &&
      [
        contrast,
        detailDensity,
        directionality,
        regularity,
      ].every((value) => value.isFinite && value >= 0 && value <= 1) &&
      dominantAngle.isFinite &&
      dominantAngle >= 0 &&
      dominantAngle < 180 &&
      palette.isNotEmpty &&
      palette.length <= 6 &&
      palette.every(
        (swatch) =>
            swatch.share.isFinite &&
            swatch.share > 0 &&
            swatch.share <= 1 &&
            swatch.color.argb >= 0xFF000000 &&
            swatch.color.argb <= 0xFFFFFFFF,
      ) &&
      (palette.fold<double>(0, (sum, swatch) => sum + swatch.share) - 1)
              .abs() <=
          .02;

  bool get hasDetail => isReliable && detailDensity >= .10 && contrast >= .07;

  String get shortDescription {
    if (!isReliable) return 'Design details are unclear';
    if (!hasDetail) return 'Quiet design';
    final density = detailDensity >= .48 ? 'Detailed' : 'Subtle';
    final colorContrast = contrast >= .45 ? 'strong contrast' : 'soft contrast';
    return '$density design · $colorContrast';
  }

  String get stylingDescription {
    if (!isReliable) {
      return 'Select a larger, evenly lit area inside the garment to read its design.';
    }
    if (!hasDetail) {
      return 'This area reads as visually quiet. You can add texture elsewhere or keep the whole outfit simple.';
    }
    final base = detailDensity >= .48 || contrast >= .45
        ? 'This area has noticeable visual detail. A quieter companion lets the design stand out.'
        : 'This area has softer detail. A plain companion or a subtle texture can work with it.';
    final direction = directionality >= .55
        ? ' It also has a clear line direction.'
        : '';
    final repeat = regularity >= .50 ? ' Some spacing appears repeated.' : '';
    return '$base$direction$repeat';
  }

  /// Bounded deterministic identity includes spatial layout, so two designs
  /// with the same palette and broad measurements can remain distinct.
  String get signature {
    var hash = 17;
    void add(int value) => hash = (hash * 31 + value) & 0x7fffffff;
    for (final value in [contrast, detailDensity, directionality, regularity]) {
      add((_unit(value) * 20).round());
    }
    add(dominantAngle.isFinite ? (dominantAngle / 15).round() : 0);
    for (final swatch in palette.take(6)) {
      add(swatch.color.argb & 0xFFFFFF);
      add((_unit(swatch.share) * 100).round());
    }
    for (final argb in previewArgb.take(256)) {
      // Four bits per channel tolerate tiny image-decoder colour differences.
      add(
        ((argb >> 20) & 15) << 8 |
            ((argb >> 12) & 15) << 4 |
            ((argb >> 4) & 15),
      );
    }
    return 'visual-${hash.toRadixString(16)}';
  }

  Map<String, dynamic> toJson() => {
    'version': 1,
    'contrast': contrast,
    'detailDensity': detailDensity,
    'directionality': directionality,
    'dominantAngle': dominantAngle,
    'regularity': regularity,
    'palette': palette.take(6).map((swatch) => swatch.toJson()).toList(),
    'previewArgb': previewArgb.take(256).toList(),
    'sampleWidth': sampleWidth,
    'sampleHeight': sampleHeight,
    'opaqueCoverage': opaqueCoverage,
  };

  factory GarmentVisualProfile.fromJson(Object? raw) {
    if (raw is! Map || (raw['version'] != null && raw['version'] != 1)) {
      return const GarmentVisualProfile();
    }
    final colors = <VisualColorShare>[];
    final seen = <int>{};
    if (raw['palette'] case final List values) {
      for (final value in values.take(12)) {
        final parsed = VisualColorShare.fromJson(value);
        if (parsed.share > 0 && seen.add(parsed.color.argb)) colors.add(parsed);
        if (colors.length == 6) break;
      }
    }
    final total = colors.fold<double>(0, (sum, swatch) => sum + swatch.share);
    final palette = [
      for (final swatch in colors)
        VisualColorShare(color: swatch.color, share: swatch.share / total),
    ];
    final preview = <int>[];
    if (raw['previewArgb'] case final List values) {
      for (final value in values.take(256)) {
        preview.add(
          value is int && value >= 0 && value <= 0xFFFFFFFF ? value : 0,
        );
      }
    }
    final angle = raw['dominantAngle'];
    final normalizedAngle = angle is num && angle.isFinite
        ? ((angle.toDouble() % 180) + 180) % 180
        : 0.0;
    return GarmentVisualProfile(
      contrast: _unit(raw['contrast']),
      detailDensity: _unit(raw['detailDensity']),
      directionality: _unit(raw['directionality']),
      dominantAngle: normalizedAngle,
      regularity: _unit(raw['regularity']),
      palette: List.unmodifiable(palette),
      previewArgb: List.unmodifiable(preview),
      sampleWidth: _dimension(raw['sampleWidth']),
      sampleHeight: _dimension(raw['sampleHeight']),
      opaqueCoverage: _unit(raw['opaqueCoverage']),
    );
  }
}

double _unit(Object? raw) =>
    raw is num && raw.isFinite ? raw.toDouble().clamp(0.0, 1.0) : 0;

int _dimension(Object? raw) => raw is int && raw >= 12 && raw <= 96 ? raw : 0;
