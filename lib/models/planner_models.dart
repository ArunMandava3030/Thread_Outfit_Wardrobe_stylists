import 'style_models.dart';

/// A calendar day and outfit, kept on the device independently of saved looks.
class PlannedOutfit {
  PlannedOutfit({
    required this.id,
    required this.outfit,
    required DateTime date,
    this.note = '',
  }) : date = DateTime(date.year, date.month, date.day);

  final String id;
  final OutfitRecommendation outfit;
  final DateTime date;
  final String note;

  PlannedOutfit copyWith({
    OutfitRecommendation? outfit,
    DateTime? date,
    String? note,
  }) => PlannedOutfit(
    id: id,
    outfit: outfit ?? this.outfit,
    date: date ?? this.date,
    note: note ?? this.note,
  );

  // A date is deliberately not serialized as a timestamp: changing time zones
  // must never move an outfit onto the previous or following calendar day.
  Map<String, dynamic> toJson() => {
    'id': id,
    'outfit': outfit.toJson(),
    'date':
        '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}',
    'note': note,
  };

  factory PlannedOutfit.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final rawDate = json['date'];
    final note = json['note'] ?? '';
    if (id is! String || id.isEmpty || rawDate is! String || note is! String) {
      throw const FormatException('Invalid outfit plan.');
    }
    final parts = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(rawDate);
    if (parts == null) throw const FormatException('Invalid plan date.');
    final year = int.parse(parts[1]!);
    final month = int.parse(parts[2]!);
    final day = int.parse(parts[3]!);
    final date = DateTime(year, month, day);
    // DateTime normalizes e.g. February 30; reject it rather than changing a plan.
    if (year < 1 ||
        date.year != year ||
        date.month != month ||
        date.day != day) {
      throw const FormatException('Invalid plan date.');
    }
    return PlannedOutfit(
      id: id,
      outfit: OutfitRecommendation.fromJson(
        Map<String, dynamic>.from(json['outfit'] as Map),
      ),
      date: date,
      note: note,
    );
  }
}
