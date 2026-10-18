import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/weather_models.dart';
import '../services/weather_service.dart';
import '../theme.dart';

class WeatherPanel extends StatelessWidget {
  const WeatherPanel({
    super.key,
    required this.weather,
    required this.busy,
    required this.onChoose,
    required this.onRefresh,
    required this.onClear,
  });
  final WeatherSnapshot? weather;
  final bool busy;
  final VoidCallback onChoose, onRefresh, onClear;

  @override
  Widget build(BuildContext context) {
    final current = weather;
    return SurfaceCard(
      padding: const EdgeInsets.all(20),
      color: ThreadTheme.softGreen,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.cloud_outlined, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  current == null
                      ? 'Dress for the weather'
                      : current.location.label,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              if (busy)
                const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (current == null)
            const Text(
              'Choose a city to adjust fabrics, shoes, and layers to current conditions.',
              style: TextStyle(fontSize: 12),
            )
          else ...[
            Text(
              '${current.temperatureC.round()}°C · Feels like ${current.apparentTemperatureC.round()}°C · ${current.conditionLabel}',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 5),
            Text(
              current.isStale
                  ? 'Saved weather is over an hour old. Refresh to use it for outfits.'
                  : 'Updated ${TimeOfDay.fromDateTime(current.fetchedAt.toLocal()).format(context)} · Current conditions, not a future forecast.',
              style: const TextStyle(fontSize: 11, color: ThreadTheme.muted),
            ),
          ],
          const SizedBox(height: 6),
          Wrap(
            spacing: 10,
            runSpacing: 3,
            children: [
              TextButton.icon(
                key: const Key('choose_weather_city'),
                onPressed: busy ? null : onChoose,
                icon: const Icon(Icons.location_city_outlined, size: 16),
                label: Text(current == null ? 'Choose city' : 'Change city'),
              ),
              if (current != null) ...[
                IconButton(
                  tooltip: 'Refresh weather',
                  onPressed: busy ? null : onRefresh,
                  icon: const Icon(Icons.refresh_rounded, size: 19),
                ),
                TextButton(
                  onPressed: busy ? null : onClear,
                  child: const Text('Turn off'),
                ),
              ],
            ],
          ),
          const _WeatherAttribution(),
        ],
      ),
    );
  }
}

class _WeatherAttribution extends StatelessWidget {
  const _WeatherAttribution();
  @override
  Widget build(BuildContext context) => Wrap(
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [
      const Text(
        'Weather: ',
        style: TextStyle(fontSize: 10, color: ThreadTheme.muted),
      ),
      InkWell(
        onTap: () => _openSource(context, 'https://open-meteo.com/'),
        child: const Padding(
          padding: EdgeInsets.symmetric(vertical: 7),
          child: Text(
            'Open-Meteo',
            style: TextStyle(
              fontSize: 10,
              decoration: TextDecoration.underline,
            ),
          ),
        ),
      ),
      const Text(' · ', style: TextStyle(fontSize: 10)),
      InkWell(
        onTap: () => _openSource(
          context,
          'https://creativecommons.org/licenses/by/4.0/',
        ),
        child: const Padding(
          padding: EdgeInsets.symmetric(vertical: 7),
          child: Text(
            'CC BY 4.0',
            style: TextStyle(
              fontSize: 10,
              decoration: TextDecoration.underline,
            ),
          ),
        ),
      ),
    ],
  );
}

Future<void> _openSource(BuildContext context, String url) async {
  try {
    if (!await launchUrl(
      Uri.parse(url),
      mode: LaunchMode.externalApplication,
    )) {
      throw StateError('Link unavailable');
    }
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('This link could not be opened on your device.'),
        ),
      );
    }
  }
}

Future<CityLocation?> showCitySearchDialog(
  BuildContext context,
  WeatherService service,
) => showDialog<CityLocation>(
  context: context,
  builder: (_) => _CitySearchDialog(service: service),
);

class _CitySearchDialog extends StatefulWidget {
  const _CitySearchDialog({required this.service});
  final WeatherService service;
  @override
  State<_CitySearchDialog> createState() => _CitySearchDialogState();
}

class _CitySearchDialogState extends State<_CitySearchDialog> {
  final _query = TextEditingController();
  bool _busy = false;
  String? _error;
  bool _searched = false;
  List<CityLocation> _results = [];
  int _request = 0;
  @override
  void dispose() {
    _request++;
    _query.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final query = _query.text.trim();
    if (query.length < 2) {
      setState(() => _error = 'Enter at least two characters.');
      return;
    }
    final request = ++_request;
    setState(() {
      _busy = true;
      _error = null;
      _results = [];
    });
    try {
      final results = await widget.service.searchCities(query);
      if (!mounted || request != _request) return;
      setState(() {
        _results = results;
        _searched = true;
      });
    } catch (_) {
      if (mounted && request == _request) {
        setState(
          () => _error =
              'City search is unavailable. Check your connection and try again.',
        );
      }
    } finally {
      if (mounted && request == _request) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Where are you dressing for?'),
    content: SizedBox(
      width: 420,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Search a city. Only your search and the selected city coordinates are sent to Open-Meteo; photos stay on your device.',
              style: TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 16),
            TextField(
              key: const Key('city_search_input'),
              controller: _query,
              maxLength: 100,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _search(),
              onChanged: (_) {
                _request++;
                setState(() {
                  _busy = false;
                  _searched = false;
                  _results = [];
                  _error = null;
                });
              },
              decoration: const InputDecoration(
                labelText: 'City',
                hintText: 'e.g. Bengaluru, India',
              ),
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: _busy ? null : _search,
              icon: _busy
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.search, size: 17),
              label: const Text('Search cities'),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            if (_searched && _results.isEmpty && !_busy)
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: Text('No cities found. Try adding a country or region.'),
              ),
            ..._results.map(
              (city) => ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(city.label),
                subtitle: Text(
                  '${city.latitude.toStringAsFixed(2)}, ${city.longitude.toStringAsFixed(2)}',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.pop(context, city),
              ),
            ),
            const SizedBox(height: 12),
            const _WeatherAttribution(),
            InkWell(
              onTap: () => _openSource(context, 'https://www.geonames.org/'),
              child: const Padding(
                padding: EdgeInsets.symmetric(vertical: 6),
                child: Text(
                  'Location data: GeoNames · CC BY 4.0',
                  style: TextStyle(
                    fontSize: 10,
                    decoration: TextDecoration.underline,
                  ),
                ),
              ),
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
    ],
  );
}
