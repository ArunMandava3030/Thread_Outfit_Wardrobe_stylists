enum Occasion {
  office,
  date,
  casual,
  beach,
  bikeRide;

  String get label => switch (this) {
    office => 'Office',
    date => 'Date night',
    casual => 'Casual outing',
    beach => 'Beach day',
    bikeRide => 'Bike ride',
  };
}

enum BodyShape {
  balanced,
  broadShoulders,
  widerHips,
  fullerMidsection;

  String get label => switch (this) {
    balanced => 'Balanced proportions',
    broadShoulders => 'Broader shoulders',
    widerHips => 'Wider hips',
    fullerMidsection => 'Fuller midsection',
  };
}

enum Undertone {
  warm,
  cool,
  neutral,
  unsure;

  String get label => switch (this) {
    warm => 'Warm',
    cool => 'Cool',
    neutral => 'Neutral',
    unsure => 'Not sure',
  };
}

const Object _notProvided = Object();

class StyleProfile {
  const StyleProfile({
    this.heightCm = 175,
    this.bodyShape,
    this.skinToneArgb,
    this.undertone = Undertone.unsure,
    this.useSkinTone = false,
  });

  final double heightCm;
  final BodyShape? bodyShape;
  final int? skinToneArgb;
  final Undertone undertone;
  final bool useSkinTone;

  StyleProfile copyWith({
    double? heightCm,
    Object? bodyShape = _notProvided,
    Object? skinToneArgb = _notProvided,
    Undertone? undertone,
    bool? useSkinTone,
  }) => StyleProfile(
    heightCm: heightCm ?? this.heightCm,
    bodyShape: identical(bodyShape, _notProvided)
        ? this.bodyShape
        : bodyShape as BodyShape?,
    skinToneArgb: identical(skinToneArgb, _notProvided)
        ? this.skinToneArgb
        : skinToneArgb as int?,
    undertone: undertone ?? this.undertone,
    useSkinTone: useSkinTone ?? this.useSkinTone,
  );

  Map<String, dynamic> toJson() => {
    'heightCm': heightCm,
    'bodyShape': bodyShape?.name,
    'skinToneArgb': skinToneArgb,
    'undertone': undertone.name,
    'useSkinTone': useSkinTone,
  };

  factory StyleProfile.fromJson(Map<String, dynamic> json) {
    final storedHeight = (json['heightCm'] as num?)?.toDouble();
    return StyleProfile(
      heightCm:
          storedHeight != null && storedHeight.isFinite && storedHeight > 0
          ? storedHeight
          : 175,
      bodyShape: _enumOrNull(BodyShape.values, json['bodyShape']),
      skinToneArgb: (json['skinToneArgb'] as num?)?.toInt(),
      undertone:
          _enumOrNull(Undertone.values, json['undertone']) ?? Undertone.unsure,
      useSkinTone: json['useSkinTone'] == true,
    );
  }
}

class ShirtColor {
  const ShirtColor({required this.name, required this.argb});

  final String name;
  final int argb;

  String get hex =>
      '#${(argb & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

  static const List<ShirtColor> presets = [
    ShirtColor(name: 'Sage', argb: 0xFF9BAE98),
    ShirtColor(name: 'Olive', argb: 0xFF71764B),
    ShirtColor(name: 'Navy', argb: 0xFF25394F),
    ShirtColor(name: 'White', argb: 0xFFF4F2EB),
    ShirtColor(name: 'Black', argb: 0xFF262626),
    ShirtColor(name: 'Beige', argb: 0xFFD8C5A6),
    ShirtColor(name: 'Blue', argb: 0xFF7898B3),
    ShirtColor(name: 'Burgundy', argb: 0xFF783B4B),
    ShirtColor(name: 'Pink', argb: 0xFFD7A2A0),
    ShirtColor(name: 'Rust', argb: 0xFFB96643),
    ShirtColor(name: 'Grey', argb: 0xFF979B9B),
    ShirtColor(name: 'Lilac', argb: 0xFFB5A5C5),
    ShirtColor(name: 'Red', argb: 0xFFC94F4F),
    ShirtColor(name: 'Yellow', argb: 0xFFD9B953),
    ShirtColor(name: 'Teal', argb: 0xFF367E7F),
    ShirtColor(name: 'Orange', argb: 0xFFD88A40),
  ];

  Map<String, dynamic> toJson() => {'name': name, 'argb': argb};

  factory ShirtColor.fromJson(Map<String, dynamic> json) => ShirtColor(
    name: json['name'] as String,
    argb: (json['argb'] as num).toInt(),
  );
}

class OutfitPiece {
  const OutfitPiece({
    required this.category,
    required this.title,
    required this.colorName,
    required this.colorArgb,
  });

  final String category;
  final String title;
  final String colorName;
  final int colorArgb;

  Map<String, dynamic> toJson() => {
    'category': category,
    'title': title,
    'colorName': colorName,
    'colorArgb': colorArgb,
  };

  factory OutfitPiece.fromJson(Map<String, dynamic> json) => OutfitPiece(
    category: json['category'] as String,
    title: json['title'] as String,
    colorName: json['colorName'] as String,
    colorArgb: (json['colorArgb'] as num).toInt(),
  );
}

class OutfitRecommendation {
  const OutfitRecommendation({
    required this.id,
    required this.title,
    required this.description,
    required this.occasion,
    required this.shirt,
    required this.pants,
    required this.shoes,
    required this.layer,
    required this.reasons,
    required this.fitAdvice,
    this.safetyNote,
  });

  final String id;
  final String title;
  final String description;
  final Occasion occasion;
  final ShirtColor shirt;
  final OutfitPiece pants;
  final OutfitPiece shoes;
  final OutfitPiece layer;
  final List<String> reasons;
  final String fitAdvice;
  final String? safetyNote;

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'description': description,
    'occasion': occasion.name,
    'shirt': shirt.toJson(),
    'pants': pants.toJson(),
    'shoes': shoes.toJson(),
    'layer': layer.toJson(),
    'reasons': reasons,
    'fitAdvice': fitAdvice,
    'safetyNote': safetyNote,
  };

  factory OutfitRecommendation.fromJson(Map<String, dynamic> json) =>
      OutfitRecommendation(
        id: json['id'] as String,
        title: json['title'] as String,
        description: json['description'] as String,
        occasion:
            _enumOrNull(Occasion.values, json['occasion']) ?? Occasion.casual,
        shirt: ShirtColor.fromJson(_jsonMap(json['shirt'])),
        pants: OutfitPiece.fromJson(_jsonMap(json['pants'])),
        shoes: OutfitPiece.fromJson(_jsonMap(json['shoes'])),
        layer: OutfitPiece.fromJson(_jsonMap(json['layer'])),
        reasons: List<String>.unmodifiable(
          (json['reasons'] as List<dynamic>).cast<String>(),
        ),
        fitAdvice: json['fitAdvice'] as String,
        safetyNote: json['safetyNote'] as String?,
      );
}

T? _enumOrNull<T extends Enum>(List<T> values, Object? name) {
  for (final value in values) {
    if (value.name == name) return value;
  }
  return null;
}

Map<String, dynamic> _jsonMap(Object? value) =>
    Map<String, dynamic>.from(value as Map);
