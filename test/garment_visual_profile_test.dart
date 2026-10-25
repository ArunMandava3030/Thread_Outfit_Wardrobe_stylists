import 'package:flutter_test/flutter_test.dart';
import 'package:thread_style/models/style_models.dart';

void main() {
  const red = ShirtColor(name: 'Red', argb: 0xFFCC2222);
  const black = ShirtColor(name: 'Black', argb: 0xFF000000);
  final profile = GarmentVisualProfile(
    contrast: .7,
    detailDensity: .6,
    directionality: .8,
    dominantAngle: 90,
    regularity: .7,
    sampleWidth: 96,
    sampleHeight: 64,
    opaqueCoverage: 1,
    palette: const [
      VisualColorShare(color: black, share: .7),
      VisualColorShare(color: red, share: .3),
    ],
    previewArgb: List.generate(256, (i) => i % 16 < 8 ? red.argb : black.argb),
  );

  test(
    'continuous descriptors and preview survive JSON with stable identity',
    () {
      final restored = GarmentVisualProfile.fromJson(profile.toJson());
      expect(restored.isReliable, isTrue);
      expect(restored.hasDetail, isTrue);
      expect(restored.signature, profile.signature);
      expect(restored.previewArgb, profile.previewArgb);
      expect(restored.palette.map((swatch) => swatch.share), [.7, .3]);
      expect(restored.shortDescription, contains('Detailed'));
    },
  );

  test('missing or future data is a harmless unreliable observation', () {
    for (final raw in [
      null,
      'invalid',
      <String, dynamic>{},
      {'version': 77},
    ]) {
      final restored = GarmentVisualProfile.fromJson(raw);
      expect(restored.isReliable, isFalse);
      expect(restored.hasDetail, isFalse);
      expect(restored.signature, isNotEmpty);
    }
  });

  test('direct API profiles with invalid color shares are not reliable', () {
    const invalid = GarmentVisualProfile(
      sampleWidth: 96,
      sampleHeight: 96,
      opaqueCoverage: 1,
      palette: [
        VisualColorShare(color: red, share: .9),
        VisualColorShare(color: black, share: .9),
      ],
    );
    expect(invalid.isReliable, isFalse);
  });

  test('malformed metrics, palette and preview stay bounded and finite', () {
    final restored = GarmentVisualProfile.fromJson({
      'contrast': double.nan,
      'detailDensity': 300,
      'directionality': -1,
      'regularity': double.infinity,
      'dominantAngle': -90,
      'sampleWidth': 100000,
      'sampleHeight': 96,
      'opaqueCoverage': 7,
      'palette': [
        null,
        {
          'color': {'name': 'Broken', 'argb': -1},
          'share': 1,
        },
        for (var i = 0; i < 1000; i++)
          {
            'color': {'name': 'Color $i', 'argb': 0xFF000000 + i},
            'share': .5,
          },
      ],
      'previewArgb': [null, -3, for (var i = 0; i < 1000; i++) 0xFFFFFFFF],
    });
    expect(restored.isReliable, isFalse);
    expect(restored.contrast, 0);
    expect(restored.detailDensity, 1);
    expect(restored.directionality, 0);
    expect(restored.regularity, 0);
    expect(restored.dominantAngle, 90);
    expect(restored.palette.length, lessThanOrEqualTo(6));
    expect(
      restored.palette.fold<double>(0, (sum, swatch) => sum + swatch.share),
      closeTo(1, .001),
    );
    expect(restored.previewArgb.length, 256);
    expect(restored.previewArgb.take(2), [0, 0]);
  });

  test(
    'palette labels do not change the design identity but spatial changes do',
    () {
      final renamed = profile.toJson();
      final palette = renamed['palette'] as List;
      ((palette[0] as Map)['color'] as Map)['name'] = 'Another name';
      expect(
        GarmentVisualProfile.fromJson(renamed).signature,
        profile.signature,
      );
      final rearranged = profile.toJson();
      rearranged['previewArgb'] = profile.previewArgb.reversed.toList();
      expect(
        GarmentVisualProfile.fromJson(rearranged).signature,
        isNot(profile.signature),
      );
    },
  );
}
