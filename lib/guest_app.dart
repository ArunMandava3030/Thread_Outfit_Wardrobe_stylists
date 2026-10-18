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
  final _results = GlobalKey();
  final _height = TextEditingController();
  ShirtColor _shirt = ShirtColor.presets.first;
  Occasion _occasion = Occasion.casual;
  StyleDirection _direction = StyleDirection.everyday;
  bool _includeLayer = true;
  List<OutfitRecommendation> _outfits = const [];
  bool _heightProvided = false;

  @override
  void dispose() {
    _height.dispose();
    super.dispose();
  }

  void _change(VoidCallback update) => setState(() {
    update();
    _outfits = const [];
  });

  void _generate() {
    if (!_form.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    final height = double.tryParse(_height.text.trim());
    final candidates = const StyleEngine().generate(
      shirt: _shirt,
      occasion: _occasion,
      profile: StyleProfile(heightCm: height ?? 175),
      includeLayer: _includeLayer,
    );
    setState(() {
      _heightProvided = height != null;
      _outfits = const StyleDirectionStylist().adapt(candidates, _direction);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final target = _results.currentContext;
      if (mounted && target != null) {
        Scrollable.ensureVisible(
          target,
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeOut,
        );
      }
    });
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
            constraints: const BoxConstraints(maxWidth: 1200),
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: MediaQuery.sizeOf(context).width < 600 ? 16 : 36,
                vertical: 24,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _header(),
                  const SizedBox(height: 40),
                  const Eyebrow('Your shirt. A fresh perspective.'),
                  const SizedBox(height: 14),
                  Text(
                    'Good outfits\nstart with one color.',
                    style: MediaQuery.sizeOf(context).width < 600
                        ? Theme.of(context).textTheme.displayMedium
                        : Theme.of(context).textTheme.displayLarge,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Pick the shirt you’re wearing. Discover pants, shoes and '
                    'layers that work together, wherever you’re headed.',
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Try Thread · No account or saved profile.\n'
                    'Your choices reset when you reload.',
                    style: TextStyle(color: ThreadTheme.muted, height: 1.6),
                  ),
                  const SizedBox(height: 28),
                  Form(
                    key: _form,
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        if (constraints.maxWidth < 760) {
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _colorPanel(),
                              const SizedBox(height: 16),
                              _occasionPanel(),
                            ],
                          );
                        }
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: _colorPanel()),
                            const SizedBox(width: 20),
                            Expanded(child: _occasionPanel()),
                          ],
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    key: const Key('guest_generate'),
                    onPressed: _generate,
                    icon: const Icon(Icons.auto_awesome_outlined, size: 20),
                    label: const Padding(
                      padding: EdgeInsets.symmetric(vertical: 14),
                      child: Text('Find my outfits'),
                    ),
                  ),
                  const SizedBox(height: 28),
                  if (_outfits.isNotEmpty) ...[
                    Column(
                      key: _results,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Eyebrow('Made for your plans'),
                        const SizedBox(height: 8),
                        Text(
                          'Three ways to wear ${_shirt.name.toLowerCase()}.',
                          style: Theme.of(context).textTheme.headlineMedium,
                        ),
                        const SizedBox(height: 8),
                        Text('${_occasion.label} · ${_direction.label}'),
                      ],
                    ),
                    const SizedBox(height: 20),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final columns = constraints.maxWidth >= 1000
                            ? 3
                            : constraints.maxWidth >= 640
                            ? 2
                            : 1;
                        final width =
                            (constraints.maxWidth - (columns - 1) * 18) /
                            columns;
                        return Wrap(
                          spacing: 18,
                          runSpacing: 18,
                          children: [
                            for (var i = 0; i < _outfits.length; i++)
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
                    const SizedBox(height: 28),
                  ],
                  TrendPanel(
                    onSelected: (direction) {
                      _change(() => _direction = direction);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            '${direction.label} selected. Tap Find my outfits to try it.',
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 32),
                  SurfaceCard(
                    color: ThreadTheme.softGreen,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Take your wardrobe with you.',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'The full app adds photo analysis, a wardrobe, outfit '
                          'planning and style preferences. Visit releases for '
                          'available downloads and iPhone installation details.',
                        ),
                        const SizedBox(height: 16),
                        OutlinedButton.icon(
                          onPressed: () => _open(
                            'https://github.com/ArunMandava3030/'
                            'Thread_Outfit_Wardrobe_stylists/releases',
                          ),
                          icon: const Icon(Icons.download_outlined),
                          label: const Text('App releases'),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'A little color. A little confidence. Thread.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: ThreadTheme.muted),
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

  Widget _colorPanel() => SurfaceCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Eyebrow('01 / Start with your shirt'),
        const SizedBox(height: 12),
        Text('Choose a color', style: Theme.of(context).textTheme.titleLarge),
        Center(
          child: GarmentArt(
            kind: GarmentKind.shirt,
            color: Color(_shirt.argb),
            size: 160,
          ),
        ),
        Text(
          '${_shirt.name} · ${_shirt.hex}',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 20),
        Wrap(
          spacing: 7,
          runSpacing: 7,
          children: [
            for (final color in ShirtColor.presets)
              ChoiceChip(
                key: Key('guest_color_${color.name}'),
                avatar: Container(
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    color: Color(color.argb),
                    shape: BoxShape.circle,
                    border: Border.all(color: ThreadTheme.line),
                  ),
                ),
                label: Text(color.name),
                selected: _shirt.argb == color.argb,
                showCheckmark: false,
                onSelected: (_) => _change(() => _shirt = color),
              ),
          ],
        ),
      ],
    ),
  );

  Widget _occasionPanel() => SurfaceCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Eyebrow('02 / Make it yours'),
        const SizedBox(height: 12),
        Text(
          'Where are you headed?',
          style: Theme.of(context).textTheme.titleLarge,
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
        const SizedBox(height: 24),
        DropdownButtonFormField<StyleDirection>(
          key: ValueKey(_direction),
          initialValue: _direction,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Style mood'),
          items: [
            for (final direction in StyleDirection.values)
              DropdownMenuItem(
                value: direction,
                child: Text(direction.label, overflow: TextOverflow.ellipsis),
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
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
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
        const SizedBox(height: 12),
        SwitchListTile.adaptive(
          key: const Key('guest_layers'),
          contentPadding: EdgeInsets.zero,
          title: const Text('Include a layer'),
          value: _includeLayer,
          onChanged: (value) => _change(() => _includeLayer = value),
        ),
        if (_occasion == Occasion.bikeRide)
          const Text(
            'Protective motorcycle gear stays included with optional layers off.',
            style: TextStyle(color: ThreadTheme.muted),
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
        Eyebrow('Look 0${index + 1}'),
        OutfitArt(
          shirt: Color(outfit.shirt.argb),
          pants: Color(outfit.pants.colorArgb),
          shoes: Color(outfit.shoes.colorArgb),
          layer: Color(outfit.layer.colorArgb),
          height: 215,
        ),
        Text(outfit.title, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        Text(outfit.description),
        const SizedBox(height: 20),
        for (final piece in [outfit.pants, outfit.shoes, outfit.layer]) ...[
          _piece(piece),
          const SizedBox(height: 14),
        ],
        Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            tilePadding: EdgeInsets.zero,
            childrenPadding: const EdgeInsets.only(bottom: 8),
            title: const Text('Why it works'),
            children: [
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
