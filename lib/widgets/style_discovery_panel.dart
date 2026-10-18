import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/style_discovery_models.dart';
import '../services/style_discovery_service.dart';
import '../theme.dart';

class StyleDiscoveryPanel extends StatefulWidget {
  const StyleDiscoveryPanel({
    super.key,
    required this.selected,
    required this.onSelected,
    this.service,
  });

  final StyleDirection selected;
  final ValueChanged<StyleDirection> onSelected;
  final StyleDiscoveryService? service;

  @override
  State<StyleDiscoveryPanel> createState() => _StyleDiscoveryPanelState();
}

class _StyleDiscoveryPanelState extends State<StyleDiscoveryPanel> {
  late StyleDiscoveryService _service;
  bool _ownsService = false;
  bool _loading = false;
  bool _showSources = true;
  String? _error;
  List<StyleInspiration> _inspirations = const [];
  int _requestVersion = 0;

  @override
  void initState() {
    super.initState();
    _ownsService = widget.service == null;
    _service = widget.service ?? StyleDiscoveryService();
  }

  @override
  void didUpdateWidget(covariant StyleDiscoveryPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.service != widget.service) {
      _requestVersion++;
      if (_ownsService) _service.dispose();
      _ownsService = widget.service == null;
      _service = widget.service ?? StyleDiscoveryService();
      _loading = false;
    }
  }

  @override
  void dispose() {
    _requestVersion++;
    if (_ownsService) _service.dispose();
    super.dispose();
  }

  Future<void> _fetch() async {
    if (_loading) return;
    final version = ++_requestVersion;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final inspirations = await _service.fetchInspirations();
      if (!mounted || version != _requestVersion) return;
      setState(() {
        _inspirations = inspirations;
        _showSources = true;
      });
    } catch (error) {
      if (!mounted || version != _requestVersion) return;
      setState(() {
        _error = error is StyleDiscoveryException
            ? error.message
            : 'The style guides could not be loaded. You can still choose a local style.';
      });
    } finally {
      if (mounted && version == _requestVersion) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _open(String url) async {
    try {
      final opened = await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      );
      if (opened || !mounted) return;
    } catch (_) {
      if (!mounted) return;
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('This link could not be opened on your device.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) => SurfaceCard(
    padding: const EdgeInsets.all(20),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Eyebrow('Discover your direction'),
        const SizedBox(height: 7),
        Text(
          'Style inspiration from the web',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 7),
        const Text(
          'Try a style direction, or explore Wikipedia guides to find what feels like you.',
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 7,
          runSpacing: 5,
          children: [
            for (final direction in StyleDirection.values)
              ChoiceChip(
                label: Text(direction.label),
                selected: widget.selected == direction,
                onSelected: (_) => widget.onSelected(direction),
              ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 10,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            OutlinedButton.icon(
              onPressed: _loading ? null : _fetch,
              icon: _loading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.public_rounded, size: 18),
              label: Text(
                _loading
                    ? 'Loading guides…'
                    : _inspirations.isEmpty
                    ? 'Explore styles'
                    : 'Refresh sources',
              ),
            ),
            if (_inspirations.isNotEmpty)
              TextButton.icon(
                onPressed: () => setState(() => _showSources = !_showSources),
                icon: Icon(
                  _showSources ? Icons.expand_less : Icons.expand_more,
                ),
                label: Text(_showSources ? 'Hide guides' : 'Show guides'),
              ),
          ],
        ),
        if (_error != null) ...[
          const SizedBox(height: 10),
          Text(_error!, style: const TextStyle(color: ThreadTheme.muted)),
          if (_inspirations.isNotEmpty)
            const Text(
              'Previously loaded excerpts are shown below.',
              style: TextStyle(fontSize: 12),
            ),
        ],
        if (_inspirations.isNotEmpty && _showSources) ...[
          const SizedBox(height: 10),
          Text(
            'Loaded ${_dateLabel(_inspirations.first.fetchedAt)} · ${_inspirations.length} of ${StyleDirection.values.length} guides',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          for (final inspiration in _inspirations)
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              childrenPadding: const EdgeInsets.only(bottom: 14),
              title: Text(
                inspiration.direction.label,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              subtitle: Text(
                'Wikipedia · ${inspiration.title}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(inspiration.summary),
                ),
                const SizedBox(height: 6),
                Wrap(
                  alignment: WrapAlignment.start,
                  spacing: 8,
                  children: [
                    TextButton.icon(
                      onPressed: () => _open(inspiration.sourceUrl),
                      icon: const Icon(Icons.open_in_new, size: 15),
                      label: const Text('Read source'),
                    ),
                    TextButton.icon(
                      onPressed: () => widget.onSelected(inspiration.direction),
                      icon: const Icon(Icons.checkroom_outlined, size: 16),
                      label: const Text('Try this style'),
                    ),
                  ],
                ),
              ],
            ),
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                'Excerpts by Wikipedia contributors · ',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              TextButton(
                onPressed: () =>
                    _open('https://creativecommons.org/licenses/by-sa/4.0/'),
                child: const Text('CC BY-SA 4.0'),
              ),
            ],
          ),
          Text(
            'Excerpts are shortened. These guides provide style context; your likes and dislikes personalize the outfit order.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ] else if (_inspirations.isEmpty) ...[
          const SizedBox(height: 8),
          Text(
            'Guides load only when you explore. Style directions work offline.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ],
    ),
  );
}

String _dateLabel(DateTime value) {
  final local = value.toLocal();
  String two(int number) => number.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)} at ${two(local.hour)}:${two(local.minute)}';
}
