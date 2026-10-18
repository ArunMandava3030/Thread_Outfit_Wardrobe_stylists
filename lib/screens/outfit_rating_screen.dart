import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/learning_models.dart';
import '../models/outfit_rating_models.dart';
import '../models/style_discovery_models.dart';
import '../models/style_models.dart';
import '../models/trend_models.dart';
import '../services/outfit_rater.dart';
import '../services/trend_service.dart';
import '../theme.dart';

class OutfitRatingScreen extends StatefulWidget {
  const OutfitRatingScreen({
    super.key,
    required this.profile,
    required this.hasProfile,
    required this.history,
    required this.onFavorite,
    this.savedIds = const {},
    this.initialOutfit,
    this.trendService,
    this.onPickColor,
  });

  final StyleProfile profile;
  final bool hasProfile;
  final List<StyleFeedbackEntry> history;
  final Future<void> Function(OutfitRecommendation) onFavorite;
  final Set<String> savedIds;
  final OutfitRecommendation? initialOutfit;
  final TrendService? trendService;
  final Future<ShirtColor?> Function(String garmentLabel)? onPickColor;

  @override
  State<OutfitRatingScreen> createState() => _OutfitRatingScreenState();
}

class _OutfitRatingScreenState extends State<OutfitRatingScreen> {
  ShirtColor _topColor = ShirtColor.presets[3];
  ShirtColor _pantsColor = ShirtColor.presets[2];
  ShirtColor _shoesColor = ShirtColor.presets[3];
  ShirtColor _layerColor = ShirtColor.presets[5];
  RatingTop _top = RatingTop.shirt;
  RatingBottom _bottom = RatingBottom.chinos;
  RatingShoes _shoes = RatingShoes.sneakers;
  RatingLayer _layer = RatingLayer.none;
  Occasion _occasion = Occasion.casual;
  StyleDirection _direction = StyleDirection.everyday;
  DressExpectation _dress = DressExpectation.occasionDefault;
  FitComfort _comfort = FitComfort.unknown;
  TrouserHem _hem = TrouserHem.unknown;
  SilhouetteFit _silhouette = SilhouetteFit.unknown;
  bool _includeTrends = false;
  bool _loadingTrends = false;
  bool _saving = false;
  bool _picking = false;
  TrendSnapshot? _trends;
  String? _trendError;
  OutfitRating? _rating;
  final _savedThisSession = <String>{};
  late TrendService _trendService;
  late bool _ownsTrendService;

  @override
  void initState() {
    super.initState();
    _ownsTrendService = widget.trendService == null;
    _trendService = widget.trendService ?? TrendService();
    if (widget.initialOutfit case final outfit?) _applyInitial(outfit);
  }

