import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/style_discovery_models.dart';
import '../models/trend_models.dart';
import '../services/trend_service.dart';
import '../theme.dart';

class TrendPanel extends StatefulWidget {
  const TrendPanel({super.key, required this.onSelected, this.service});

  final ValueChanged<StyleDirection> onSelected;
  final TrendService? service;

  @override
  State<TrendPanel> createState() => _TrendPanelState();
}

class _TrendPanelState extends State<TrendPanel> {
  late TrendService _service;
  bool _ownsService = false;
  bool _loading = false;
  bool _expanded = true;
  String? _error;
  TrendSnapshot? _snapshot;
  int _requestVersion = 0;

  @override
  void initState() {
    super.initState();
    _setService();
  }

  void _setService() {
    _ownsService = widget.service == null;
    _service = widget.service ?? TrendService();
  }

  @override
  void didUpdateWidget(covariant TrendPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.service != widget.service) {
      _requestVersion++;
      if (_ownsService) _service.dispose();
      _setService();
      _loading = false;
      _error = null;
      _snapshot = null;
    }
  }

  @override
  void dispose() {
    _requestVersion++;
    if (_ownsService) _service.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (_loading) return;
    final version = ++_requestVersion;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final snapshot = await _service.fetchTrends();
      if (!mounted || version != _requestVersion) return;
      setState(() {
        _snapshot = snapshot;
        _expanded = true;
      });
    } catch (error) {
      if (!mounted || version != _requestVersion) return;
      setState(() {
        _error = error is TrendException
            ? error.message
            : 'Could not load recent headlines. Try again later.';
      });
    } finally {
      if (mounted && version == _requestVersion) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _open(TrendHeadline item) async {
    try {
      if (await launchUrl(
        Uri.parse(item.url),
        mode: LaunchMode.externalApplication,
      )) {
        return;
      }
    } catch (_) {
      /* Report failures in the current UI. */
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('This article could not be opened.')),
    );
  }

  String _date(DateTime value) {
    final date = value.toUtc();
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${date.day} ${months[date.month - 1]} ${date.year}';
  }

  String _time(DateTime value) =>
      '${_date(value)} ${value.toUtc().hour.toString().padLeft(2, '0')}:${value.toUtc().minute.toString().padLeft(2, '0')} UTC';

  @override
  Widget build(BuildContext context) {
    final snapshot = _snapshot;
    final theme = Theme.of(context);
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.newspaper_outlined, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Recent style headlines',
                  style: theme.textTheme.titleMedium,
                ),
              ),
              if (snapshot != null)
                IconButton(
                  tooltip: _expanded
                      ? 'Collapse headlines'
                      : 'Expand headlines',
                  onPressed: () => setState(() => _expanded = !_expanded),
                  icon: Icon(_expanded ? Icons.expand_less : Icons.expand_more),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Menswear reports from GQ, Esquire and FashionBeans, newest first. A starting point for inspiration, with links to the original articles.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              OutlinedButton.icon(
                onPressed: _loading ? null : _load,
                icon: _loading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh, size: 18),
                label: Text(
                  _loading
                      ? 'Checking headlines...'
                      : snapshot == null
                      ? 'Check latest headlines'
                      : 'Refresh headlines',
                ),
              ),
              if (snapshot != null)
                Text(
                  'Feed checked ${_time(snapshot.fetchedAt)}',
                  style: theme.textTheme.bodySmall,
                ),
            ],
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                '$_error${snapshot != null ? ' Showing the last loaded headlines.' : ''}',
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ),
          if (snapshot != null && _expanded) ...[
            if (snapshot.isStaleAt(DateTime.now()))
              const Padding(
                padding: EdgeInsets.only(top: 10),
                child: Text(
                  'This feed is over 48 hours old. The dates below show when each article was published.',
                ),
              ),
            if (snapshot.isPartial)
              const Padding(
                padding: EdgeInsets.only(top: 10),
                child: Text(
                  'Some publishers could not refresh. Their earlier headlines may still appear.',
                ),
              ),
            if (snapshot.headlines.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 14),
                child: Text(
                  'No eligible headlines from the last 90 days are available. Your local style directions still work.',
                ),
              ),
            for (final item in snapshot.headlines.take(6)) ...[
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 10),
                child: Divider(height: 1),
              ),
              Text(
                '${item.publisher} · Published ${_date(item.publishedAt)}',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 5),
              Text(item.headline, style: theme.textTheme.titleSmall),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  TextButton.icon(
                    onPressed: () => _open(item),
                    icon: const Icon(Icons.open_in_new, size: 15),
                    label: Text('Read at ${item.publisher}'),
                  ),
                  if (item.suggestedDirection case final direction?)
                    TextButton.icon(
                      onPressed: () => widget.onSelected(direction),
                      icon: const Icon(Icons.checkroom_outlined, size: 16),
                      label: Text('Try ${direction.label.toLowerCase()}'),
                    ),
                ],
              ),
            ],
            if (snapshot.headlines.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Style shortcuts match words in a headline to an existing outfit direction. They are not popularity rankings or a copy of the featured look. Article rights remain with each publisher.',
                  style: theme.textTheme.bodySmall,
                ),
              ),
          ],
        ],
      ),
    );
  }
}
