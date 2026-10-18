import 'package:flutter/material.dart';

import '../models/planner_models.dart';
import '../models/style_models.dart';
import '../theme.dart';
import '../widgets/garment_art.dart';

class PlannerScreen extends StatelessWidget {
  const PlannerScreen({
    super.key,
    required this.plans,
    required this.onRemove,
    required this.onEdit,
    required this.onBrowse,
  });

  final List<PlannedOutfit> plans;
  final ValueChanged<String> onRemove;
  final ValueChanged<PlannedOutfit> onEdit;
  final VoidCallback onBrowse;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final upcoming = plans.where((plan) => !plan.date.isBefore(today)).toList()
      ..sort((a, b) => a.date.compareTo(b.date));
    final past = plans.where((plan) => plan.date.isBefore(today)).toList()
      ..sort((a, b) => b.date.compareTo(a.date));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Eyebrow('One less thing to think about'),
        const SizedBox(height: 12),
        Text(
          'Good plans. Great outfits.',
          style: Theme.of(context).textTheme.displayMedium,
        ),
        const SizedBox(height: 12),
        const Text(
          'Set aside a look for your next office day, date or getaway. '
          'Add a note to remember the details.',
        ),
        const SizedBox(height: 20),
        OutlinedButton.icon(
          onPressed: onBrowse,
          icon: const Icon(Icons.add_rounded, size: 18),
          label: const Text('Find an outfit to plan'),
        ),
        const SizedBox(height: 24),
        if (plans.isEmpty)
          SurfaceCard(
            color: ThreadTheme.softGreen,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.event_available_outlined, size: 32),
                const SizedBox(height: 16),
                Text(
                  'Your calendar is a blank canvas.',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 10),
                const Text(
                  'Create a look in the studio, then tap Plan look to '
                  'choose a day. Your plans stay on this device.',
                ),
              ],
            ),
          ),
        if (upcoming.isNotEmpty) ...[
          Text('Coming up', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 14),
          for (final plan in upcoming) _card(plan),
        ],
        if (past.isNotEmpty) ...[
          if (upcoming.isNotEmpty) const SizedBox(height: 14),
          Text('Past plans', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          const Text('A little inspiration for what to wear again.'),
          const SizedBox(height: 14),
          for (final plan in past) _card(plan),
        ],
      ],
    );
  }

  Widget _card(PlannedOutfit plan) => Padding(
    key: ValueKey('plan_${plan.id}'),
    padding: const EdgeInsets.only(bottom: 14),
    child: _PlanCard(
      plan: plan,
      onRemove: () => onRemove(plan.id),
      onEdit: () => onEdit(plan),
    ),
  );
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({
    required this.plan,
    required this.onRemove,
    required this.onEdit,
  });

  final PlannedOutfit plan;
  final VoidCallback onRemove;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final outfit = plan.outfit;
    final art = SizedBox(
      width: 180,
      child: OutfitArt(
        shirt: Color(outfit.shirt.argb),
        pants: Color(outfit.pants.colorArgb),
        shoes: Color(outfit.shoes.colorArgb),
        layer: Color(outfit.layer.colorArgb),
        height: 145,
      ),
    );
    final details = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          MaterialLocalizations.of(context).formatFullDate(plan.date),
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 5),
        Eyebrow(outfit.occasion.label),
        const SizedBox(height: 10),
        Text(outfit.title, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        Text('${outfit.shirt.name} shirt'),
        Text('${outfit.pants.colorName} ${outfit.pants.title}'),
        Text('${outfit.shoes.colorName} ${outfit.shoes.title}'),
        if (outfit.layer.colorArgb != 0)
          Text('${outfit.layer.colorName} ${outfit.layer.title}'),
        if (plan.note.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(plan.note, style: const TextStyle(color: ThreadTheme.muted)),
        ],
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            OutlinedButton.icon(
              onPressed: onEdit,
              icon: const Icon(Icons.edit_calendar_outlined, size: 18),
              label: const Text('Edit plan'),
            ),
            IconButton(
              tooltip: 'Remove plan',
              onPressed: onRemove,
              icon: const Icon(Icons.delete_outline_rounded),
            ),
          ],
        ),
      ],
    );
    return SurfaceCard(
      padding: const EdgeInsets.all(20),
      child: LayoutBuilder(
        builder: (context, constraints) => constraints.maxWidth >= 520
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  art,
                  const SizedBox(width: 24),
                  Expanded(child: details),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(child: art),
                  const SizedBox(height: 12),
                  details,
                ],
              ),
      ),
    );
  }
}

