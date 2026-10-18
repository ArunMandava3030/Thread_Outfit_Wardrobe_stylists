import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/style_models.dart';
import '../models/learning_models.dart';
import '../theme.dart';
import 'garment_art.dart';

IconData occasionIcon(Occasion occasion) => switch (occasion) {
  Occasion.office => Icons.work_outline_rounded,
  Occasion.date => Icons.favorite_border_rounded,
  Occasion.casual => Icons.coffee_outlined,
  Occasion.beach => Icons.beach_access_outlined,
  Occasion.bikeRide => Icons.two_wheeler_rounded,
  Occasion.party => Icons.celebration_outlined,
  Occasion.special => Icons.auto_awesome_outlined,
};

class OutfitCard extends StatelessWidget {
  const OutfitCard({
    super.key,
    required this.outfit,
    required this.saved,
    required this.onSave,
    this.index = 0,
    this.feedback,
    this.onFeedback,
    this.onPlan,
    this.wardrobeMatches,
    this.onRate,
  });
  final OutfitRecommendation outfit;
  final bool saved;
  final VoidCallback onSave;
  final int index;
  final StyleFeedback? feedback;
  final ValueChanged<StyleFeedback>? onFeedback;
  final VoidCallback? onPlan;
  final int? wardrobeMatches;
  final VoidCallback? onRate;

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: Colors.white,
      border: Border.all(color: ThreadTheme.line),
      borderRadius: BorderRadius.circular(22),
    ),
    clipBehavior: Clip.antiAlias,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          color: [
            const Color(0xFFEFF0E7),
            const Color(0xFFF2EDE5),
            const Color(0xFFE8EEEB),
          ][index % 3],
          child: Stack(
            children: [
              OutfitArt(
                shirt: Color(outfit.shirt.argb),
                pants: Color(outfit.pants.colorArgb),
                shoes: Color(outfit.shoes.colorArgb),
                layer: Color(outfit.layer.colorArgb),
              ),
              Positioned(
                top: 15,
                left: 16,
                right: 66,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: .85),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Eyebrow(
                    index == 0
                        ? 'Everyday favorite'
                        : index == 1
                        ? 'A fresh perspective'
                        : 'Something different',
                    color: ThreadTheme.green,
                  ),
                ),
              ),
              Positioned(
                right: 10,
                top: 8,
                child: IconButton.filledTonal(
                  tooltip: saved ? 'Remove saved look' : 'Save look',
                  onPressed: onSave,
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.white.withValues(alpha: .9),
                  ),
                  icon: Icon(
                    saved
                        ? Icons.bookmark_rounded
                        : Icons.bookmark_border_rounded,
                    size: 21,
                  ),
                ),
              ),
              const Positioned(
                bottom: 8,
                right: 12,
                child: Text(
                  'COLOR & COMBINATION GUIDE',
                  style: TextStyle(
                    fontSize: 7,
                    letterSpacing: 1,
                    color: ThreadTheme.muted,
                  ),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    occasionIcon(outfit.occasion),
                    size: 13,
                    color: ThreadTheme.muted,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      outfit.occasion.label,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 7),
              Text(outfit.title, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 10),
              _PieceLine(
                piece: OutfitPiece(
                  category: 'Top',
                  title: outfit.shirtTitle,
                  colorName: outfit.shirt.name,
                  colorArgb: outfit.shirt.argb,
                ),
              ),
              _PieceLine(piece: outfit.pants),
              _PieceLine(piece: outfit.shoes),
              if (outfit.layer.colorArgb != 0) _PieceLine(piece: outfit.layer),
              if (wardrobeMatches != null && wardrobeMatches! > 0) ...[
                const SizedBox(height: 10),
                Text(
                  '$wardrobeMatches wardrobe color ${wardrobeMatches == 1 ? 'match' : 'matches'}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: ThreadTheme.green,
                  ),
                ),
              ],
              const SizedBox(height: 10),
              const Divider(),
              Wrap(
                spacing: 8,
                children: [
                  TextButton.icon(
                    onPressed: onSave,
                    icon: Icon(saved ? Icons.favorite : Icons.favorite_border),
                    label: Text(saved ? 'Favorited' : 'Favorite outfit'),
                  ),
                  if (onRate != null)
                    TextButton.icon(
                      onPressed: onRate,
                      icon: const Icon(Icons.star_outline),
                      label: const Text('Rate this outfit'),
                    ),
                ],
              ),
              TextButton(
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(0, 40),
                ),
                onPressed: () => showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  showDragHandle: true,
                  backgroundColor: ThreadTheme.canvas,
                  builder: (context) => _OutfitDetails(outfit: outfit),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(child: Text('Why it works')),
                    Icon(Icons.arrow_outward_rounded, size: 17),
                  ],
                ),
              ),
              if (onFeedback != null || onPlan != null)
                Wrap(
                  spacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    IconButton(
                      tooltip: feedback == StyleFeedback.like
                          ? 'Undo like'
                          : 'Like this look',
                      isSelected: feedback == StyleFeedback.like,
                      selectedIcon: const Icon(Icons.thumb_up),
                      icon: const Icon(Icons.thumb_up_outlined),
                      onPressed: onFeedback == null
                          ? null
                          : () => onFeedback!(StyleFeedback.like),
                    ),
                    IconButton(
                      tooltip: feedback == StyleFeedback.dislike
                          ? 'Undo dislike'
                          : 'Dislike this look',
                      isSelected: feedback == StyleFeedback.dislike,
                      selectedIcon: const Icon(Icons.thumb_down),
                      icon: const Icon(Icons.thumb_down_outlined),
                      onPressed: onFeedback == null
                          ? null
                          : () => onFeedback!(StyleFeedback.dislike),
                    ),
                    if (onPlan != null)
                      TextButton.icon(
                        onPressed: onPlan,
                        icon: const Icon(
                          Icons.event_available_outlined,
                          size: 18,
                        ),
                        label: const Text('Plan look'),
                      ),
                  ],
                ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _PieceLine extends StatelessWidget {
  const _PieceLine({required this.piece});
  final OutfitPiece piece;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: Color(piece.colorArgb),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.black12),
          ),
        ),
        const SizedBox(width: 9),
        Expanded(
          child: Text(
            '${piece.colorName} ${piece.title}',
            style: const TextStyle(fontSize: 12),
          ),
        ),
      ],
    ),
  );
}

