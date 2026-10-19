import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'models/style_discovery_models.dart';
import 'models/style_models.dart';
import 'services/style_direction_stylist.dart';
import 'services/style_engine.dart';
import 'theme.dart';
import 'widgets/garment_art.dart';
import 'widgets/trend_panel.dart';

/// A session-only public preview. Its entrypoint never opens a profile store or
/// photo analyzer, so basic styling works with browser storage unavailable.
class ThreadGuestApp extends StatelessWidget {
  const ThreadGuestApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Try Thread · Find your next outfit',
    debugShowCheckedModeBanner: false,
    theme: ThreadTheme.theme,
    home: const _GuestStudio(),
  );
}

class _GuestStudio extends StatefulWidget {
  const _GuestStudio();

  @override
  State<_GuestStudio> createState() => _GuestStudioState();
}

class _GuestStudioState extends State<_GuestStudio> {
  final _form = GlobalKey<FormState>();
  final _flow = GlobalKey();
  final _height = TextEditingController();
  final _optionsController = ExpansibleController();
  StartingPiece _startingPiece = StartingPiece.shirt;
  ShirtColor _color = ShirtColor.presets.first;
  ShirtColor? _matchingColor;
  int _step = 0;
  Occasion _occasion = Occasion.casual;
  StyleDirection _direction = StyleDirection.everyday;
  bool _includeLayer = true;
  List<OutfitRecommendation> _outfits = const [];
  bool _heightProvided = false;
  bool _showMoreOutfits = false;

  @override
  void dispose() {
    _height.dispose();
    _optionsController.dispose();
    super.dispose();
  }

  void _change(VoidCallback update) => setState(() {
    update();
    _outfits = const [];
    _showMoreOutfits = false;
    if (_step == 3) _step = 2;
  });

  void _changeStartingItem(VoidCallback update) => _change(() {
    update();
    _matchingColor = null;
  });

  void _goTo(int step) {
    setState(() {
      if (step == 1 && _matchingColor == null) {
        _matchingColor = const StyleEngine()
            .matchingColors(startingPiece: _startingPiece, color: _color)
            .first;
      }
      _step = step;
    });
    _scrollToFlow();
  }