Future<PlannedOutfit?> showPlanOutfitDialog(
  BuildContext context, {
  required OutfitRecommendation outfit,
  PlannedOutfit? existing,
  DateTime? now,
}) => showDialog<PlannedOutfit>(
  context: context,
  builder: (context) => _PlanOutfitDialog(
    outfit: outfit,
    existing: existing,
    now: now ?? DateTime.now(),
  ),
);

class _PlanOutfitDialog extends StatefulWidget {
  const _PlanOutfitDialog({
    required this.outfit,
    required this.now,
    this.existing,
  });

  final OutfitRecommendation outfit;
  final PlannedOutfit? existing;
  final DateTime now;

  @override
  State<_PlanOutfitDialog> createState() => _PlanOutfitDialogState();
}

class _PlanOutfitDialogState extends State<_PlanOutfitDialog> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _note;
  late final DateTime _today;
  late final DateTime _lastDate;
  late DateTime _date;

  @override
  void initState() {
    super.initState();
    _note = TextEditingController(text: widget.existing?.note ?? '');
    _today = DateTime(widget.now.year, widget.now.month, widget.now.day);
    _lastDate = DateTime(_today.year, _today.month, _today.day + 365);
    final existingDate = widget.existing?.date;
    _date =
        existingDate != null &&
            !existingDate.isBefore(_today) &&
            !existingDate.isAfter(_lastDate)
        ? existingDate
        : _today;
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: _today,
      lastDate: _lastDate,
      currentDate: _today,
      helpText: 'Date to wear it',
      initialEntryMode: DatePickerEntryMode.input,
    );
    if (date != null && mounted) setState(() => _date = date);
  }

  void _save() {
    if (!_form.currentState!.validate()) return;
    if (_date.isBefore(_today) || _date.isAfter(_lastDate)) return;
    Navigator.pop(
      context,
      PlannedOutfit(
        id:
            widget.existing?.id ??
            'plan-${DateTime.now().microsecondsSinceEpoch}',
        outfit: widget.outfit,
        date: _date,
        note: _note.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    scrollable: true,
    insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
    title: Text(
      widget.existing == null ? 'Plan this outfit' : 'Edit your plan',
    ),
    content: SizedBox(
      width: 400,
      child: Form(
        key: _form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.outfit.title,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            Text(widget.outfit.occasion.label),
            const SizedBox(height: 20),
            const Eyebrow('Date to wear it'),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                key: const Key('plan_date'),
                onPressed: _pickDate,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Row(
                    children: [
                      const Icon(Icons.calendar_today_outlined, size: 18),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          MaterialLocalizations.of(
                            context,
                          ).formatFullDate(_date),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (widget.existing != null &&
                widget.existing!.date.isBefore(_today)) ...[
              const SizedBox(height: 8),
              const Text(
                'This past plan is set to today. Choose another day if you like.',
                style: TextStyle(color: ThreadTheme.muted),
              ),
            ],
            const SizedBox(height: 20),
            TextFormField(
              key: const Key('plan_note'),
              controller: _note,
              maxLength: 160,
              minLines: 2,
              maxLines: 4,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Note (optional)',
                hintText: 'Dinner at 7, bring a jacket…',
              ),
              validator: (value) => (value?.characters.length ?? 0) > 160
                  ? 'Keep your note to 160 characters.'
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
        key: const Key('save_plan'),
        onPressed: _save,
        child: const Text('Save plan'),
      ),
    ],
  );
}
