import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/style_models.dart';
import '../models/wardrobe_models.dart';
import '../theme.dart';
import '../widgets/garment_art.dart';

class WardrobeScreen extends StatefulWidget {
  const WardrobeScreen({
    super.key,
    required this.items,
    required this.onSave,
    required this.onRemove,
    required this.onWear,
  });

  final List<WardrobeItem> items;
  final ValueChanged<WardrobeItem> onSave;
  final ValueChanged<String> onRemove;
  final ValueChanged<WardrobeItem> onWear;

  @override
  State<WardrobeScreen> createState() => _WardrobeScreenState();
}

class _WardrobeScreenState extends State<WardrobeScreen> {
  WardrobeCategory? _filter;

  Future<void> _edit([WardrobeItem? item]) async {
    final result = await showWardrobeItemDialog(
      context,
      existing: item,
      existingIds: widget.items.map((item) => item.id).toSet(),
    );
    if (result != null && mounted) widget.onSave(result);
  }

  @override
  Widget build(BuildContext context) {
    final filtered = widget.items
        .where((item) => _filter == null || item.category == _filter)
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Eyebrow('Make more of what you own'),
        const SizedBox(height: 12),
        Text(
          'Your wardrobe, in color.',
          style: Theme.of(context).textTheme.displayMedium,
        ),
        const SizedBox(height: 12),
        const Text(
          'Add your everyday pieces. Wear a shirt to start a look, or use your wardrobe colors to sort outfit ideas.',
        ),
        const SizedBox(height: 20),
        FilledButton.icon(
          key: const Key('add_wardrobe_item'),
          onPressed: _edit,
          icon: const Icon(Icons.add_rounded),
          label: const Text('Add an item'),
        ),
        const SizedBox(height: 20),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ChoiceChip(
              label: Text('All (${widget.items.length})'),
              selected: _filter == null,
              onSelected: (_) => setState(() => _filter = null),
            ),
            for (final category in WardrobeCategory.values)
              ChoiceChip(
                label: Text(category.label),
                selected: _filter == category,
                onSelected: (_) => setState(() => _filter = category),
              ),
          ],
        ),
        const SizedBox(height: 22),
        if (filtered.isEmpty)
          SurfaceCard(
            color: ThreadTheme.softGreen,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.checkroom_rounded, size: 32),
                const SizedBox(height: 16),
                Text(
                  widget.items.isEmpty
                      ? 'Start with your favorite shirt.'
                      : 'Room for another favorite.',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 10),
                Text(
                  widget.items.isEmpty
                      ? 'Give it a name and a color. Your wardrobe stays on this device.'
                      : 'There are no ${_filter?.label.toLowerCase() ?? 'items'} here yet. Add one when you’re ready.',
                ),
              ],
            ),
          )
        else
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 900
                  ? 3
                  : constraints.maxWidth >= 560
                  ? 2
                  : 1;
              final width =
                  (constraints.maxWidth - 16 * (columns - 1)) / columns;
              return Wrap(
                spacing: 16,
                runSpacing: 16,
                children: [
                  for (final item in filtered)
                    SizedBox(
                      width: width,
                      child: _WardrobeCard(
                        item: item,
                        onEdit: () => _edit(item),
                        onRemove: () => widget.onRemove(item.id),
                        onWear: () => widget.onWear(item),
                      ),
                    ),
                ],
              );
            },
          ),
        const SizedBox(height: 18),
        const Text(
          'Wardrobe matches compare colors and clothing categories. Check the actual garment, fit and occasion before you wear it.',
          style: TextStyle(color: ThreadTheme.muted, fontSize: 12),
        ),
      ],
    );
  }
}

class _WardrobeCard extends StatelessWidget {
  const _WardrobeCard({
    required this.item,
    required this.onEdit,
    required this.onRemove,
    required this.onWear,
  });
  final WardrobeItem item;
  final VoidCallback onEdit, onRemove, onWear;

  @override
  Widget build(BuildContext context) => SurfaceCard(
    padding: const EdgeInsets.all(20),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Eyebrow(item.category.label)),
            IconButton(
              tooltip: 'Edit item',
              onPressed: onEdit,
              icon: const Icon(Icons.edit_outlined, size: 20),
            ),
            IconButton(
              tooltip: 'Remove item',
              onPressed: onRemove,
              icon: const Icon(Icons.delete_outline_rounded, size: 20),
            ),
          ],
        ),
        Center(
          child: GarmentArt(
            kind: switch (item.category) {
              WardrobeCategory.shirt => GarmentKind.shirt,
              WardrobeCategory.pants => GarmentKind.pants,
              WardrobeCategory.shoes => GarmentKind.shoes,
              WardrobeCategory.layer => GarmentKind.jacket,
            },
            color: Color(item.colorArgb),
            size: 130,
          ),
        ),
        const SizedBox(height: 12),
        Text(item.name, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        Text(
          '${item.colorName} · ${item.hex}',
          style: const TextStyle(color: ThreadTheme.muted),
        ),
        if (item.category == WardrobeCategory.shirt) ...[
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: onWear,
            icon: const Icon(Icons.checkroom_outlined, size: 18),
            label: const Text('Wear this shirt'),
          ),
        ],
      ],
    ),
  );
}