class _OutfitDetails extends StatelessWidget {
  const _OutfitDetails({required this.outfit});
  final OutfitRecommendation outfit;
  @override
  Widget build(BuildContext context) => SafeArea(
    child: ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * .86,
        maxWidth: 640,
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Eyebrow(outfit.occasion.label),
            const SizedBox(height: 8),
            Text(
              outfit.title,
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 12),
            Text(outfit.description),
            OutfitArt(
              shirt: Color(outfit.shirt.argb),
              pants: Color(outfit.pants.colorArgb),
              shoes: Color(outfit.shoes.colorArgb),
              layer: Color(outfit.layer.colorArgb),
              height: 235,
            ),
            Text(
              'The color story',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            for (final reason in outfit.reasons)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.check_circle_outline,
                      size: 17,
                      color: ThreadTheme.green,
                    ),
                    const SizedBox(width: 9),
                    Expanded(child: Text(reason)),
                  ],
                ),
              ),
            const SizedBox(height: 10),
            SurfaceCard(
              color: ThreadTheme.softGreen,
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Eyebrow('Make the fit yours'),
                  const SizedBox(height: 8),
                  Text(outfit.fitAdvice),
                ],
              ),
            ),
            if (outfit.safetyNote != null) ...[
              const SizedBox(height: 15),
              Text(
                outfit.safetyNote!,
                style: const TextStyle(fontSize: 12, height: 1.5),
              ),
            ],
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () async {
                  final text =
                      '${outfit.title} · ${outfit.occasion.label}\nTop: ${outfit.shirt.name} ${outfit.shirtTitle}\nPants: ${outfit.pants.colorName} ${outfit.pants.title}\nShoes: ${outfit.shoes.colorName} ${outfit.shoes.title}\nLayer: ${outfit.layer.colorName} ${outfit.layer.title}\n\n${outfit.fitAdvice}${outfit.safetyNote == null ? '' : '\n${outfit.safetyNote}'}';
                  try {
                    await Clipboard.setData(ClipboardData(text: text));
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Outfit copied to clipboard.'),
                        ),
                      );
                    }
                  } catch (_) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Clipboard unavailable on this device.',
                          ),
                        ),
                      );
                    }
                  }
                },
                icon: const Icon(Icons.copy_outlined, size: 17),
                label: const Text('Copy outfit details'),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
