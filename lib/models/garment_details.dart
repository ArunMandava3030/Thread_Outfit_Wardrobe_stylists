import 'garment_visual_profile.dart';
export 'garment_visual_profile.dart';
import 'style_models.dart' show ShirtColor, StartingPiece;

enum GarmentType {
  shirt,
  tShirt,
  polo,
  flannel,
  knit,
  jeans,
  chinos,
  trousers,
  shorts,
  joggers;

  String get label => switch (this) {
    shirt => 'Shirt',
    tShirt => 'T-shirt',
    polo => 'Polo',
    flannel => 'Flannel shirt',
    knit => 'Knit / sweater',
    jeans => 'Jeans',
    chinos => 'Chinos',
    trousers => 'Tailored trousers',
    shorts => 'Shorts',
    joggers => 'Joggers',
  };

  bool get isTop => index <= knit.index;
}

enum GarmentPattern {
  solid,
  checks,
  stripes,
  print,
  colorBlock;

  String get label => switch (this) {
    solid => 'Solid',
    checks => 'Checks / plaid',
    stripes => 'Stripes',
    print => 'Print / graphic',
    colorBlock => 'Color block',
  };
}

const _unsetType = Object();

/// User-confirmed garment details. Flannel describes fabric/type independently
/// of pattern: a flannel shirt may be solid, checked or striped.
class GarmentDetails {
  const GarmentDetails({
    this.type,
    this.pattern = GarmentPattern.solid,
    this.accentColors = const [],
    this.visualProfile,
  });

  final GarmentType? type;
  final GarmentPattern pattern;
  final List<ShirtColor> accentColors;
  final GarmentVisualProfile? visualProfile;

  GarmentVisualProfile? get measuredVisual =>
      visualProfile?.isReliable == true ? visualProfile : null;

  /// Continuous visual weight, not a semantic pattern classification.
  double get visualIntensity {
    final visual = measuredVisual;
    if (visual == null) return 0;
    return (visual.contrast * .35 +
            visual.detailDensity * .45 +
            visual.directionality * .10 +
            visual.regularity * .10)
        .clamp(0.0, 1.0);
  }

  bool get needsQuietCompanion => measuredVisual != null
      ? visualIntensity >= .28 || measuredVisual!.palette.length > 1
      : pattern != GarmentPattern.solid || accentColors.isNotEmpty;

  bool get needsQuietLayer => measuredVisual != null
      ? visualIntensity >= .52
      : pattern != GarmentPattern.solid || accentColors.isNotEmpty;

  bool get isSpecified =>
      type != null ||
      pattern != GarmentPattern.solid ||
      accentColors.isNotEmpty ||
      visualProfile != null;

  GarmentDetails copyWith({
    Object? type = _unsetType,
    GarmentPattern? pattern,
    List<ShirtColor>? accentColors,
    Object? visualProfile = _unsetType,
  }) => GarmentDetails(
    type: identical(type, _unsetType) ? this.type : type as GarmentType?,
    pattern: pattern ?? this.pattern,
    visualProfile: identical(visualProfile, _unsetType)
        ? this.visualProfile
        : visualProfile as GarmentVisualProfile?,
    accentColors: accentColors == null
        ? this.accentColors
        : List.unmodifiable(accentColors),
  );

  /// Names and sampling order do not change a garment's stored identity.
  String get signature {
    final accents = accentColors.map((color) => color.argb).toSet().toList()
      ..sort();
    return '${type?.name ?? 'unspecified'}-${pattern.name}-'
        '${accents.map((argb) => argb.toRadixString(16)).join('.')}'
        '${visualProfile == null ? '' : '-visual-${visualProfile!.signature}'}';
  }

  String summary(StartingPiece piece) {
    final garment = type?.label ?? piece.itemLabel;
    if (measuredVisual != null) {
      return '${measuredVisual!.shortDescription} ${garment.toLowerCase()}';
    }
    final patternName = switch (pattern) {
      GarmentPattern.solid => accentColors.isEmpty ? 'Solid' : 'Multicolor',
      GarmentPattern.checks => 'Checked',
      GarmentPattern.stripes => 'Striped',
      GarmentPattern.print => 'Printed',
      GarmentPattern.colorBlock => 'Color-block',
    };
    return '$patternName ${garment.toLowerCase()}';
  }

  Map<String, dynamic> toJson() => {
    'type': type?.name,
    if (visualProfile != null) 'visualProfile': visualProfile!.toJson(),
    'pattern': pattern.name,
    'accentColors': accentColors.map((color) => color.toJson()).toList(),
  };

  factory GarmentDetails.fromJson(Object? raw) {
    if (raw is! Map) return const GarmentDetails();
    GarmentType? type;
    var pattern = GarmentPattern.solid;
    for (final value in GarmentType.values) {
      if (value.name == raw['type']) type = value;
    }
    for (final value in GarmentPattern.values) {
      if (value.name == raw['pattern']) pattern = value;
    }
    final accents = <ShirtColor>[];
    final values = raw['accentColors'];
    if (values is List) {
      for (final value in values.take(8)) {
        if (value is! Map) continue;
        final argb = value['argb'];
        final name = value['name'];
        if (argb is! int ||
            argb < 0xFF000000 ||
            argb > 0xFFFFFFFF ||
            name is! String ||
            name.trim().isEmpty ||
            name.length > 80) {
          continue;
        }
        if (accents.any((color) => color.argb == argb)) continue;
        accents.add(ShirtColor(name: name.trim(), argb: argb));
      }
    }
    return GarmentDetails(
      type: type,
      pattern: pattern,
      accentColors: List.unmodifiable(accents),
      visualProfile: raw['visualProfile'] == null
          ? null
          : GarmentVisualProfile.fromJson(raw['visualProfile']),
    );
  }
}