Future<WardrobeItem?> showWardrobeItemDialog(
  BuildContext context, {
  WardrobeItem? existing,
  Set<String> existingIds = const {},
}) => showDialog<WardrobeItem>(
  context: context,
  builder: (context) =>
      _WardrobeItemDialog(existing: existing, existingIds: existingIds),
);

class _WardrobeItemDialog extends StatefulWidget {
  const _WardrobeItemDialog({this.existing, required this.existingIds});
  final WardrobeItem? existing;
  final Set<String> existingIds;
  @override
  State<_WardrobeItemDialog> createState() => _WardrobeItemDialogState();
}

class _WardrobeItemDialogState extends State<_WardrobeItemDialog> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _hex;
  late WardrobeCategory _category;
  late String _colorName;
  late int _colorArgb;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _name = TextEditingController(text: existing?.name ?? '');
    _category = existing?.category ?? WardrobeCategory.shirt;
    _colorName = existing?.colorName ?? ShirtColor.presets.first.name;
    _colorArgb = existing?.colorArgb ?? ShirtColor.presets.first.argb;
    _hex = TextEditingController(text: _hexFor(_colorArgb));
  }

  @override
  void dispose() {
    _name.dispose();
    _hex.dispose();
    super.dispose();
  }

  int? _parseColor(String value) {
    final raw = value.trim().replaceFirst(RegExp(r'^#'), '');
    if (!RegExp(r'^[a-fA-F0-9]{6}$').hasMatch(raw)) return null;
    return 0xFF000000 | int.parse(raw, radix: 16);
  }

  void _save() {
    if (!_form.currentState!.validate()) return;
    final color = _parseColor(_hex.text)!;
    final prefix = 'wardrobe-${DateTime.now().microsecondsSinceEpoch}';
    var id = widget.existing?.id ?? prefix;
    var suffix = 1;
    if (widget.existing == null) {
      while (widget.existingIds.contains(id)) {
        id = '$prefix-${suffix++}';
      }
    }
    Navigator.pop(
      context,
      WardrobeItem(
        id: id,
        name: _name.text.trim(),
        colorName: color == _colorArgb ? _colorName : 'Custom',
        colorArgb: color,
        category: _category,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    scrollable: true,
    insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
    title: Text(
      widget.existing == null ? 'Add to your wardrobe' : 'Edit wardrobe item',
    ),
    content: SizedBox(
      width: 420,
      child: Form(
        key: _form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextFormField(
              key: const Key('wardrobe_name'),
              controller: _name,
              maxLength: 60,
              inputFormatters: [
                TextInputFormatter.withFunction(
                  (oldValue, newValue) =>
                      newValue.text.runes.length <= 60 ? newValue : oldValue,
                ),
              ],
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Item name',
                hintText: 'My favorite linen shirt',
              ),
              validator: (value) => value == null || value.trim().isEmpty
                  ? 'Give this item a name.'
                  : value.runes.length > 60
                  ? 'Use 60 characters or fewer.'
                  : null,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<WardrobeCategory>(
              key: const Key('wardrobe_category'),
              initialValue: _category,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Category'),
              items: [
                for (final category in WardrobeCategory.values)
                  DropdownMenuItem(
                    value: category,
                    child: Text(category.label),
                  ),
              ],
              onChanged: (value) {
                if (value != null) setState(() => _category = value);
              },
            ),
            const SizedBox(height: 22),
            const Eyebrow('Pick its closest color'),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final color in ShirtColor.presets)
                  Semantics(
                    label: color.name,
                    selected: _parseColor(_hex.text) == color.argb,
                    button: true,
                    child: Tooltip(
                      message: color.name,
                      child: InkWell(
                        onTap: () => setState(() {
                          _colorArgb = color.argb;
                          _colorName = color.name;
                          _hex.text = _hexFor(color.argb);
                        }),
                        borderRadius: BorderRadius.circular(24),
                        child: Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: Color(color.argb),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: _parseColor(_hex.text) == color.argb
                                  ? ThreadTheme.ink
                                  : ThreadTheme.line,
                              width: 2,
                            ),
                          ),
                          child: _parseColor(_hex.text) == color.argb
                              ? Icon(
                                  Icons.check_rounded,
                                  color:
                                      Color(color.argb).computeLuminance() > .4
                                      ? ThreadTheme.ink
                                      : Colors.white,
                                  size: 20,
                                )
                              : null,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            TextFormField(
              key: const Key('wardrobe_hex'),
              controller: _hex,
              maxLength: 7,
              decoration: const InputDecoration(
                labelText: 'Or enter a color hex',
                hintText: '#9BAE98',
              ),
              onChanged: (_) => setState(() {}),
              validator: (value) => _parseColor(value ?? '') == null
                  ? 'Use 6 hex digits, like #9BAE98.'
                  : null,
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        key: const Key('save_wardrobe_item'),
        onPressed: _save,
        child: const Text('Save item'),
      ),
    ],
  );

  String _hexFor(int color) =>
      '#${(color & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';
}
