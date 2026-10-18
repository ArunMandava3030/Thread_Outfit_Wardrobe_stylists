import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'models/style_models.dart';
import 'models/learning_models.dart';
import 'models/planner_models.dart';
import 'models/weather_models.dart';
import 'models/wardrobe_models.dart';
import 'models/style_discovery_models.dart';
import 'screens/planner_screen.dart';
import 'screens/wardrobe_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/outfit_rating_screen.dart';
import 'services/adaptive_stylist.dart';
import 'services/weather_service.dart';
import 'services/weather_stylist.dart';
import 'services/wardrobe_stylist.dart';
import 'services/style_direction_stylist.dart';
import 'services/style_discovery_service.dart';
import 'services/photo_analyzer.dart';
import 'services/style_engine.dart';
import 'services/style_store.dart';
import 'theme.dart';
import 'widgets/garment_art.dart';
import 'widgets/outfit_card.dart';
import 'widgets/photo_analysis_sheet.dart';
import 'widgets/weather_panel.dart';
import 'widgets/style_discovery_panel.dart';
import 'widgets/trend_panel.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks([
      'Roboto',
    ], await rootBundle.loadString('assets/fonts/LICENSE.txt'));
  });
  runApp(const ThreadApp());
}

class ThreadApp extends StatelessWidget {
  const ThreadApp({
    super.key,
    this.store,
    this.weatherService,
    this.discoveryService,
  });
  final StyleStore? store;
  final WeatherService? weatherService;
  final StyleDiscoveryService? discoveryService;
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Thread · Your personal outfit companion',
    debugShowCheckedModeBanner: false,
    theme: ThreadTheme.theme,
    home: StyleHome(
      store: store ?? StyleStore(),
      weatherService: weatherService,
      discoveryService: discoveryService,
    ),
  );
}

class StyleHome extends StatefulWidget {
  const StyleHome({
    super.key,
    required this.store,
    this.weatherService,
    this.discoveryService,
  });
  final StyleStore store;
  final WeatherService? weatherService;
  final StyleDiscoveryService? discoveryService;
  @override
  State<StyleHome> createState() => _StyleHomeState();
}

class _StyleHomeState extends State<StyleHome> {
  final _scroll = ScrollController();
  final _resultsKey = GlobalKey();
  final _picker = ImagePicker();
  StyleProfile _profile = const StyleProfile();
  bool _configured = false;
  bool _loading = true;
  bool _picking = false;
  bool _writing = false;
  Completer<void>? _writeFinished;
  bool _includeLayer = true;
  bool _generated = false;
  int _page = 0;
  int _profileVersion = 0;
  ShirtColor _shirt = ShirtColor.presets.first;
  StartingPiece _startingPiece = StartingPiece.shirt;
  ShirtColor? _matchingColor;
  int _studioStep = 0;
  Occasion _occasion = Occasion.casual;
  Uint8List? _photo;
  List<OutfitRecommendation> _saved = [];
  List<OutfitRecommendation> _outfits = [];
  List<StyleFeedbackEntry> _feedback = [];
  List<PlannedOutfit> _plans = [];
  List<WardrobeItem> _wardrobe = [];
  StyleDirection _direction = StyleDirection.everyday;
  WeatherSnapshot? _weather;
  late final WeatherService _weatherService;
  bool _weatherBusy = false;
  bool _preferWardrobe = true;
  int _weatherRequest = 0;

  @override
  void initState() {
    super.initState();
    _weatherService = widget.weatherService ?? WeatherService();
    _load();
  }

  @override
  void dispose() {
    _scroll.dispose();
    if (widget.weatherService == null) _weatherService.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final loaded = await widget.store.load();
      if (!mounted) return;
      setState(() {
        _profile = loaded.profile;
        _configured = loaded.configured;
        _saved = loaded.saved;
        _feedback = loaded.feedback;
        _plans = loaded.plans;
        _weather = loaded.weather;
        _wardrobe = loaded.wardrobe;
        _direction = loaded.direction;
      });
      if (loaded.recoveryMessage != null) {
        _message(loaded.recoveryMessage!);
      }
    } catch (_) {
      if (mounted) {
        _message(
          'Saved data could not be loaded. You can still create an outfit.',
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      try {
        final response = await _picker.retrieveLostData();
        if (!mounted || response.isEmpty) return;
        if (response.files?.isNotEmpty == true) {
          final bytes = await _readPhoto(response.files!.first);
          if (!mounted) return;
          final mode = await showDialog<int>(
            context: context,
            builder: (context) => SimpleDialog(
              title: const Text('Your photo is ready'),
              children: [
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                  child: Text(
                    'Thread restarted while the camera was open. What would you like to use this photo for?',
                  ),
                ),
                for (final (index, title) in [
                  'Shirt color',
                  'Pants color',
                  'Skin tone',
                  'Body proportions',
                ].indexed)
                  SimpleDialogOption(
                    onPressed: () => Navigator.pop(context, index),
                    child: Text(title),
                  ),
              ],
            ),
          );
          if (mode == null || !mounted) return;
          final result = await _analyzeBytes(
            bytes,
            sampleSkin: mode == 2,
            measureBody: mode == 3,
            garmentLabel: mode == 1 ? 'pants' : null,
          );
          if (result == null || !mounted) return;
          if ((mode == 0 || mode == 1) && result.shirtColor != null) {
            setState(() {
              _shirt = result.shirtColor!;
              _photo = bytes;
              _generated = false;
              _outfits = [];
              _startingPiece = mode == 1
                  ? StartingPiece.pants
                  : StartingPiece.shirt;
              _matchingColor = null;
              _studioStep = 0;
            });
          } else {
            setState(() {
              if (result.skinToneArgb != null) {
                _profile = _profile.copyWith(
                  skinToneArgb: result.skinToneArgb,
                  useSkinTone: true,
                );
              }
              if (result.bodyShape != null) {
                _profile = _profile.copyWith(bodyShape: result.bodyShape);
              }
              _profileVersion++;
              _page = 2;
            });
            _message(
              'Recovered estimate added. Review it and save your profile.',
            );
          }
        } else if (response.exception != null) {
          _message(
            'The interrupted photo could not be recovered. Please try again.',
          );
        }
      } catch (_) {
        if (mounted) {
          _message(
            'The interrupted photo could not be opened. Please try again.',
          );
        }
      }
    }
  }

