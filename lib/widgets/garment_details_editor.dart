import 'package:flutter/material.dart';

import '../models/style_models.dart';

/// A small optional editor. Nothing changes until the user presses Done.
Future<GarmentDetails?> showGarmentDetailsEditor(
  BuildContext context, {
  required StartingPiece startingPiece,
  required GarmentDetails initial,
  required ShirtColor mainColor,
}) {
  var draft = initial.copyWith(
    accentColors: _uniqueAccents(initial.accentColors, mainColor),
  );
  return showModalBottomSheet<GarmentDetails>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (sheetContext) => StatefulBuilder(
      builder: (sheetContext, updateSheet) => ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(sheetContext).height * .88,
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Type & pattern',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    IconButton(
                      key: const Key('garment_details_cancel'),
                      tooltip: 'Cancel changes',
                      onPressed: () => Navigator.pop(sheetContext),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        DropdownButtonFormField<GarmentType>(
                          key: ValueKey(
                            'garment_type_${draft.type?.name ?? 'any'}',
                          ),
                          initialValue: draft.type,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Clothing type',
                          ),
                          hint: const Text('Any type'),
                          items: [
                            const DropdownMenuItem(
                              value: null,
                              child: Text('Any type'),
                            ),
                            for (final type in GarmentType.values)
                              if (type.isTop ==
                                  (startingPiece == StartingPiece.shirt))
                                DropdownMenuItem(
                                  value: type,
                                  child: Text(type.label),
                                ),
                          ],
                          onChanged: (value) => updateSheet(
                            () => draft = draft.copyWith(type: value),
                          ),
                        ),
                        const SizedBox(height: 20),
                        GarmentPatternFields(
                          details: draft,
                          mainColor: mainColor,
                          onChanged: (value) =>
                              updateSheet(() => draft = value),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  key: const Key('garment_details_done'),
                  onPressed: () => Navigator.pop(sheetContext, draft),
                  child: const Text('Done'),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

/// Shared by the outfit builder and the existing rating garment editor.
/// The owner keeps the draft so the enclosing editor's Cancel still discards it.
class GarmentPatternFields extends StatelessWidget {
  const GarmentPatternFields({
    super.key,
    required this.details,
    required this.mainColor,
    required this.onChanged,
  });

  final GarmentDetails details;
  final ShirtColor mainColor;
  final ValueChanged<GarmentDetails> onChanged;

  @override
  Widget build(BuildContext context) {
    final accents = _uniqueAccents(details.accentColors, mainColor);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Pattern', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            for (final pattern in GarmentPattern.values)
              ChoiceChip(
                key: ValueKey('garment_pattern_${pattern.name}'),
                materialTapTargetSize: MaterialTapTargetSize.padded,
                label: Text(pattern.label),
                selected: details.pattern == pattern,
                onSelected: (_) => onChanged(
                  details.copyWith(
                    pattern: pattern,
                    accentColors: pattern == GarmentPattern.solid
                        ? const []
                        : accents,
                  ),
                ),
              ),
          ],
        ),
        if (details.pattern != GarmentPattern.solid || accents.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text(
            'Other colors (up to 2)',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 4),
          Text(
            '${mainColor.name} is the main color. Add other colors visible on the garment.',
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final color in [
                ...accents,
                ...ShirtColor.presets.where(
                  (preset) =>
                      !accents.any((selected) => selected.argb == preset.argb),
                ),
              ])
                if (color.argb != mainColor.argb)
                  FilterChip(
                    key: ValueKey(
                      'garment_accent_${color.name}_${color.argb.toRadixString(16)}',
                    ),
                    materialTapTargetSize: MaterialTapTargetSize.padded,
                    avatar: CircleAvatar(backgroundColor: Color(color.argb)),
                    label: Text(color.name),
                    selected: accents.any(
                      (selected) => selected.argb == color.argb,
                    ),
                    onSelected:
                        accents.length >= 2 &&
                            !accents.any(
                              (selected) => selected.argb == color.argb,
                            )
                        ? null
                        : (selected) => onChanged(
                            details.copyWith(
                              accentColors: selected
                                  ? [...accents, color]
                                  : accents
                                        .where(
                                          (item) => item.argb != color.argb,
                                        )
                                        .toList(),
                            ),
                          ),
                  ),
            ],
          ),
          if (accents.length == 2)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text('Tap a selected color to replace it.'),
            ),
        ],
      ],
    );
  }
}

List<ShirtColor> _uniqueAccents(List<ShirtColor> colors, ShirtColor mainColor) {
  final seen = <int>{mainColor.argb};
  return colors.where((color) => seen.add(color.argb)).take(2).toList();
}
