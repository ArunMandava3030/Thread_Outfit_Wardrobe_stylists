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
import '../widgets/garment_details_editor.dart';

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
  GarmentDetails _topDetails = const GarmentDetails();
  GarmentDetails _pantsDetails = const GarmentDetails();
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
  bool _moreOptions = false;
  TrendSnapshot? _trends;
  String? _trendError;
  OutfitRating? _rating;
  final _resultKey = GlobalKey();
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
    _topDetails = outfit.topDetails;
    _pantsDetails = outfit.pantsDetails;
    final top = outfit.shirtTitle.toLowerCase();
    _top = top.contains('flannel')
        ? RatingTop.flannel
        : top.contains('polo')
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
    // Saved metadata takes precedence over older titles when available.
    _top = switch (_topDetails.type) {
      GarmentType.shirt => RatingTop.shirt,
      GarmentType.tShirt => RatingTop.tee,
      GarmentType.polo => RatingTop.polo,
      GarmentType.flannel => RatingTop.flannel,
      GarmentType.knit => RatingTop.knit,
      _ => _top,
    };
    _bottom = switch (_pantsDetails.type) {
      GarmentType.jeans => RatingBottom.jeans,
      GarmentType.chinos => RatingBottom.chinos,
      GarmentType.trousers => RatingBottom.tailored,
      GarmentType.shorts => RatingBottom.shorts,
      GarmentType.joggers => RatingBottom.track,
      _ => _bottom,
    };
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

  void _rate() {
    setState(() {
      _rating = const OutfitRater().rate(
        _input,
        profile: widget.profile,
        hasProfile: widget.hasProfile,
        history: widget.history,
        trends: _trends,
      );
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final resultContext = _resultKey.currentContext;
      if (!mounted || resultContext == null) return;
      Scrollable.ensureVisible(
        resultContext,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOutCubic,
        alignment: .05,
      );
    });
  }

  OutfitRatingInput get _input => OutfitRatingInput(
    topColor: _topColor,
    pantsColor: _pantsColor,
    shoesColor: _shoesColor,
    layerColor: _layerColor,
    top: _top,
    bottom: _bottom,
    topDetails: _topDetails,
    pantsDetails: _pantsDetails,
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
      setState(() => _trends = trends);
      // A delayed headline response must not send someone back to the form.
      if (_rating != null) _rate();
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

  Future<ShirtColor?> _pickColor(String garment) async {
    if (_picking || widget.onPickColor == null) return null;
    setState(() => _picking = true);
    try {
      final color = await widget.onPickColor!(garment);
      return mounted ? color : null;
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
    return null;
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
    if (_rating case final rating?) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextButton.icon(
            key: const Key('rating_edit_outfit'),
            onPressed: () => setState(() => _rating = null),
            icon: const Icon(Icons.arrow_back, size: 18),
            label: const Text('Edit outfit'),
          ),
          const SizedBox(height: 8),
          KeyedSubtree(key: _resultKey, child: _result(rating)),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Your outfit', style: theme.textTheme.headlineMedium),
        const SizedBox(height: 6),
        Text(
          widget.initialOutfit == null
              ? 'Check these pieces match what you are wearing, then rate your outfit.'
              : 'These pieces come from your suggestion. Check the types and colors match what you are wearing.',
        ),
        const SizedBox(height: 16),
        SurfaceCard(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Column(
            children: [
              _garmentRow(
                'Top',
                _top.label,
                _topColor,
                () => _editGarment(
                  label: 'Top',
                  typeLabel: 'Top type',
                  type: _top,
                  types: RatingTop.values,
                  name: (value) => value.label,
                  color: _topColor,
                  details: _topDetails,
                  onDone: (type, color, details) => _edit(() {
                    _top = type;
                    _topColor = color;
                    _topDetails = details.copyWith(type: type.garmentType);
                  }),
                ),
                details: _topDetails,
              ),
              const Divider(height: 1),
              _garmentRow(
                'Pants',
                _bottom.label,
                _pantsColor,
                () => _editGarment(
                  label: 'Pants',
                  typeLabel: 'Bottom type',
                  type: _bottom,
                  types: RatingBottom.values,
                  name: (value) => value.label,
                  color: _pantsColor,
                  details: _pantsDetails,
                  onDone: (type, color, details) => _edit(() {
                    _bottom = type;
                    _pantsColor = color;
                    _pantsDetails = details.copyWith(type: type.garmentType);
                  }),
                ),
                details: _pantsDetails,
              ),
              const Divider(height: 1),
              _garmentRow(
                'Shoes',
                _shoes.label,
                _shoesColor,
                () => _editGarment(
                  label: 'Shoes',
                  typeLabel: 'Shoe type',
                  type: _shoes,
                  types: RatingShoes.values,
                  name: (value) => value.label,
                  color: _shoesColor,
                  onDone: (type, color, _) => _edit(() {
                    _shoes = type;
                    _shoesColor = color;
                  }),
                ),
              ),
              const Divider(height: 1),
              _garmentRow(
                'Layer',
                _layer.label,
                _layer == RatingLayer.none ? null : _layerColor,
                () => _editGarment(
                  label: 'Layer',
                  typeLabel: 'Layer type',
                  type: _layer,
                  types: RatingLayer.values,
                  name: (value) => value.label,
                  color: _layerColor,
                  hasColor: (value) => value != RatingLayer.none,
                  onDone: (type, color, _) => _edit(() {
                    _layer = type;
                    _layerColor = color;
                  }),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _dropdown(
          'Occasion',
          _occasion,
          Occasion.values,
          (value) => value.label,
          (value) => _edit(() => _occasion = value),
        ),
        const SizedBox(height: 8),
        ExpansionTile(
          key: const Key('rating_more_options'),
          initiallyExpanded: _moreOptions,
          onExpansionChanged: (expanded) => _moreOptions = expanded,
          tilePadding: EdgeInsets.zero,
          childrenPadding: const EdgeInsets.only(bottom: 16),
          title: const Text('More options'),
          children: [_options()],
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            key: const Key('rate_current_outfit'),
            onPressed: _picking ? null : _rate,
            icon: const Icon(Icons.star_outline_rounded),
            label: const Text('Rate this outfit'),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          widget.hasProfile
              ? 'Your saved profile is included in the personal advice.'
              : 'No profile needed. Add one later for personal advice.',
          style: theme.textTheme.bodySmall,
        ),
      ],
    );
  }

  Widget _options() {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _dropdown(
          'Dress code',
          _dress,
          DressExpectation.values,
          (value) => value.label,
          (value) => _edit(() => _dress = value),
        ),
        const SizedBox(height: 14),
        _dropdown(
          'Style',
          _direction,
          StyleDirection.values,
          (value) => value.label,
          (value) => _edit(() => _direction = value),
        ),
        const SizedBox(height: 20),
        Text('How does it fit?', style: theme.textTheme.titleMedium),
        const SizedBox(height: 6),
        const Text(
          'Optional. Choose what you notice when wearing these clothes.',
        ),
        const SizedBox(height: 14),
        _dropdown(
          'Comfort',
          _comfort,
          FitComfort.values,
          (value) => value.label,
          (value) => _edit(() => _comfort = value),
        ),
        if (_bottom != RatingBottom.shorts) ...[
          const SizedBox(height: 14),
          _dropdown(
            'Pants length',
            _hem,
            TrouserHem.values,
            (value) => value.label,
            (value) => _edit(() => _hem = value),
          ),
        ],
        const SizedBox(height: 14),
        _dropdown(
          'Overall fit',
          _silhouette,
          SilhouetteFit.values,
          (value) => value.label,
          (value) => _edit(() => _silhouette = value),
        ),
        const SizedBox(height: 8),
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          title: const Text('Include current trends'),
          subtitle: const Text('Fresh style headlines can add a small bonus.'),
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
              _loadingTrends ? 'Checking headlines…' : 'Refresh headlines',
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
    );
  }

  Widget _garmentRow(
    String label,
    String type,
    ShirtColor? color,
    VoidCallback onEdit, {
    GarmentDetails? details,
  }) => Row(
    children: [
      Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: color == null ? ThreadTheme.canvas : Color(color.argb),
          shape: BoxShape.circle,
          border: Border.all(color: ThreadTheme.line),
        ),
        child: color == null ? const Icon(Icons.remove, size: 16) : null,
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: Theme.of(context).textTheme.titleSmall),
              Text(
                color == null ? type : '${color.name} · $type',
                key: ValueKey('rating-summary-$label'),
                style: Theme.of(context).textTheme.bodySmall,
              ),
              if (details?.measuredVisual case final visual?)
                Text(
                  visual.shortDescription,
                  style: Theme.of(context).textTheme.bodySmall,
                )
              else if (details != null &&
                  (details.pattern != GarmentPattern.solid ||
                      details.accentColors.isNotEmpty))
                Text(
                  '${details.pattern == GarmentPattern.solid ? 'Multicolor' : details.pattern.label}${details.accentColors.isEmpty ? '' : ' · ${details.accentColors.map((color) => color.name).join(', ')}'}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
            ],
          ),
        ),
      ),
      TextButton(
        key: ValueKey('rating-edit-$label'),
        onPressed: _picking ? null : onEdit,
        child: Text(color == null ? 'Add' : 'Edit'),
      ),
    ],
  );

  Future<void> _editGarment<T extends Enum>({
    required String label,
    required String typeLabel,
    required T type,
    required List<T> types,
    required String Function(T) name,
    required ShirtColor color,
    required void Function(T, ShirtColor, GarmentDetails) onDone,
    GarmentDetails? details,
    bool Function(T)? hasColor,
  }) async {
    var draftType = type;
    var draftColor = color;
    var draftDetails = details ?? const GarmentDetails();
    var picking = false;
    final confirmed = await showModalBottomSheet<bool>(
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
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Edit ${label.toLowerCase()}',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ),
                      IconButton(
                        key: const Key('rating-editor-cancel'),
                        onPressed: () => Navigator.pop(sheetContext, false),
                        tooltip: 'Cancel changes',
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Flexible(
                    child: SingleChildScrollView(
                      key: const Key('rating-editor-scroll'),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _dropdown(
                            typeLabel,
                            draftType,
                            types,
                            name,
                            (value) => updateSheet(() => draftType = value),
                          ),
                          if (hasColor?.call(draftType) ?? true) ...[
                            const SizedBox(height: 18),
                            Text(
                              '$label color: ${draftColor.name}',
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 4,
                              children: [
                                for (final preset in ShirtColor.presets)
                                  ChoiceChip(
                                    key: ValueKey(
                                      'rating-$label-color-${preset.name}',
                                    ),
                                    label: Text(preset.name),
                                    avatar: CircleAvatar(
                                      backgroundColor: Color(preset.argb),
                                    ),
                                    selected: draftColor.argb == preset.argb,
                                    onSelected: (_) => updateSheet(() {
                                      if (draftColor.argb != preset.argb) {
                                        draftDetails = draftDetails.copyWith(
                                          accentColors: const [],
                                          visualProfile: null,
                                        );
                                      }
                                      draftColor = preset;
                                    }),
                                  ),
                              ],
                            ),
                            if (widget.onPickColor != null) ...[
                              const SizedBox(height: 12),
                              OutlinedButton.icon(
                                key: const Key('rating-editor-photo'),
                                onPressed: picking
                                    ? null
                                    : () async {
                                        updateSheet(() => picking = true);
                                        final sampled = await _pickColor(label);
                                        if (!sheetContext.mounted) return;
                                        updateSheet(() {
                                          picking = false;
                                          if (sampled != null) {
                                            if (draftColor.argb !=
                                                sampled.argb) {
                                              draftDetails = draftDetails
                                                  .copyWith(
                                                    accentColors: const [],
                                                    visualProfile: null,
                                                  );
                                            }
                                            draftColor = sampled;
                                          }
                                        });
                                      },
                                icon: const Icon(
                                  Icons.add_a_photo_outlined,
                                  size: 18,
                                ),
                                label: Text(
                                  picking
                                      ? 'Reading photo…'
                                      : 'Pick color from photo',
                                ),
                              ),
                              const SizedBox(height: 4),
                              const Text(
                                'Photo sampling reads color. Confirm the clothing type and pattern yourself.',
                              ),
                            ],
                            if (details != null) ...[
                              const SizedBox(height: 20),
                              GarmentPatternFields(
                                details: draftDetails,
                                mainColor: draftColor,
                                onChanged: (value) =>
                                    updateSheet(() => draftDetails = value),
                              ),
                            ],
                          ],
                          const SizedBox(height: 8),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      key: const Key('rating-editor-done'),
                      onPressed: picking
                          ? null
                          : () => Navigator.pop(sheetContext, true),
                      child: const Text('Done'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    if (mounted && confirmed == true) {
      onDone(draftType, draftColor, draftDetails);
    }
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
              const Text(
                'A subjective styling estimate based on clothes, occasion, fit checks and your local preferences. Photos and profile details stay on this device.',
              ),
              const SizedBox(height: 12),
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