  void _message(String text) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  void _navigate(int page) {
    setState(() => _page = page);
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  void _invalidate(VoidCallback update) => setState(() {
    update();
    _generated = false;
    _outfits = [];
    if (_studioStep == 3) _studioStep = 2;
  });

  void _chooseAnchor(ShirtColor color, {StartingPiece? piece}) {
    _invalidate(() {
      _shirt = color;
      _startingPiece = piece ?? _startingPiece;
      _matchingColor = null;
      _photo = null;
      _studioStep = 0;
    });
  }

  void _goToStep(int step) {
    setState(() => _studioStep = step);
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  Future<Uint8List> _readPhoto(XFile file) async {
    if (await file.length() > 25 * 1024 * 1024) {
      throw const FormatException('Choose a photo smaller than 25 MB.');
    }
    return file.readAsBytes();
  }

  Future<PhotoAnalysisResult?> _analyzeBytes(
    Uint8List bytes, {
    bool sampleSkin = false,
    bool measureBody = false,
    String? garmentLabel,
  }) => showModalBottomSheet<PhotoAnalysisResult>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: ThreadTheme.canvas,
    builder: (_) => PhotoAnalysisSheet(
      bytes: bytes,
      sampleSkin: sampleSkin,
      measureBody: measureBody,
      garmentLabel: garmentLabel,
    ),
  );

  Future<PhotoAnalysisResult?> _pickPhoto({
    bool sampleSkin = false,
    bool measureBody = false,
    ImageSource? source,
    String? garmentLabel,
    bool updateStudio = true,
    ValueChanged<Uint8List>? onPhotoLoaded,
  }) async {
    if (_picking) return null;
    final cameraAvailable =
        kIsWeb ||
        defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
    final choice =
        source ??
        await showModalBottomSheet<ImageSource>(
          context: context,
          showDragHandle: true,
          builder: (context) => SafeArea(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ListTile(
                    title: const Text('Choose a photo'),
                    subtitle: Text(
                      measureBody
                          ? 'Use a front-facing photo showing shoulders, waist, and hips.'
                          : 'Even daylight gives the most useful color sample.',
                    ),
                  ),
                  if (cameraAvailable)
                    ListTile(
                      leading: const Icon(Icons.photo_camera_outlined),
                      title: const Text('Take a photo'),
                      onTap: () => Navigator.pop(context, ImageSource.camera),
                    ),
                  ListTile(
                    leading: const Icon(Icons.photo_library_outlined),
                    title: const Text('Choose from gallery'),
                    onTap: () => Navigator.pop(context, ImageSource.gallery),
                  ),
                ],
              ),
            ),
          ),
        );
    if (choice == null || !mounted) return null;
    setState(() => _picking = true);
    try {
      final file = await _picker.pickImage(
        source: choice,
        maxWidth: 1800,
        maxHeight: 1800,
        imageQuality: 90,
        requestFullMetadata: false,
      );
      if (file == null || !mounted) return null;
      final bytes = await _readPhoto(file);
      if (!mounted) return null;
      onPhotoLoaded?.call(bytes);
      final result = await _analyzeBytes(
        bytes,
        sampleSkin: sampleSkin,
        measureBody: measureBody,
        garmentLabel:
            garmentLabel ??
            (!sampleSkin &&
                    !measureBody &&
                    _startingPiece == StartingPiece.pants
                ? 'pants'
                : null),
      );
      if (!mounted || result == null) return null;
      if (updateStudio &&
          !sampleSkin &&
          !measureBody &&
          result.shirtColor != null) {
        _invalidate(() {
          _shirt = result.shirtColor!;
          _photo = bytes;
          _matchingColor = null;
          _studioStep = 0;
        });
      }
      return result;
    } on PlatformException catch (error) {
      if (mounted) {
        _message(
          error.code.toLowerCase().contains('denied')
              ? 'Camera or photo access is off. Enable it in device settings, or choose a color below.'
              : 'The photo picker is unavailable. Try the gallery or choose a color.',
        );
      }
    } on FormatException catch (error) {
      if (mounted) _message(error.message);
    } catch (_) {
      if (mounted) {
        _message('This photo could not be opened. Please try another photo.');
      }
    } finally {
      if (mounted) setState(() => _picking = false);
    }
    return null;
  }

  Future<void> _saveProfile(StyleProfile profile) async {
    final saved = await _persist(() => widget.store.saveProfile(profile), () {
      _profile = profile;
      _configured = true;
      _profileVersion++;
      _generated = false;
      _outfits = [];
      if (_studioStep == 3) _studioStep = 2;
    });
    if (saved && mounted) {
      _navigate(0);
      _message('Profile saved. Let’s put your look together.');
    }
  }

  Future<void> _clearData() async {
    if (_writing) return;
    setState(() => _weatherBusy = false);
    _weatherRequest++;
    final cleared = await _persist(widget.store.clear, () {
      _profile = const StyleProfile();
      _configured = false;
      _saved = [];
      _feedback = [];
      _plans = [];
      _wardrobe = [];
      _weather = null;
      _weatherBusy = false;
      _direction = StyleDirection.everyday;
      _preferWardrobe = true;
      _outfits = [];
      _generated = false;
      _photo = null;
      _shirt = ShirtColor.presets.first;
      _startingPiece = StartingPiece.shirt;
      _matchingColor = null;
      _studioStep = 0;
      _profileVersion++;
    });
    if (cleared && mounted) {
      _navigate(0);
      _message(
        'Your profile, wardrobe, plans, and learned preferences have been cleared.',
      );
    }
  }

  Future<bool> _persist(
    Future<void> Function() write,
    VoidCallback update,
  ) async {
    if (_writing) return false;
    final finished = Completer<void>();
    _writeFinished = finished;
    setState(() => _writing = true);
    try {
      await write();
      if (!mounted) return false;
      setState(update);
      return true;
    } catch (_) {
      if (mounted) _message('Changes could not be saved. Please try again.');
      return false;
    } finally {
      if (mounted) setState(() => _writing = false);
      _writeFinished = null;
      finished.complete();
    }
  }

  StyleFeedback? _voteFor(OutfitRecommendation outfit) {
    for (final entry in _feedback) {
      if (entry.outfit.id == outfit.id) return entry.feedback;
    }
    return null;
  }

  Future<void> _vote(OutfitRecommendation outfit, StyleFeedback vote) async {
    final nextVote = _voteFor(outfit) == vote ? null : vote;
    final next = const AdaptiveStylist().record(_feedback, outfit, nextVote);
    if (await _persist(
      () => widget.store.saveFeedback(next),
      () => _feedback = next,
    )) {
      if (mounted) {
        _message(
          nextVote == null
              ? 'Feedback removed.'
              : 'Preference saved. Your next outfit edit will learn from it.',
        );
      }
    }
  }

  Future<void> _resetLearning() async {
    final reset = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reset style learning?'),
        content: const Text(
          'Remove all likes and dislikes and start fresh. Your wardrobe, plans, and saved looks stay available.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep learning'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Reset learning'),
          ),
        ],
      ),
    );
    if (reset == true && mounted) {
      await _persist(() => widget.store.saveFeedback([]), () => _feedback = []);
    }
  }

  Future<void> _setDirection(StyleDirection direction) async {
    await _persist(() => widget.store.saveDirection(direction), () {
      _direction = direction;
      _generated = false;
      _outfits = [];
      if (_studioStep == 3) _studioStep = 2;
    });
  }

  Future<void> _plan(
    OutfitRecommendation outfit, {
    PlannedOutfit? existing,
  }) async {
    final entry = await showPlanOutfitDialog(
      context,
      outfit: outfit,
      existing: existing,
    );
    if (entry == null || !mounted) return;
    final next = [entry, ..._plans.where((plan) => plan.id != entry.id)];
    if (await _persist(
      () => widget.store.savePlans(next),
      () => _plans = next,
    )) {
      if (mounted) _message('Outfit added to your planner.');
    }
  }

  Future<void> _removePlan(String id) async {
    final next = _plans.where((plan) => plan.id != id).toList();
    await _persist(() => widget.store.savePlans(next), () => _plans = next);
  }

  Future<void> _saveWardrobe(WardrobeItem item) async {
    final next = [item, ..._wardrobe.where((entry) => entry.id != item.id)];
    await _persist(
      () => widget.store.saveWardrobe(next),
      () => _wardrobe = next,
    );
  }

  Future<void> _removeWardrobe(String id) async {
    final next = _wardrobe.where((entry) => entry.id != id).toList();
    await _persist(
      () => widget.store.saveWardrobe(next),
      () => _wardrobe = next,
    );
  }

  void _wear(WardrobeItem item) {
    _invalidate(() {
      _shirt = ShirtColor(name: item.colorName, argb: item.colorArgb);
      _photo = null;
      _startingPiece = item.category == WardrobeCategory.pants
          ? StartingPiece.pants
          : StartingPiece.shirt;
      _matchingColor = null;
      _studioStep = 1;
    });
    _navigate(0);
    _message('Starting with ${item.name}. Choose a matching color next.');
  }

  Future<void> _chooseWeather() async {
    final location = await showCitySearchDialog(context, _weatherService);
    if (location != null && mounted) await _fetchWeather(location);
  }

  Future<void> _fetchWeather(CityLocation location) async {
    if (_writing) return;
    final request = ++_weatherRequest;
    setState(() => _weatherBusy = true);
    try {
      final weather = await _weatherService.fetchCurrent(location);
      if (!mounted || request != _weatherRequest) return;
      // A network response can arrive while another preference is being saved.
      // Keep it pending rather than discarding a successful city selection.
      while (_writeFinished != null) {
        await _writeFinished!.future;
        if (!mounted || request != _weatherRequest) return;
      }
      await _persist(() => widget.store.saveWeather(weather), () {
        _weather = weather;
        _generated = false;
        _outfits = [];
        if (_studioStep == 3) _studioStep = 2;
      });
    } on WeatherException catch (error) {
      if (mounted && request == _weatherRequest) _message(error.message);
    } catch (_) {
      if (mounted && request == _weatherRequest) {
        _message('Weather is unavailable. You can still create outfits.');
      }
    } finally {
      if (mounted && request == _weatherRequest) {
        setState(() => _weatherBusy = false);
      }
    }
  }

  Future<void> _clearWeather() async {
    _weatherRequest++;
    await _persist(() => widget.store.saveWeather(null), () {
      _weather = null;
      _weatherBusy = false;
      _generated = false;
      _outfits = [];
      if (_studioStep == 3) _studioStep = 2;
    });
  }

  Future<void> _toggleSave(OutfitRecommendation outfit) async {
    if (_writing) return;
    final exists = _saved.any((item) => item.id == outfit.id);
    final next = exists
        ? _saved.where((item) => item.id != outfit.id).toList()
        : [outfit, ..._saved];
    final saved = await _persist(
      () => widget.store.saveOutfits(next),
      () => _saved = next,
    );
    if (saved && mounted) {
      _message(
        exists
            ? 'Look removed from your collection.'
            : 'Look saved to your collection.',
      );
    }
  }

  Future<void> _favoriteFromRating(OutfitRecommendation outfit) async {
    while (_writeFinished != null) {
      await _writeFinished!.future;
    }
    if (!mounted) throw StateError('The studio was closed.');
    if (_saved.any((item) => item.id == outfit.id)) return;
    final next = [outfit, ..._saved];
    final saved = await _persist(
      () => widget.store.saveOutfits(next),
      () => _saved = next,
    );
    if (!saved) throw StateError('Could not save this favorite. Try again.');
  }

  Future<void> _openRating([OutfitRecommendation? outfit]) async {
    Uint8List? outfitPhoto;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (context) => Scaffold(
          appBar: AppBar(title: const Text('Rate my outfit')),
          body: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 860),
                  child: OutfitRatingScreen(
                    profile: _profile,
                    hasProfile: _configured,
                    history: _feedback,
                    savedIds: _saved.map((item) => item.id).toSet(),
                    initialOutfit: outfit,
                    onFavorite: _favoriteFromRating,
                    onPickColor: (label) async {
                      if (outfitPhoto != null) {
                        final reuse = await showModalBottomSheet<bool>(
                          context: context,
                          showDragHandle: true,
                          builder: (context) => SafeArea(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                ListTile(
                                  leading: const Icon(Icons.colorize_outlined),
                                  title: Text(
                                    'Sample $label from the same outfit photo',
                                  ),
                                  onTap: () => Navigator.pop(context, true),
                                ),
                                ListTile(
                                  leading: const Icon(
                                    Icons.add_photo_alternate_outlined,
                                  ),
                                  title: const Text('Choose another photo'),
                                  onTap: () => Navigator.pop(context, false),
                                ),
                              ],
                            ),
                          ),
                        );
                        if (reuse == null || !mounted) return null;
                        if (reuse) {
                          final sample = await _analyzeBytes(
                            outfitPhoto!,
                            garmentLabel: label.toLowerCase(),
                          );
                          return sample?.shirtColor;
                        }
                      }
                      final result = await _pickPhoto(
                        garmentLabel: label.toLowerCase(),
                        updateStudio: false,
                        onPhotoLoaded: (bytes) => outfitPhoto = bytes,
                      );
                      return result?.shirtColor;
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _generate() async {
    if (_matchingColor == null) {
      _goToStep(1);
      return;
    }
    if (!_configured) {
      final configure = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('What’s your height?'),
          content: const Text(
            'Add your height for more personal fit advice. You can also explore colors now with a default 175 cm profile.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Explore colors first'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Add my height'),
            ),
          ],
        ),
      );
      if (!mounted || configure == null) return;
      if (configure) {
        _navigate(2);
        return;
      }
    }
    setState(() {
      var candidates = const StyleEngine().generateForItem(
        startingPiece: _startingPiece,
        color: _shirt,
        matchingColor: _matchingColor,
        occasion: _occasion,
        profile: _profile,
        includeLayer: _includeLayer,
      );
      candidates = const StyleDirectionStylist().adapt(candidates, _direction);
      if (_weather != null) {
        candidates = const WeatherStylist().adapt(
          candidates,
          _weather!,
          includeLayer: _includeLayer,
        );
      }
      candidates = const AdaptiveStylist().rank(candidates, _feedback);
      _outfits = _preferWardrobe
          ? const WardrobeStylist().rankByOwnership(candidates, _wardrobe)
          : candidates;
      _generated = true;
      _studioStep = 3;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final resultsContext = _resultsKey.currentContext;
      if (resultsContext != null) {
        Scrollable.ensureVisible(
          resultsContext,
          duration: const Duration(milliseconds: 450),
          curve: Curves.easeOutCubic,
          alignment: .05,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final wide =
        MediaQuery.sizeOf(context).width >=
        940 * MediaQuery.textScalerOf(context).scale(1);
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            _header(wide),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : SingleChildScrollView(
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      controller: _scroll,
                      padding: EdgeInsets.fromLTRB(
                        wide ? 42 : 20,
                        wide ? 38 : 26,
                        wide ? 42 : 20,
                        40,
                      ),
                      child: Center(
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            maxWidth: _page == 2 ? 730 : 1160,
                          ),
                          child: switch (_page) {
                            1 => _savedPage(),
                            3 => PlannerScreen(
                              plans: _plans,
                              onRemove: _removePlan,
                              onEdit: (plan) =>
                                  _plan(plan.outfit, existing: plan),
                              onBrowse: () => _navigate(0),
                            ),
                            4 => WardrobeScreen(
                              items: _wardrobe,
                              onSave: _saveWardrobe,
                              onRemove: _removeWardrobe,
                              onWear: _wear,
                            ),
                            2 => ProfileScreen(
                              key: ValueKey(_profileVersion),
                              profile: _profile,
                              onSave: _saveProfile,
                              onAnalyze:
                                  ({
                                    bool sampleSkin = false,
                                    bool measureBody = false,
                                  }) => _pickPhoto(
                                    sampleSkin: sampleSkin,
                                    measureBody: measureBody,
                                  ),
                              onClear: _clearData,
                            ),
                            _ => _studio(wide),
                          },
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: wide
          ? null
          : NavigationBar(
              selectedIndex: _page,
              onDestinationSelected: _navigate,
              backgroundColor: Colors.white,
              indicatorColor: ThreadTheme.lime,
              labelTextStyle: const WidgetStatePropertyAll(
                TextStyle(fontSize: 10),
              ),
              destinations: const [
                NavigationDestination(
                  icon: Icon(Icons.auto_awesome_outlined),
                  selectedIcon: Icon(Icons.auto_awesome),
                  label: 'Style studio',
                ),
                NavigationDestination(
                  icon: Icon(Icons.bookmark_border_rounded),
                  selectedIcon: Icon(Icons.bookmark_rounded),
                  label: 'Saved looks',
                ),
                NavigationDestination(
                  icon: Icon(Icons.person_outline_rounded),
                  selectedIcon: Icon(Icons.person_rounded),
                  label: 'My profile',
                ),
                NavigationDestination(
                  icon: Icon(Icons.calendar_month_outlined),
                  selectedIcon: Icon(Icons.calendar_month),
                  label: 'Planner',
                ),
                NavigationDestination(
                  icon: Icon(Icons.checkroom_outlined),
                  selectedIcon: Icon(Icons.checkroom),
                  label: 'Wardrobe',
                ),
              ],
            ),
    );
  }

  Widget _header(bool wide) => Container(
    padding: EdgeInsets.symmetric(horizontal: wide ? 44 : 22, vertical: 17),
    decoration: const BoxDecoration(
      color: Colors.white,
      border: Border(bottom: BorderSide(color: ThreadTheme.line)),
    ),
    child: Row(
      children: [
        SizedBox(
          width: 145,
          height: 44,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: InkWell(
              onTap: () => _navigate(0),
              borderRadius: BorderRadius.circular(8),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.polymer_rounded,
                    color: ThreadTheme.green,
                    size: 34,
                  ),
                  SizedBox(width: 8),
                  Text(
                    'thread',
                    style: TextStyle(
                      fontSize: 28,
                      letterSpacing: -1.4,
                      fontWeight: FontWeight.w700,
                      color: ThreadTheme.ink,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (wide) ...[
          const SizedBox(width: 18),
          for (final (index, label) in [
            'Style studio',
            'Saved looks',
            'My profile',
            'Planner',
            'Wardrobe',
          ].indexed)
            Padding(
              padding: const EdgeInsets.only(right: 2),
              child: TextButton(
                style: TextButton.styleFrom(
                  foregroundColor: _page == index
                      ? ThreadTheme.ink
                      : ThreadTheme.muted,
                  backgroundColor: _page == index
                      ? ThreadTheme.softGreen
                      : null,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 16,
                  ),
                ),
                onPressed: () => _navigate(index),
                child: Text(label),
              ),
            ),
        ],
        const Spacer(),
        if (wide && MediaQuery.sizeOf(context).width >= 1480)
          const Flexible(
            child: Padding(
              padding: EdgeInsets.only(right: 18),
              child: Eyebrow('Less guesswork. More you.'),
            ),
          ),
        IconButton.filledTonal(
          tooltip: 'Your style profile',
          onPressed: () => _navigate(2),
          style: IconButton.styleFrom(backgroundColor: ThreadTheme.softGreen),
          icon: const Icon(Icons.person_outline_rounded, size: 21),
        ),
      ],
    ),
  );

  Widget _studio(bool wide) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(
                      Icons.wb_sunny_outlined,
                      size: 15,
                      color: ThreadTheme.green,
                    ),
                    SizedBox(width: 8),
                    Expanded(
                      child: Eyebrow(
                        'A good day to get dressed',
                        color: ThreadTheme.green,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 15),
                Text(
                  'One piece.\nYour whole outfit.',
                  style: wide
                      ? Theme.of(context).textTheme.displayLarge
                      : Theme.of(context).textTheme.displayMedium,
                ),
                const SizedBox(height: 15),
                const Text(
                  'Start with what you’re wearing. Find the colors,\npieces, and little details that bring it all together.',
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.6,
                    color: ThreadTheme.muted,
                  ),
                ),
              ],
            ),
          ),
          if (wide) SizedBox(width: 260, child: _profileSummary()),
        ],
      ),
      const SizedBox(height: 16),
      OutlinedButton.icon(
        key: const Key('open_outfit_rating'),
        onPressed: () => _openRating(),
        icon: const Icon(Icons.star_outline_rounded),
        label: const Text('Already dressed? Rate my outfit'),
      ),
      const SizedBox(height: 24),
      _studioProgress(),
      const SizedBox(height: 20),
      if (_studioStep == 0)
        _shirtPanel()
      else if (_studioStep == 1)
        _matchingPanel()
      else if (_studioStep == 2)
        _occasionPanel()
      else if (_generated)
        _results(),
      const SizedBox(height: 18),
      Wrap(
        spacing: 12,
        runSpacing: 10,
        children: [
          if (_studioStep > 0)
            OutlinedButton.icon(
              key: const Key('studio_back'),
              onPressed: () => _goToStep(_studioStep - 1),
              icon: const Icon(Icons.arrow_back_rounded),
              label: Text(_studioStep == 3 ? 'Edit occasion & layers' : 'Back'),
            ),
          if (_studioStep < 2)
            FilledButton.icon(
              key: const Key('studio_next'),
              onPressed: _studioStep == 1 && _matchingColor == null
                  ? null
                  : () => _goToStep(_studioStep + 1),
              icon: const Icon(Icons.arrow_forward_rounded),
              label: Text(
                _studioStep == 0
                    ? 'Find matching ${_startingPiece == StartingPiece.pants ? 'tops' : 'pants'}'
                    : 'Choose the occasion',
              ),
            ),
        ],
      ),
      const SizedBox(height: 22),
      ExpansionTile(
        key: const Key('studio_personalization'),
        tilePadding: EdgeInsets.zero,
        title: const Text('Style, weather & personal preferences'),
        subtitle: const Text('Optional extras for your next outfit'),
        children: [
          _contextPanels(wide),
          const SizedBox(height: 16),
          TrendPanel(onSelected: _setDirection),
          const SizedBox(height: 16),
        ],
      ),
      const SizedBox(height: 30),
      Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.spa_outlined, size: 15, color: ThreadTheme.muted),
          const SizedBox(width: 7),
          Flexible(
            child: Text(
              'Wear what feels like you. We’ll help with the rest.',
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    ],
  );

  Widget _studioProgress() => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: [
      for (final (index, label) in [
        'Your starting piece',
        'Matching colors',
        'The occasion',
        'Your outfits',
      ].indexed)
        ChoiceChip(
          key: Key('studio_step_$index'),
          label: Text('${index + 1}. $label'),
          selected: _studioStep == index,
          onSelected:
              (index == 2 && _matchingColor == null) ||
                  (index == 3 && !_generated)
              ? null
              : (_) => _goToStep(index),
        ),
    ],
  );

  Widget _matchingPanel() {
    final colors = const StyleEngine().matchingColors(
      startingPiece: _startingPiece,
      color: _shirt,
      profile: _profile,
    );
    final other = _startingPiece == StartingPiece.pants ? 'top' : 'pants';
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Eyebrow('02 / Make the pairing'),
          const SizedBox(height: 8),
          Text(
            'Choose your $other color',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 10),
          Text(
            'Keeping your ${_shirt.name.toLowerCase()} ${_startingPiece == StartingPiece.pants ? 'pants' : 'shirt'}. Pick a suggested match or another color you love.',
          ),
          const SizedBox(height: 20),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final (index, color) in colors.indexed)
                ChoiceChip(
                  key: Key('matching_suggestion_$index'),
                  avatar: CircleAvatar(backgroundColor: Color(color.argb)),
                  label: Text(color.name),
                  selected: _matchingColor?.argb == color.argb,
                  onSelected: (_) => _invalidate(() => _matchingColor = color),
                ),
            ],
          ),
          const SizedBox(height: 18),
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: const Text('More colors'),
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final color in ShirtColor.presets)
                    ChoiceChip(
                      key: Key('matching_color_${color.name}'),
                      label: Text(color.name),
                      avatar: CircleAvatar(backgroundColor: Color(color.argb)),
                      selected: _matchingColor?.argb == color.argb,
                      onSelected: (_) =>
                          _invalidate(() => _matchingColor = color),
                    ),
                ],
              ),
              const SizedBox(height: 12),
            ],
          ),
          if (_matchingColor != null) ...[
            const SizedBox(height: 14),
            Text(
              '${_matchingColor!.name} $other selected. Next, dress it for your plans.',
              style: const TextStyle(
                color: ThreadTheme.green,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _contextPanels(bool wide) {
    final weather = WeatherPanel(
      weather: _weather,
      busy: _weatherBusy || _writing,
      onChoose: _chooseWeather,
      onRefresh: () {
        if (_weather != null) _fetchWeather(_weather!.location);
      },
      onClear: _clearWeather,
    );
    final discovery = StyleDiscoveryPanel(
      selected: _direction,
      onSelected: _setDirection,
      service: widget.discoveryService,
    );
    if (!wide) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          weather,
          const SizedBox(height: 16),
          discovery,
          const SizedBox(height: 16),
          _learningPanel(),
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 11,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [weather, const SizedBox(height: 16), _learningPanel()],
          ),
        ),
        const SizedBox(width: 24),
        Expanded(flex: 10, child: discovery),
      ],
    );
  }

  Widget _learningPanel() => SurfaceCard(
    padding: const EdgeInsets.all(20),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Eyebrow('Your taste, remembered'),
        const SizedBox(height: 8),
        Text(
          _feedback.isEmpty
              ? 'Help Thread get to know you.'
              : '${_feedback.length} style ${_feedback.length == 1 ? 'preference' : 'preferences'} learned.',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 6),
        const Text(
          'Like or dislike a look to personalize your next recommendations. Your preferences stay on this device.',
          style: TextStyle(fontSize: 12, color: ThreadTheme.muted, height: 1.5),
        ),
        if (_wardrobe.isNotEmpty)
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: const Text('Prioritize my wardrobe colors'),
            subtitle: const Text(
              'Color matches still need the right garment and fit.',
            ),
            value: _preferWardrobe,
            onChanged: (value) => _invalidate(() => _preferWardrobe = value),
          ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            FilledButton.tonalIcon(
              onPressed: _generate,
              icon: const Icon(Icons.auto_awesome, size: 17),
              label: const Text('Create my outfit edit'),
            ),
            if (_feedback.isNotEmpty)
              TextButton(
                onPressed: _writing ? null : _resetLearning,
                child: const Text('Reset learning'),
              ),
            if (_wardrobe.isEmpty)
              TextButton(
                onPressed: () => _navigate(4),
                child: const Text('Add my wardrobe'),
              ),
          ],
        ),
      ],
    ),
  );

  Widget _profileSummary() => SurfaceCard(
    color: ThreadTheme.softGreen,
    padding: const EdgeInsets.all(20),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.tune_rounded, size: 16),
            const SizedBox(width: 8),
            Expanded(
              child: Eyebrow(
                _configured ? 'Made for you' : 'Make it personal',
                color: ThreadTheme.green,
              ),
            ),
          ],
        ),
        const SizedBox(height: 13),
        Text(
          _configured
              ? '${_profile.heightCm.round()} cm · Your fit'
              : 'Good style starts\nwith your details.',
          style: const TextStyle(
            fontSize: 19,
            fontWeight: FontWeight.w600,
            height: 1.3,
            letterSpacing: -.5,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          _configured
              ? (_profile.bodyShape?.label ?? 'Easy, comfortable proportions')
              : 'Add your height, proportions, and optional color profile.',
          style: const TextStyle(
            fontSize: 12,
            color: ThreadTheme.muted,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 10),
        TextButton(
          onPressed: () => _navigate(2),
          style: TextButton.styleFrom(padding: EdgeInsets.zero),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  _configured ? 'Edit my profile' : 'Build my profile',
                ),
              ),
              const SizedBox(width: 10),
              const Icon(Icons.arrow_forward_rounded, size: 16),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _shirtPanel() => SurfaceCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Eyebrow('01 / The starting point'),
        const SizedBox(height: 8),
        Text(
          'What are you wearing?',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 10,
          runSpacing: 8,
          children: [
            for (final piece in StartingPiece.values)
              ChoiceChip(
                key: Key('starting_piece_${piece.name}'),
                label: Text(
                  piece == StartingPiece.pants ? 'Pants first' : 'Shirt first',
                ),
                selected: _startingPiece == piece,
                onSelected: (_) => _chooseAnchor(_shirt, piece: piece),
              ),
          ],
        ),
        const SizedBox(height: 18),
        Container(
          height: 215,
          width: double.infinity,
          decoration: BoxDecoration(
            color: const Color(0xFFF0F1E8),
            borderRadius: BorderRadius.circular(16),
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Positioned(
                right: -22,
                top: -35,
                child: Container(
                  width: 185,
                  height: 185,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: const Color(0xFFE0E4D5)),
                  ),
                ),
              ),
              Positioned(
                left: -50,
                bottom: -85,
                child: Container(
                  width: 240,
                  height: 240,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: const Color(0xFFE0E4D5)),
                  ),
                ),
              ),
              if (_photo != null)
                Image.memory(
                  _photo!,
                  height: 215,
                  width: double.infinity,
                  fit: BoxFit.contain,
                  cacheWidth: 700,
                  errorBuilder: (_, error, stack) => GarmentArt(
                    kind: _startingPiece == StartingPiece.pants
                        ? GarmentKind.pants
                        : GarmentKind.shirt,
                    color: Color(_shirt.argb),
                    size: 200,
                  ),
                )
              else
                Transform.rotate(
                  angle: -.08,
                  child: GarmentArt(
                    kind: _startingPiece == StartingPiece.pants
                        ? GarmentKind.pants
                        : GarmentKind.shirt,
                    color: Color(_shirt.argb),
                    size: 214,
                  ),
                ),
              Positioned(
                bottom: 12,
                left: 12,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: .92),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _photo != null
                            ? Icons.colorize_rounded
                            : Icons.check_circle_outline,
                        size: 13,
                        color: ThreadTheme.green,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        _photo != null
                            ? 'Photo color sampled'
                            : 'Try a color to get started',
                        style: const TextStyle(
                          fontSize: 10,
                          color: ThreadTheme.green,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (_photo != null)
                Positioned(
                  right: 4,
                  top: 4,
                  child: IconButton.filledTonal(
                    tooltip: 'Remove photo',
                    onPressed: () => setState(() => _photo = null),
                    icon: const Icon(Icons.close, size: 16),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                key: const Key('add_photo'),
                onPressed: _picking ? null : () => _pickPhoto(),
                icon: Icon(
                  _picking
                      ? Icons.hourglass_top_rounded
                      : Icons.add_a_photo_outlined,
                  size: 17,
                ),
                label: Text(_picking ? 'Opening photo…' : 'Add your photo'),
              ),
            ),
            const SizedBox(width: 10),
            IconButton.outlined(
              tooltip: 'Choose from gallery',
              onPressed: _picking
                  ? null
                  : () => _pickPhoto(source: ImageSource.gallery),
              style: IconButton.styleFrom(
                minimumSize: const Size(50, 50),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(13),
                ),
                side: const BorderSide(color: ThreadTheme.line),
              ),
              icon: const Icon(Icons.photo_library_outlined, size: 21),
            ),
          ],
        ),
        const SizedBox(height: 18),
        Row(
          children: [
            Expanded(
              child: Text(
                'Or pick your ${_startingPiece == StartingPiece.pants ? 'pants' : 'shirt'} color',
                style: const TextStyle(fontSize: 12, color: ThreadTheme.muted),
              ),
            ),
            Container(
              width: 9,
              height: 9,
              decoration: BoxDecoration(
                color: Color(_shirt.argb),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.black12),
              ),
            ),
            const SizedBox(width: 6),
            Text(
              _shirt.name,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 7,
          runSpacing: 7,
          children: ShirtColor.presets
              .map(
                (color) => Tooltip(
                  message: color.name,
                  child: Semantics(
                    button: true,
                    selected: _shirt.argb == color.argb,
                    label:
                        '${color.name} ${_startingPiece == StartingPiece.pants ? 'pants' : 'shirt'}',
                    child: InkWell(
                      key: Key('starting_color_${color.name}'),
                      onTap: () => _chooseAnchor(color),
                      borderRadius: BorderRadius.circular(24),
                      child: SizedBox.square(
                        dimension: 36,
                        child: Center(
                          child: Container(
                            width: 29,
                            height: 29,
                            decoration: BoxDecoration(
                              color: Color(color.argb),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: _shirt.argb == color.argb
                                    ? ThreadTheme.green
                                    : Colors.black12,
                                width: _shirt.argb == color.argb ? 2 : 1,
                              ),
                            ),
                            child: _shirt.argb == color.argb
                                ? Icon(
                                    Icons.check_rounded,
                                    size: 17,
                                    color:
                                        Color(color.argb).computeLuminance() <
                                            .35
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
              )
              .toList(),
        ),
        const SizedBox(height: 13),
        const Row(
          children: [
            Icon(
              Icons.lock_outline_rounded,
              size: 12,
              color: ThreadTheme.muted,
            ),
            SizedBox(width: 5),
            Expanded(
              child: Text(
                'On-device sampling. Your photos stay with you.',
                style: TextStyle(fontSize: 10, color: ThreadTheme.muted),
              ),
            ),
          ],
        ),
      ],
    ),
  );

  Widget _occasionPanel() => SurfaceCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Eyebrow('03 / Set the scene'),
        const SizedBox(height: 8),
        Text(
          'Where are you headed?',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        Text(
          '${_shirt.name} ${_startingPiece == StartingPiece.pants ? 'pants' : 'shirt'} + '
          '${_matchingColor?.name ?? ''} ${_startingPiece == StartingPiece.pants ? 'top' : 'pants'}. '
          'Now choose where you’ll wear them.',
          style: const TextStyle(fontSize: 12, color: ThreadTheme.muted),
        ),
        const SizedBox(height: 18),
        LayoutBuilder(
          builder: (context, constraints) => Wrap(
            spacing: 10,
            runSpacing: 10,
            children: Occasion.values.map((occasion) {
              final selected = occasion == _occasion;
              return SizedBox(
                width: (constraints.maxWidth - 10) / 2,
                child: Material(
                  color: selected ? ThreadTheme.softGreen : Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(13),
                    side: BorderSide(
                      color: selected ? ThreadTheme.green : ThreadTheme.line,
                      width: selected ? 1.3 : 1,
                    ),
                  ),
                  child: InkWell(
                    key: ValueKey('occasion_${occasion.name}'),
                    borderRadius: BorderRadius.circular(13),
                    onTap: () => _invalidate(() => _occasion = occasion),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 15,
                      ),
                      child: Row(
                        children: [
                          Icon(
                            occasionIcon(occasion),
                            size: 19,
                            color: selected
                                ? ThreadTheme.green
                                : ThreadTheme.muted,
                          ),
                          const SizedBox(width: 9),
                          Expanded(
                            child: Text(
                              occasion.label,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: selected
                                    ? FontWeight.w600
                                    : FontWeight.w400,
                              ),
                            ),
                          ),
                          if (selected)
                            const Icon(
                              Icons.check_circle,
                              size: 15,
                              color: ThreadTheme.green,
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 15),
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: const Text(
            'Add a layering option',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
          ),
          subtitle: const Text(
            'That extra piece to finish the look.',
            style: TextStyle(fontSize: 11, color: ThreadTheme.muted),
          ),
          value: _includeLayer,
          onChanged: (value) => _invalidate(() => _includeLayer = value),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: ThreadTheme.canvas,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.tune_rounded,
                size: 18,
                color: ThreadTheme.muted,
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  _configured
                      ? 'Tailored to your ${_profile.heightCm.round()} cm profile'
                      : 'Add your height for a more personal fit',
                  style: const TextStyle(
                    fontSize: 11,
                    color: ThreadTheme.muted,
                  ),
                ),
              ),
              InkWell(
                onTap: () => _navigate(2),
                child: const Padding(
                  padding: EdgeInsets.all(6),
                  child: Icon(Icons.arrow_forward_rounded, size: 17),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            key: const Key('generate_outfits'),
            onPressed: _generate,
            icon: const Icon(Icons.auto_awesome, size: 18),
            label: const Text('Find my outfits'),
          ),
        ),
        const SizedBox(height: 10),
        const Center(
          child: Text(
            'Three combinations. A little inspiration. All you.',
            style: TextStyle(fontSize: 10, color: ThreadTheme.muted),
          ),
        ),
      ],
    ),
  );

  Widget _results() => Column(
    key: _resultsKey,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Eyebrow('04 / Finish & favorite'),
      const SizedBox(height: 10),
      Text(
        'A few ways to wear it.',
        style: Theme.of(context).textTheme.headlineMedium,
      ),
      const SizedBox(height: 8),
      Text(
        '${_shirt.name} ${_startingPiece == StartingPiece.pants ? 'pants' : 'shirt'}. '
        '${_occasion.label}. Favorite a finished look or rate it for more advice.',
        style: const TextStyle(fontSize: 13, color: ThreadTheme.muted),
      ),
      const SizedBox(height: 22),
      _outfitGrid(_outfits),
    ],
  );

  Widget _outfitGrid(List<OutfitRecommendation> outfits) => LayoutBuilder(
    builder: (context, constraints) {
      final columns = constraints.maxWidth > 950
          ? 3
          : constraints.maxWidth > 620
          ? 2
          : 1;
      final width = (constraints.maxWidth - (columns - 1) * 20) / columns;
      return Wrap(
        spacing: 20,
        runSpacing: 20,
        children: [
          for (final (index, outfit) in outfits.indexed)
            SizedBox(
              width: width,
              child: OutfitCard(
                outfit: outfit,
                index: index,
                saved: _saved.any((saved) => saved.id == outfit.id),
                onSave: () => _toggleSave(outfit),
                feedback: _voteFor(outfit),
                onFeedback: _writing ? null : (vote) => _vote(outfit, vote),
                onPlan: () => _plan(outfit),
                onRate: () => _openRating(outfit),
                wardrobeMatches: _wardrobe.isEmpty
                    ? null
                    : const WardrobeStylist().coverage(outfit, _wardrobe),
              ),
            ),
        ],
      );
    },
  );

  Widget _savedPage() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Eyebrow('Your personal collection'),
      const SizedBox(height: 12),
      Text(
        'The looks you love.',
        style: Theme.of(context).textTheme.displayMedium,
      ),
      const SizedBox(height: 12),
      Text(
        _saved.isEmpty
            ? 'A little inspiration, ready when you need it.'
            : '${_saved.length} saved ${_saved.length == 1 ? 'look' : 'looks'}. Ready for your next outing.',
        style: const TextStyle(color: ThreadTheme.muted),
      ),
      const SizedBox(height: 30),
      if (_saved.isNotEmpty)
        _outfitGrid(_saved)
      else
        SurfaceCard(
          color: ThreadTheme.softGreen,
          child: SizedBox(
            width: double.infinity,
            child: Column(
              children: [
                OutfitArt(
                  shirt: Color(_shirt.argb),
                  pants: const Color(0xFFD8C5A6),
                  shoes: const Color(0xFFF4F2EB),
                ),
                Text(
                  'Your next favorite look is waiting.',
                  style: Theme.of(context).textTheme.titleLarge,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 10),
                const Text(
                  'Create an outfit and tap the bookmark to keep it here.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: () => _navigate(0),
                  icon: const Icon(Icons.auto_awesome, size: 18),
                  label: const Text('Find my first look'),
                ),
                const SizedBox(height: 15),
              ],
            ),
          ),
        ),
    ],
  );
}