  @override
  void didUpdateWidget(covariant OutfitRatingScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialOutfit?.id != widget.initialOutfit?.id &&
        widget.initialOutfit != null) {
      _applyInitial(widget.initialOutfit!);
      _rating = null;
    }
    if (oldWidget.profile != widget.profile ||
        oldWidget.hasProfile != widget.hasProfile ||
        oldWidget.history != widget.history) {
      _rating = null;
    }
  }

  @override
  void dispose() {
    if (_ownsTrendService) _trendService.dispose();
    super.dispose();
  }

  void _applyInitial(OutfitRecommendation outfit) {
    _topColor = outfit.shirt;
    _pantsColor = ShirtColor(
      name: outfit.pants.colorName,
      argb: outfit.pants.colorArgb,
    );
    _shoesColor = ShirtColor(
      name: outfit.shoes.colorName,
      argb: outfit.shoes.colorArgb,
    );
    _occasion = outfit.occasion;
    final top = outfit.shirtTitle.toLowerCase();
    _top = top.contains('polo')
        ? RatingTop.polo
        : top.contains('knit')
        ? RatingTop.knit
        : top.contains('t-shirt') || top.contains('tee')
        ? RatingTop.tee
        : RatingTop.shirt;
    final bottom = outfit.pants.title.toLowerCase();
    _bottom = bottom.contains('motorcycle') || bottom.contains('riding')
        ? RatingBottom.riding
        : bottom.contains('short')
        ? RatingBottom.shorts
        : bottom.contains('jean') || bottom.contains('denim')
        ? RatingBottom.jeans
        : bottom.contains('tailor')
        ? RatingBottom.tailored
        : bottom.contains('track') || bottom.contains('jogger')
        ? RatingBottom.track
        : RatingBottom.chinos;
    final shoes = outfit.shoes.title.toLowerCase();
    _shoes = shoes.contains('motorcycle') || shoes.contains('riding')
        ? RatingShoes.riding
        : shoes.contains('loafer')
        ? RatingShoes.loafers
        : shoes.contains('sandal')
        ? RatingShoes.sandals
        : shoes.contains('oxford') ||
              shoes.contains('derby') ||
              shoes.contains('dress')
        ? RatingShoes.dress
        : RatingShoes.sneakers;
    final layer = outfit.layer.title.toLowerCase();
    _layer = outfit.layer.colorArgb == 0
        ? RatingLayer.none
        : layer.contains('motorcycle') || layer.contains('riding')
        ? RatingLayer.riding
        : layer.contains('blazer')
        ? RatingLayer.blazer
        : layer.contains('cardigan')
        ? RatingLayer.cardigan
        : layer.contains('jacket')
        ? RatingLayer.jacket
        : RatingLayer.overshirt;
    if (_layer != RatingLayer.none) {
      _layerColor = ShirtColor(
        name: outfit.layer.colorName,
        argb: outfit.layer.colorArgb,
      );
    }
    _comfort = FitComfort.unknown;
    _hem = TrouserHem.unknown;
    _silhouette = SilhouetteFit.unknown;
  }

  void _edit(VoidCallback change) => setState(() {
    change();
    _rating = null;
  });

  OutfitRatingInput get _input => OutfitRatingInput(
    topColor: _topColor,
    pantsColor: _pantsColor,
    shoesColor: _shoesColor,
    layerColor: _layerColor,
    top: _top,
    bottom: _bottom,
    shoes: _shoes,
    layer: _layer,
    occasion: _occasion,
    direction: _direction,
    dressExpectation: _dress,
    comfort: _comfort,
    hem: _hem,
    silhouette: _silhouette,
    includeTrends: _includeTrends,
  );

  Future<void> _loadTrends() async {
    if (_loadingTrends) return;
    setState(() {
      _loadingTrends = true;
      _trendError = null;
    });
    try {
      final trends = await _trendService.fetchTrends();
      if (!mounted) return;
      _edit(() => _trends = trends);
    } catch (_) {
      if (!mounted) return;
      setState(
        () => _trendError =
            'Headlines are unavailable. You can still rate the outfit without them.',
      );
    } finally {
      if (mounted) setState(() => _loadingTrends = false);
    }
  }

  Future<void> _pickColor(
    String garment,
    ValueChanged<ShirtColor> onChanged,
  ) async {
    if (_picking || widget.onPickColor == null) return;
    setState(() => _picking = true);
    try {
      final color = await widget.onPickColor!(garment);
      if (mounted && color != null) _edit(() => onChanged(color));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Photo color could not be read. You can choose a color manually.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  Future<void> _save(OutfitRating rating) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await widget.onFavorite(rating.outfit);
      if (mounted) setState(() => _savedThisSession.add(rating.outfit.id));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('The favorite could not be saved. Please try again.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _openEvidence(TrendHeadline evidence) async {
    try {
      if (await launchUrl(
        Uri.parse(evidence.url),
        mode: LaunchMode.externalApplication,
      )) {
        return;
      }
    } catch (_) {
      /* Display the same actionable failure below. */
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('The article could not be opened.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Eyebrow('A second look, your way'),
        const SizedBox(height: 12),
        Text('Rate my outfit', style: theme.textTheme.displayMedium),
        const SizedBox(height: 12),
        const Text(
          'Tell Thread what you are wearing. Confirm the garment types and colors, then get a styling estimate from 0 to 5 with practical changes to try.',
        ),
        const SizedBox(height: 8),
        Text(
          widget.hasProfile
              ? 'Your saved profile is ready for optional palette and fit advice.'
              : 'You can rate an outfit without a profile. Add one later for personal palette and fit advice.',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 24),
        SurfaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '1. What are you wearing?',
                style: theme.textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              const Text(
                'Colors alone cannot identify garment type or fit. Edit each piece to match your actual outfit.',
              ),
              if (widget.initialOutfit != null) ...[
                const SizedBox(height: 8),
                const Text(
                  'These starting values come from an outfit suggestion. Confirm or change every garment type before rating what you are actually wearing.',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ],
              const SizedBox(height: 18),
              LayoutBuilder(
                builder: (context, constraints) {
                  final columns = constraints.maxWidth >= 620 ? 2 : 1;
                  final width =
                      (constraints.maxWidth - (columns - 1) * 20) / columns;
                  return Wrap(
                    spacing: 20,
                    runSpacing: 22,
                    children: [
                      SizedBox(
                        width: width,
                        child: _garment(
                          'Top',
                          _dropdown(
                            'Top type',
                            _top,
                            RatingTop.values,
                            (value) => value.label,
                            (value) => _edit(() => _top = value),
                          ),
                          _topColor,
                          (color) => _topColor = color,
                        ),
                      ),
                      SizedBox(
                        width: width,
                        child: _garment(
                          'Pants',
                          _dropdown(
                            'Bottom type',
                            _bottom,
                            RatingBottom.values,
                            (value) => value.label,
                            (value) => _edit(() => _bottom = value),
                          ),
                          _pantsColor,
                          (color) => _pantsColor = color,
                        ),
                      ),
                      SizedBox(
                        width: width,
                        child: _garment(
                          'Shoes',
                          _dropdown(
                            'Shoe type',
                            _shoes,
                            RatingShoes.values,
                            (value) => value.label,
                            (value) => _edit(() => _shoes = value),
                          ),
                          _shoesColor,
                          (color) => _shoesColor = color,
                        ),
                      ),
                      SizedBox(
                        width: width,
                        child: _garment(
                          'Layer',
                          _dropdown(
                            'Layer type',
                            _layer,
                            RatingLayer.values,
                            (value) => value.label,
                            (value) => _edit(() => _layer = value),
                          ),
                          _layerColor,
                          (color) => _layerColor = color,
                          showColor: _layer != RatingLayer.none,
                        ),
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        SurfaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '2. Where are you going?',
                style: theme.textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              _dropdown(
                'Rating occasion',
                _occasion,
                Occasion.values,
                (value) => value.label,
                (value) => _edit(() => _occasion = value),
              ),
              const SizedBox(height: 14),
              _dropdown(
                'Dress code',
                _dress,
                DressExpectation.values,
                (value) => value.label,
                (value) => _edit(() => _dress = value),
              ),
              const SizedBox(height: 14),
              _dropdown(
                'Your style direction',
                _direction,
                StyleDirection.values,
                (value) => value.label,
                (value) => _edit(() => _direction = value),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        SurfaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('3. Add a fit check', style: theme.textTheme.titleLarge),
              const SizedBox(height: 8),
              const Text(
                'Optional. Your height and shoulder proportions cannot tell whether a particular garment fits. These observations can.',
              ),
              const SizedBox(height: 16),
              _dropdown(
                'Movement and comfort',
                _comfort,
                FitComfort.values,
                (value) => value.label,
                (value) => _edit(() => _comfort = value),
              ),
              if (_bottom != RatingBottom.shorts) ...[
                const SizedBox(height: 14),
                _dropdown(
                  'Trouser hem',
                  _hem,
                  TrouserHem.values,
                  (value) => value.label,
                  (value) => _edit(() => _hem = value),
                ),
              ],
              const SizedBox(height: 14),
              _dropdown(
                'Your preferred silhouette',
                _silhouette,
                SilhouetteFit.values,
                (value) => value.label,
                (value) => _edit(() => _silhouette = value),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        SurfaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text('Consider recent style headlines'),
                subtitle: const Text(
                  'Optional: a small bonus for a fresh headline that mentions your selected style. This does not measure popularity.',
                ),
                value: _includeTrends,
                onChanged: (value) {
                  _edit(() => _includeTrends = value);
                  if (value && _trends == null) _loadTrends();
                },
              ),
              if (_includeTrends) ...[
                OutlinedButton.icon(
                  onPressed: _loadingTrends ? null : _loadTrends,
                  icon: const Icon(Icons.refresh, size: 18),
                  label: Text(
                    _loadingTrends
                        ? 'Checking headlines…'
                        : 'Refresh rating headlines',
                  ),
                ),
                if (_trends != null)
                  Text(
                    'Feed checked ${_trends!.fetchedAt.toUtc().toIso8601String().substring(0, 10)} (UTC).${_trends!.isStaleAt(DateTime.now()) ? ' Over 48 hours old; no trend bonus applies.' : ''}',
                    style: theme.textTheme.bodySmall,
                  ),
                if (_trendError != null)
                  Text(_trendError!, style: theme.textTheme.bodySmall),
              ],
            ],
          ),
        ),
        const SizedBox(height: 22),
        FilledButton.icon(
          key: const Key('rate_current_outfit'),
          onPressed: _picking
              ? null
              : () => setState(
                  () => _rating = const OutfitRater().rate(
                    _input,
                    profile: widget.profile,
                    hasProfile: widget.hasProfile,
                    history: widget.history,
                    trends: _trends,
                  ),
                ),
          icon: const Icon(Icons.star_outline_rounded),
          label: const Text('Rate this outfit'),
        ),
        const SizedBox(height: 10),
        const Text(
          'A subjective styling estimate from explainable rules and your local preference model. It rates garment choices, not your appearance. Photos and profile details stay on this device.',
          style: TextStyle(fontSize: 12, color: ThreadTheme.muted),
        ),
        if (_rating case final rating?) ...[
          const SizedBox(height: 24),
          _result(rating),
        ],
      ],
    );
  }

  Widget _dropdown<T extends Enum>(
    String label,
    T value,
    List<T> values,
    String Function(T) name,
    ValueChanged<T> onChanged,
  ) => DropdownButtonFormField<T>(
    key: ValueKey('rating-$label-${value.name}'),
    initialValue: value,
    isExpanded: true,
    decoration: InputDecoration(labelText: label),
    items: [
      for (final item in values)
        DropdownMenuItem(
          value: item,
          child: Text(name(item), maxLines: 2, overflow: TextOverflow.ellipsis),
        ),
    ],
    onChanged: (value) {
      if (value != null) onChanged(value);
    },
  );

  Widget _garment(
    String label,
    Widget typeField,
    ShirtColor color,
    ValueChanged<ShirtColor> update, {
    bool showColor = true,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      typeField,
      if (showColor) ...[
        const SizedBox(height: 12),
        Wrap(
          spacing: 10,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                color: Color(color.argb),
                shape: BoxShape.circle,
                border: Border.all(color: ThreadTheme.line),
              ),
            ),
            Text(
              '$label color: ${color.name}',
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 4,
          runSpacing: 4,
          children: [
            for (final preset in ShirtColor.presets)
              Semantics(
                label: '$label ${preset.name}',
                selected: color.argb == preset.argb,
                button: true,
                child: Tooltip(
                  message: preset.name,
                  child: InkWell(
                    key: ValueKey('rating-$label-color-${preset.name}'),
                    onTap: () => _edit(() => update(preset)),
                    borderRadius: BorderRadius.circular(22),
                    child: SizedBox(
                      width: 44,
                      height: 44,
                      child: Center(
                        child: Container(
                          width: 30,
                          height: 30,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Color(preset.argb),
                            border: Border.all(
                              color: color.argb == preset.argb
                                  ? ThreadTheme.ink
                                  : ThreadTheme.line,
                              width: color.argb == preset.argb ? 3 : 1,
                            ),
                          ),
                          child: color.argb == preset.argb
                              ? Icon(
                                  Icons.check,
                                  size: 18,
                                  color:
                                      Color(preset.argb).computeLuminance() > .4
                                      ? ThreadTheme.ink
                                      : Colors.white,
                                )
                              : null,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
        if (widget.onPickColor != null)
          TextButton.icon(
            onPressed: _picking ? null : () => _pickColor(label, update),
            icon: const Icon(Icons.add_a_photo_outlined, size: 17),
            label: Text('Read $label color from photo'),
          ),
      ],
    ],
  );

  Widget _result(OutfitRating rating) {
    final saved =
        widget.savedIds.contains(rating.outfit.id) ||
        _savedThisSession.contains(rating.outfit.id);
    return SurfaceCard(
      key: const Key('outfit_rating_result'),
      color: ThreadTheme.softGreen,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Eyebrow('Your styling estimate'),
          const SizedBox(height: 8),
          Text(
            '${rating.score.toStringAsFixed(1)} / 5',
            key: const Key('outfit_rating_score'),
            style: Theme.of(context).textTheme.displayMedium,
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            key: const Key('favorite_rated_outfit'),
            onPressed: saved || _saving ? null : () => _save(rating),
            icon: Icon(saved ? Icons.favorite : Icons.favorite_border),
            label: Text(
              saved
                  ? 'Saved to favorites'
                  : _saving
                  ? 'Saving…'
                  : 'Favorite this outfit',
            ),
          ),
          const SizedBox(height: 18),
          Text('Things to try', style: Theme.of(context).textTheme.titleLarge),
          for (final suggestion in rating.suggestions)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(suggestion),
            ),
          const SizedBox(height: 18),
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            childrenPadding: const EdgeInsets.only(bottom: 12),
            title: const Text('Personal palette and fit notes'),
            expandedCrossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final advice in rating.profileAdvice)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Text(advice),
                ),
            ],
          ),
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            childrenPadding: const EdgeInsets.only(bottom: 12),
            title: const Text('How this score works'),
            expandedCrossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final component in rating.components)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${component.label}: ${component.score.toStringAsFixed(1)} / 5',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text(component.explanation),
                    ],
                  ),
                ),
              Text(
                'Rules ${rating.baseScore.toStringAsFixed(2)} · Learned preference ${rating.preferenceAdjustment >= 0 ? '+' : ''}${rating.preferenceAdjustment.toStringAsFixed(2)} · Headlines +${rating.trendAdjustment.toStringAsFixed(2)}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 10),
              Text(rating.preferenceNote),
              const SizedBox(height: 6),
              Text(rating.trendNote),
              if (rating.trendEvidence case final evidence?)
                TextButton.icon(
                  onPressed: () => _openEvidence(evidence),
                  icon: const Icon(Icons.open_in_new, size: 16),
                  label: Text(
                    '${evidence.publisher}: ${evidence.headline} (${evidence.publishedAt.toUtc().toIso8601String().substring(0, 10)})',
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