  void _scrollToFlow() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final target = _flow.currentContext;
      if (mounted && target != null) {
        Scrollable.ensureVisible(
          target,
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _generate() {
    if (_matchingColor == null) return;
    if (!_form.currentState!.validate()) {
      _optionsController.expand();
      return;
    }
    FocusScope.of(context).unfocus();
    final height = double.tryParse(_height.text.trim());
    final candidates = const StyleEngine().generateForItem(
      startingPiece: _startingPiece,
      color: _color,
      matchingColor: _matchingColor,
      occasion: _occasion,
      profile: StyleProfile(heightCm: height ?? 175),
      includeLayer: _includeLayer,
    );
    setState(() {
      _heightProvided = height != null;
      _outfits = const StyleDirectionStylist().adapt(candidates, _direction);
      _showMoreOutfits = false;
      _step = 3;
    });
    _scrollToFlow();
  }

  Future<void> _open(String destination) async {
    try {
      if (await launchUrl(Uri.parse(destination))) return;
    } catch (_) {
      // Keep the preview usable when a browser blocks the new tab.
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Could not open GitHub. Please try again.')),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: SingleChildScrollView(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1000),
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: MediaQuery.sizeOf(context).width < 600 ? 16 : 36,
                vertical: 24,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _header(),
                  const SizedBox(height: 12),
                  if (_step == 0) ...[
                    Text(
                      'Finish your outfit.',
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    const SizedBox(height: 16),
                  ],
                  Column(
                    key: _flow,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [_progress(), const SizedBox(height: 16)],
                  ),
                  Form(
                    key: _form,
                    child: switch (_step) {
                      0 => _colorPanel(),
                      1 => _matchingPanel(),
                      2 => _occasionPanel(),
                      _ => const SizedBox.shrink(),
                    },
                  ),
                  if (_step < 3) ...[const SizedBox(height: 20), _navigation()],
                  if (_step == 3 && _outfits.isNotEmpty) ...[
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Your outfit is ready.',
                          style: Theme.of(context).textTheme.headlineMedium,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '${_occasion.label} · ${_direction.label}',
                          style: const TextStyle(color: ThreadTheme.muted),
                        ),
                        const SizedBox(height: 16),
                        Wrap(
                          spacing: 12,
                          runSpacing: 8,
                          children: [
                            OutlinedButton.icon(
                              key: const Key('guest_edit_occasion'),
                              onPressed: () => _goTo(2),
                              icon: const Icon(Icons.tune_rounded),
                              label: const Text('Edit occasion'),
                            ),
                            TextButton(
                              key: const Key('guest_restart'),
                              onPressed: () => _goTo(0),
                              child: const Text('Change colors'),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final count = _showMoreOutfits ? _outfits.length : 1;
                        final columns = count > 1 && constraints.maxWidth >= 800
                            ? 3
                            : 1;
                        final width =
                            (constraints.maxWidth - (columns - 1) * 18) /
                            columns;
                        return Wrap(
                          spacing: 18,
                          runSpacing: 18,
                          children: [
                            for (var i = 0; i < count; i++)
                              SizedBox(
                                width: width,
                                child: GuestOutfitCard(
                                  outfit: _outfits[i],
                                  index: i,
                                  showHeightAdvice: _heightProvided,
                                ),
                              ),
                          ],
                        );
                      },
                    ),
                    if (_outfits.length > 1) ...[
                      const SizedBox(height: 16),
                      OutlinedButton.icon(
                        key: const Key('guest_more_outfits'),
                        onPressed: () => setState(
                          () => _showMoreOutfits = !_showMoreOutfits,
                        ),
                        icon: Icon(
                          _showMoreOutfits
                              ? Icons.expand_less
                              : Icons.expand_more,
                        ),
                        label: Text(
                          _showMoreOutfits
                              ? 'Show fewer outfits'
                              : 'Show ${_outfits.length - 1} more outfits',
                        ),
                      ),
                    ],
                  ],
                  const SizedBox(height: 28),
                  const Text(
                    'No account or saved profile. Choices reset when you reload.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: ThreadTheme.muted),
                  ),
                  const SizedBox(height: 8),
                  Center(
                    child: TextButton.icon(
                      onPressed: () => _open(
                        'https://github.com/ArunMandava3030/'
                        'Thread_Outfit_Wardrobe_stylists/releases',
                      ),
                      icon: const Icon(Icons.download_outlined),
                      label: const Text('Get the app for photos and favorites'),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );

  Widget _header() => Wrap(
    alignment: WrapAlignment.spaceBetween,
    crossAxisAlignment: WrapCrossAlignment.center,
    spacing: 16,
    runSpacing: 12,
    children: [
      const Text(
        'thread.',
        style: TextStyle(
          fontSize: 36,
          fontWeight: FontWeight.w700,
          letterSpacing: -2,
        ),
      ),
      OutlinedButton.icon(
        onPressed: () => _open(
          'https://github.com/ArunMandava3030/'
          'Thread_Outfit_Wardrobe_stylists',
        ),
        icon: const Icon(Icons.code_rounded, size: 18),
        label: const Text('View project'),
      ),
    ],
  );

  Widget _progress() => _step == 3
      ? const SizedBox.shrink()
      : Text(
          'Step ${_step + 1} of 3',
          style: const TextStyle(
            color: ThreadTheme.muted,
            fontWeight: FontWeight.w600,
          ),
        );

  Widget _navigation() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      FilledButton.icon(
        key: Key(_step == 2 ? 'guest_generate' : 'guest_continue'),
        onPressed: _step == 1 && _matchingColor == null
            ? null
            : _step == 2
            ? _generate
            : () => _goTo(_step + 1),
        icon: Icon(
          _step == 2
              ? Icons.auto_awesome_outlined
              : Icons.arrow_forward_rounded,
          size: 20,
        ),
        label: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Text(switch (_step) {
            0 =>
              'Find ${_startingPiece.matchingItemLabel.toLowerCase()} colors',
            1 => 'Choose the occasion',
            _ => 'Show my outfit',
          }, textAlign: TextAlign.center),
        ),
      ),
      if (_step > 0) ...[
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            key: const Key('guest_back'),
            onPressed: () => _goTo(_step - 1),
            icon: const Icon(Icons.arrow_back_rounded, size: 18),
            label: const Text('Back'),
          ),
        ),
      ],
    ],
  );

  Widget _colorPanel() => SurfaceCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'What are you wearing?',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final item in StartingPiece.values)
              ChoiceChip(
                key: Key('guest_start_${item.name}'),
                label: Text(item.label),
                selected: _startingPiece == item,
                onSelected: (_) {
                  if (_startingPiece != item) {
                    _changeStartingItem(() => _startingPiece = item);
                  }
                },
              ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            GarmentArt(
              kind: _startingPiece == StartingPiece.shirt
                  ? GarmentKind.shirt
                  : GarmentKind.pants,
              color: Color(_color.argb),
              size: 90,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                '${_color.name} ${_startingPiece.itemLabel.toLowerCase()}',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 2,
          runSpacing: 2,
          children: [
            for (final color in ShirtColor.presets)
              Semantics(
                button: true,
                label: color.name,
                selected: _color.argb == color.argb,
                child: Tooltip(
                  message: color.name,
                  child: InkWell(
                    key: Key('guest_color_${color.name}'),
                    onTap: () {
                      if (_color.argb != color.argb) {
                        _changeStartingItem(() => _color = color);
                      }
                    },
                    borderRadius: BorderRadius.circular(24),
                    child: SizedBox.square(
                      dimension: 44,
                      child: Center(
                        child: Container(
                          width: 30,
                          height: 30,
                          decoration: BoxDecoration(
                            color: Color(color.argb),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: _color.argb == color.argb
                                  ? ThreadTheme.green
                                  : ThreadTheme.line,
                              width: _color.argb == color.argb ? 2 : 1,
                            ),
                          ),
                          child: _color.argb == color.argb
                              ? Icon(
                                  Icons.check,
                                  size: 18,
                                  color:
                                      Color(color.argb).computeLuminance() < .35
                                      ? Colors.white
                                      : ThreadTheme.ink,
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
      ],
    ),
  );

  Widget _matchingPanel() {
    final suggestions = const StyleEngine().matchingColors(
      startingPiece: _startingPiece,
      color: _color,
    );
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Choose your ${_startingPiece.matchingItemLabel.toLowerCase()} color',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          const Text('We’ve picked a match. Keep it or try another.'),
          const SizedBox(height: 20),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 16,
            runSpacing: 12,
            children: [
              _garmentPreview(
                color: _color,
                kind: _startingPiece == StartingPiece.shirt
                    ? GarmentKind.shirt
                    : GarmentKind.pants,
                label: 'Your ${_startingPiece.itemLabel.toLowerCase()}',
              ),
              if (_matchingColor != null)
                _garmentPreview(
                  color: _matchingColor!,
                  kind: _startingPiece == StartingPiece.shirt
                      ? GarmentKind.pants
                      : GarmentKind.shirt,
                  label:
                      'Matching ${_startingPiece.matchingItemLabel.toLowerCase()}',
                ),
            ],
          ),
          const SizedBox(height: 20),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final color in suggestions.take(3))
                ChoiceChip(
                  key: Key('guest_match_${color.name}'),
                  avatar: CircleAvatar(backgroundColor: Color(color.argb)),
                  label: Text(color.name),
                  selected: _matchingColor?.argb == color.argb,
                  showCheckmark: false,
                  onSelected: (_) => _change(() => _matchingColor = color),
                ),
            ],
          ),
          ExpansionTile(
            key: const Key('guest_more_colors'),
            tilePadding: EdgeInsets.zero,
            title: const Text('More colors'),
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final color in ShirtColor.presets)
                      ChoiceChip(
                        key: Key('guest_custom_match_${color.name}'),
                        avatar: CircleAvatar(
                          backgroundColor: Color(color.argb),
                        ),
                        label: Text(color.name),
                        selected: _matchingColor?.argb == color.argb,
                        showCheckmark: false,
                        onSelected: (_) =>
                            _change(() => _matchingColor = color),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _garmentPreview({
    required ShirtColor color,
    required GarmentKind kind,
    required String label,
  }) => SizedBox(
    width: 100,
    child: Column(
      children: [
        GarmentArt(kind: kind, color: Color(color.argb), size: 80),
        Text(label, textAlign: TextAlign.center),
        Text(
          color.name,
          textAlign: TextAlign.center,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ],
    ),
  );

  Widget _occasionPanel() => SurfaceCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Where are you headed?',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 16),
        Text(
          '${_color.name} ${_startingPiece.itemLabel.toLowerCase()} + '
          '${_matchingColor!.name} '
          '${_startingPiece.matchingItemLabel.toLowerCase()}',
          style: const TextStyle(color: ThreadTheme.muted),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 7,
          runSpacing: 7,
          children: [
            for (final occasion in Occasion.values)
              ChoiceChip(
                key: Key('guest_occasion_${occasion.name}'),
                label: Text(occasion.label),
                selected: occasion == _occasion,
                onSelected: (_) => _change(() => _occasion = occasion),
              ),
          ],
        ),
        const SizedBox(height: 12),
        SwitchListTile.adaptive(
          key: const Key('guest_layers'),
          contentPadding: EdgeInsets.zero,
          title: const Text('Include a layer'),
          value: _includeLayer,
          onChanged: (value) => _change(() => _includeLayer = value),
        ),
        if (_includeLayer &&
            [
              Occasion.date,
              Occasion.party,
              Occasion.special,
            ].contains(_occasion))
          const Text(
            'Follow any dress code on your invitation.',
            style: TextStyle(color: ThreadTheme.muted),
          ),
        if (_occasion == Occasion.bikeRide)
          const Text(
            'Protective motorcycle gear stays included with optional layers off.',
            style: TextStyle(color: ThreadTheme.muted),
          ),
        const SizedBox(height: 8),
        ExpansionTile(
          key: const Key('guest_options'),
          controller: _optionsController,
          maintainState: true,
          tilePadding: EdgeInsets.zero,
          title: const Text('Style and fit (optional)'),
          children: [
            const SizedBox(height: 8),
            DropdownButtonFormField<StyleDirection>(
              key: ValueKey(_direction),
              initialValue: _direction,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Style mood'),
              items: [
                for (final direction in StyleDirection.values)
                  DropdownMenuItem(
                    value: direction,
                    child: Text(
                      direction.label,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: (direction) {
                if (direction != null) _change(() => _direction = direction);
              },
            ),
            const SizedBox(height: 20),
            TextFormField(
              key: const Key('guest_height'),
              controller: _height,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              maxLength: 5,
              decoration: const InputDecoration(
                labelText: 'Height (optional)',
                suffixText: 'cm',
                hintText: 'e.g. 175',
                helperText: 'For fit tips in this session.',
                helperMaxLines: 2,
                errorMaxLines: 3,
                counterText: '',
              ),
              onChanged: (_) => _change(() {}),
              validator: (value) {
                if (value == null || value.trim().isEmpty) return null;
                final parsed = double.tryParse(value.trim());
                return parsed == null ||
                        !parsed.isFinite ||
                        parsed < 100 ||
                        parsed > 250
                    ? 'Enter a height between 100 and 250 cm, or leave it blank.'
                    : null;
              },
            ),
            const SizedBox(height: 20),
            TrendPanel(
              onSelected: (direction) => _change(() => _direction = direction),
            ),
          ],
        ),
      ],
    ),
  );
}

class GuestOutfitCard extends StatelessWidget {
  const GuestOutfitCard({
    super.key,
    required this.outfit,
    required this.index,
    this.showHeightAdvice = false,
  });

  final OutfitRecommendation outfit;
  final int index;
  final bool showHeightAdvice;

  @override
  Widget build(BuildContext context) => SurfaceCard(
    padding: const EdgeInsets.all(20),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (index > 0) Eyebrow('Another option · ${index + 1}'),
        OutfitArt(
          shirt: Color(outfit.shirt.argb),
          pants: Color(outfit.pants.colorArgb),
          shoes: Color(outfit.shoes.colorArgb),
          layer: Color(outfit.layer.colorArgb),
          height: 175,
        ),
        Text(outfit.title, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 20),
        for (final piece in [
          OutfitPiece(
            category: 'Top',
            title: outfit.shirtTitle,
            colorName: outfit.shirt.name,
            colorArgb: outfit.shirt.argb,
          ),
          outfit.pants,
          outfit.shoes,
          outfit.layer,
        ]) ...[_piece(piece), const SizedBox(height: 14)],
        Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            tilePadding: EdgeInsets.zero,
            childrenPadding: const EdgeInsets.only(bottom: 8),
            title: const Text('Why it works'),
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Text(outfit.description),
                ),
              ),
              for (final reason in outfit.reasons)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(reason),
                  ),
                ),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  showHeightAdvice || outfit.occasion == Occasion.bikeRide
                      ? outfit.fitAdvice.replaceAll(
                          ' Add your preferred proportions in your profile for more specific tips.',
                          '',
                        )
                      : 'Choose a comfortable fit at the shoulders and leave room to move.',
                ),
              ),
            ],
          ),
        ),
        if (outfit.safetyNote != null) ...[
          const SizedBox(height: 8),
          Text(
            outfit.safetyNote!,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ],
    ),
  );

  Widget _piece(OutfitPiece piece) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Container(
        margin: const EdgeInsets.only(top: 4),
        width: 22,
        height: 22,
        decoration: BoxDecoration(
          color: piece.colorArgb == 0
              ? ThreadTheme.canvas
              : Color(piece.colorArgb),
          borderRadius: BorderRadius.circular(7),
          border: Border.all(color: ThreadTheme.line),
        ),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${piece.category} · ${piece.colorName}',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            Text(piece.title),
          ],
        ),
      ),
    ],
  );
}
