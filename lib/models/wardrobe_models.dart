import 'garment_details.dart';

enum WardrobeCategory {
  shirt,
  pants,
  shoes,
  layer;

  String get label => switch (this) {
    shirt => 'Shirts',
    pants => 'Pants',
    shoes => 'Shoes',
    layer => 'Layers',
  };
}

class WardrobeItem {
  const WardrobeItem({
    required this.id,
    required this.name,
    required this.colorName,
    required this.colorArgb,
    required this.category,
    this.details = const GarmentDetails(),
  });

  final String id;
  final String name;
  final String colorName;
  final int colorArgb;
  final WardrobeCategory category;
  final GarmentDetails details;

  String get hex =>
      '#${(colorArgb & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'colorName': colorName,
    'colorArgb': colorArgb,
    'category': category.name,
    'details': details.toJson(),
  };

  factory WardrobeItem.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final name = json['name'];
    final colorName = json['colorName'];
    final color = json['colorArgb'];
    WardrobeCategory? category;
    for (final value in WardrobeCategory.values) {
      if (value.name == json['category']) category = value;
    }
    if (id is! String ||
        id.trim().isEmpty ||
        name is! String ||
        name.trim().isEmpty ||
        name.runes.length > 60 ||
        colorName is! String ||
        colorName.trim().isEmpty ||
        color is! int ||
        color < 0xFF000000 ||
        color > 0xFFFFFFFF ||
        category == null) {
      throw const FormatException('Invalid wardrobe item.');
    }
    return WardrobeItem(
      id: id,
      name: name.trim(),
      colorName: colorName.trim(),
      colorArgb: color,
      category: category,
      details: GarmentDetails.fromJson(json['details']),
    );
  }
}
