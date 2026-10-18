import 'package:flutter/material.dart';
import '../models/style_models.dart';
import '../services/photo_analyzer.dart';
import '../theme.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({
    super.key,
    required this.profile,
    required this.onSave,
    required this.onAnalyze,
    required this.onClear,
  });
  final StyleProfile profile;
  final Future<void> Function(StyleProfile) onSave;
  final Future<PhotoAnalysisResult?> Function({
    bool sampleSkin,
    bool measureBody,
  })
  onAnalyze;
  final Future<void> Function() onClear;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _height;
  late StyleProfile _draft;
  bool _saving = false;
  bool _feet = false;
  bool _analyzing = false;

  @override
  void initState() {
    super.initState();
    _draft = widget.profile;
    _height = TextEditingController(text: _draft.heightCm.round().toString());
  }

  @override
  void dispose() {
    _height.dispose();
    super.dispose();
  }

  Future<void> _analyze({bool skin = false}) async {
    setState(() => _analyzing = true);
    try {
      final result = await widget.onAnalyze(
        sampleSkin: skin,
        measureBody: !skin,
      );
      if (result == null || !mounted) return;
      setState(() {
        if (skin && result.skinToneArgb != null) {
          _draft = _draft.copyWith(
            skinToneArgb: result.skinToneArgb,
            useSkinTone: true,
          );
        } else if (result.bodyShape != null) {
          _draft = _draft.copyWith(bodyShape: result.bodyShape);
        }
      });
    } finally {
      if (mounted) setState(() => _analyzing = false);
    }
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final entered = double.parse(_height.text.trim());
      await widget.onSave(
        _draft.copyWith(heightCm: _feet ? entered * 2.54 : entered),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Form(
    key: _form,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Eyebrow('A little about you'),
        const SizedBox(height: 12),
        Text(
          'Style that feels like you.',
          style: Theme.of(context).textTheme.displayMedium,
        ),
        const SizedBox(height: 12),
        const Text(
          'A few details help us suggest colors and proportions.\nEvery suggestion is a starting point. Your taste comes first.',
        ),
        const SizedBox(height: 30),
        SurfaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Eyebrow('01 / Your height'),
              const SizedBox(height: 10),
              Text(
                'Find your proportions',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              const Text(
                'Height helps with trouser length, layering, and visual balance.',
              ),
              const SizedBox(height: 20),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: double.infinity,
                    child: TextFormField(
                      key: const Key('height_input'),
                      controller: _height,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(
                        labelText: 'Your height',
                        suffixText: _feet ? 'inches' : 'cm',
                      ),
                      validator: (value) {
                        final entered = double.tryParse(value?.trim() ?? '');
                        final cm = entered == null
                            ? null
                            : (_feet ? entered * 2.54 : entered);
                        return cm == null ||
                                !cm.isFinite ||
                                cm < 100 ||
                                cm > 250
                            ? 'Enter ${_feet ? '40–98 inches' : '100–250 cm'}.'
                            : null;
                      },
                    ),
                  ),
                  const SizedBox(height: 12),
                  SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(value: false, label: Text('cm')),
                      ButtonSegment(value: true, label: Text('in')),
                    ],
                    selected: {_feet},
                    showSelectedIcon: false,
                    onSelectionChanged: (selection) {
                      final entered = double.tryParse(_height.text.trim());
                      setState(() {
                        if (entered != null && entered.isFinite) {
                          _height.text =
                              (selection.first
                                      ? entered / 2.54
                                      : entered * 2.54)
                                  .toStringAsFixed(1);
                        }
                        _feet = selection.first;
                      });
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        SurfaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Eyebrow('02 / Your silhouette · optional'),
              const SizedBox(height: 10),
              Text(
                'Good fit. Your way.',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              const Text(
                'Choose the closest description, or use a front-facing photo for an automatic shoulder-to-hip guide. Guided points also let you include waist width.',
              ),
              const SizedBox(height: 18),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ChoiceChip(
                    label: const Text('Not sure'),
                    selected: _draft.bodyShape == null,
                    onSelected: (_) => setState(
                      () => _draft = _draft.copyWith(bodyShape: null),
                    ),
                  ),
                  ...BodyShape.values.map(
                    (shape) => ChoiceChip(
                      label: Text(shape.label),
                      selected: _draft.bodyShape == shape,
                      onSelected: (_) => setState(
                        () => _draft = _draft.copyWith(bodyShape: shape),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: _analyzing ? null : () => _analyze(),
                icon: const Icon(Icons.accessibility_new_rounded, size: 18),
                label: const Text('Estimate from a photo'),
              ),
              const SizedBox(height: 8),
              const Text(
                'A rough fit guide, not a body measurement. Pose, perspective, and loose clothing affect the estimate.',
                style: TextStyle(color: ThreadTheme.muted, fontSize: 12),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        SurfaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Eyebrow('03 / Your palette · optional'),
              const SizedBox(height: 8),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  'Personalize with skin tone',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                subtitle: const Text(
                  'Use a sampled tone for optional color accents.',
                ),
                value: _draft.useSkinTone,
                onChanged: (enabled) => setState(
                  () => _draft = _draft.copyWith(useSkinTone: enabled),
                ),
              ),
              if (_draft.useSkinTone) ...[
                const SizedBox(height: 12),
                const Text(
                  'Choose a close swatch or sample your skin in natural light. You can wear every color; this only helps us vary contrast.',
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (final tone in [
                      0xFFF1D5BE,
                      0xFFE2BA96,
                      0xFFC99B74,
                      0xFFAC7955,
                      0xFF895B3D,
                      0xFF69432E,
                      0xFF452D23,
                    ])
                      Semantics(
                        label:
                            'Skin tone #${tone.toRadixString(16).substring(2)}',
                        selected: _draft.skinToneArgb == tone,
                        button: true,
                        child: InkWell(
                          onTap: () => setState(
                            () => _draft = _draft.copyWith(skinToneArgb: tone),
                          ),
                          borderRadius: BorderRadius.circular(30),
                          child: Container(
                            width: 46,
                            height: 46,
                            decoration: BoxDecoration(
                              color: Color(tone),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: _draft.skinToneArgb == tone
                                    ? ThreadTheme.ink
                                    : Colors.white,
                                width: 3,
                              ),
                            ),
                            child: _draft.skinToneArgb == tone
                                ? Icon(
                                    Icons.check,
                                    color: Color(tone).computeLuminance() > .4
                                        ? ThreadTheme.ink
                                        : Colors.white,
                                    size: 20,
                                  )
                                : null,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    if (_draft.skinToneArgb != null) ...[
                      CircleAvatar(
                        radius: 14,
                        backgroundColor: Color(_draft.skinToneArgb!),
                      ),
                      const SizedBox(width: 10),
                    ],
                    Flexible(
                      child: OutlinedButton.icon(
                        onPressed: _analyzing
                            ? null
                            : () => _analyze(skin: true),
                        icon: const Icon(Icons.colorize_rounded, size: 18),
                        label: const Text('Sample from a photo'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                DropdownButtonFormField<Undertone>(
                  initialValue: _draft.undertone,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Undertone (if you know it)',
                  ),
                  items: Undertone.values
                      .map(
                        (tone) => DropdownMenuItem(
                          value: tone,
                          child: Text(
                            tone.label,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (tone) {
                    if (tone != null) {
                      setState(() => _draft = _draft.copyWith(undertone: tone));
                    }
                  },
                ),
                const SizedBox(height: 10),
                const Text(
                  'We do not infer undertone from a photo. Lighting and camera processing make that unreliable.',
                  style: TextStyle(color: ThreadTheme.muted, fontSize: 12),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            key: const Key('save_profile'),
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox.square(
                    dimension: 17,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.check_rounded, size: 18),
            label: const Text('Save my style profile'),
          ),
        ),
        const SizedBox(height: 22),
        const Row(
          children: [
            Icon(
              Icons.lock_outline_rounded,
              size: 16,
              color: ThreadTheme.muted,
            ),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Photos are processed on this device and are not saved by Thread.',
                style: TextStyle(fontSize: 12, color: ThreadTheme.muted),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: _saving
              ? null
              : () async {
                  final confirmed = await showDialog<bool>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('Clear your saved data?'),
                      content: const Text(
                        'This removes your profile, saved looks, likes and dislikes, wardrobe, outfit plans, saved city, and style direction from this device.',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: const Text('Keep it'),
                        ),
                        FilledButton(
                          onPressed: () => Navigator.pop(context, true),
                          child: const Text('Clear data'),
                        ),
                      ],
                    ),
                  );
                  if (confirmed == true) await widget.onClear();
                },
          child: const Text('Clear all my Thread data'),
        ),
      ],
    ),
  );
}
