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
  bool _showMoreOutfits = false;
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
    _showMoreOutfits = false;
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
    setState(() {
      if (step == 1 && _matchingColor == null) {
        _matchingColor = const StyleEngine()
            .matchingColors(
              startingPiece: _startingPiece,
              color: _shirt,
              profile: _profile,
            )
            .first;
      }
      _studioStep = step;
    });
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
    _goToStep(1);
    _message('Starting with ${item.name}. A matching color is ready.');
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
      _showMoreOutfits = false;
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
    return PopScope<void>(
      canPop: _page == 0 && _studioStep == 0,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (_page == 2 || _page == 3 || _page == 4) {
          _navigate(5);
        } else if (_page != 0) {
          _navigate(0);
        } else if (_studioStep > 0) {
          _goToStep(_studioStep - 1);
        }
      },
      child: Scaffold(
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
                          wide ? 28 : 16,
                          wide ? 42 : 20,
                          40,
                        ),
                        child: Center(
                          child: ConstrainedBox(
                            constraints: BoxConstraints(
                              maxWidth: _page == 0 || _page == 2 || _page == 5
                                  ? 730
                                  : 1160,
                            ),
                            child: switch (_page) {
                              1 => _savedPage(),
                              5 => _morePage(),
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
                selectedIndex: _page < 2 ? _page : 2,
                onDestinationSelected: (index) =>
                    _navigate(index == 2 ? 5 : index),
                backgroundColor: Colors.white,
                indicatorColor: ThreadTheme.lime,
                labelTextStyle: const WidgetStatePropertyAll(
                  TextStyle(fontSize: 10),
                ),
                destinations: const [
                  NavigationDestination(
                    icon: Icon(Icons.auto_awesome_outlined),
                    selectedIcon: Icon(Icons.auto_awesome),
                    label: 'Outfits',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.favorite_border),
                    selectedIcon: Icon(Icons.favorite),
                    label: 'Saved',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.more_horiz),
                    label: 'More',
                  ),
                ],
              ),
      ),
    );
  }

  Widget _header(bool wide) => Container(
    padding: EdgeInsets.symmetric(horizontal: wide ? 44 : 22, vertical: 8),
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
            (0, 'Outfits'),
            (1, 'Saved'),
            (5, 'More'),
          ])
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: TextButton(
                style: TextButton.styleFrom(
                  backgroundColor: (_page == index || (index == 5 && _page > 1))
                      ? ThreadTheme.softGreen
                      : null,
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

  Widget _morePage() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('Make it yours', style: Theme.of(context).textTheme.headlineMedium),
      const SizedBox(height: 8),
      const Text('Your profile, wardrobe and plans, whenever you need them.'),
      const SizedBox(height: 20),
      SurfaceCard(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          children: [
            ListTile(
              leading: const Icon(Icons.person_outline),
              title: const Text('My profile'),
              subtitle: Text(
                _configured
                    ? 'Your height, skin tone and fit preferences'
                    : 'Add your height and fit preferences',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _navigate(2),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.checkroom_outlined),
              title: const Text('Wardrobe'),
              subtitle: const Text('Create looks with clothes you own'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _navigate(4),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.calendar_month_outlined),
              title: const Text('Planner'),
              subtitle: const Text('Outfits for upcoming days'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _navigate(3),
            ),
          ],
        ),
      ),
    ],
  );

  Widget _studio(bool wide) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Wrap(
        spacing: 16,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            'Build an outfit',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          TextButton.icon(
            key: const Key('open_outfit_rating'),
            onPressed: () => _openRating(),
            icon: const Icon(Icons.star_outline_rounded, size: 20),
            label: const Text('Rate outfit'),
          ),
        ],
      ),
      const SizedBox(height: 12),
      _studioProgress(),
      const SizedBox(height: 16),
      if (_studioStep == 0)
        _shirtPanel()
      else if (_studioStep == 1)
        _matchingPanel()
      else if (_studioStep == 2)
        _occasionPanel()
      else if (_generated)
        _results(),
      if (_studioStep < 2) ...[
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            key: const Key('studio_next'),
            onPressed: () => _goToStep(_studioStep + 1),
            icon: const Icon(Icons.arrow_forward_rounded),
            label: Text(
              _studioStep == 0 ? 'Find matching colors' : 'Choose occasion',
            ),
          ),
        ),
      ],
      const SizedBox(height: 16),
      ExpansionTile(
        key: const Key('studio_personalization'),
        tilePadding: EdgeInsets.zero,
        title: const Text('More options'),
        subtitle: const Text('Style, weather and trends'),
        children: [
          _contextPanels(wide),
          const SizedBox(height: 16),
          TrendPanel(onSelected: _setDirection),
          const SizedBox(height: 16),
        ],
      ),
    ],
  );

  Widget _studioProgress() => _studioStep == 3
      ? Wrap(
          spacing: 12,
          runSpacing: 8,
          children: [
            TextButton.icon(
              key: const Key('studio_back'),
              onPressed: () => _goToStep(2),
              icon: const Icon(Icons.arrow_back),
              label: const Text('Edit occasion'),
            ),
            TextButton(
              key: const Key('start_new_outfit'),
              onPressed: () => _goToStep(0),
              child: const Text('Start again'),
            ),
          ],
        )
      : Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (_studioStep > 0) ...[
                  IconButton(
                    key: const Key('studio_back'),
                    tooltip: 'Back',
                    onPressed: () => _goToStep(_studioStep - 1),
                    icon: const Icon(Icons.arrow_back),
                  ),
                  const SizedBox(width: 4),
                ],
                Expanded(
                  child: Text(
                    '${_studioStep + 1} of 3 · ${['Your starting piece', 'Matching color', 'Occasion'][_studioStep]}',
                    style: const TextStyle(
                      color: ThreadTheme.muted,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            if (_studioStep < 3) ...[
              const SizedBox(height: 8),
              LinearProgressIndicator(
                value: (_studioStep + 1) / 3,
                minHeight: 3,
                backgroundColor: ThreadTheme.line,
                borderRadius: BorderRadius.circular(3),
              ),
            ],
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
          Text(
            'Choose your $other color',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 10),
          Text(
            'Keeping your ${_shirt.name.toLowerCase()} ${_startingPiece == StartingPiece.pants ? 'pants' : 'shirt'}. A suggested match is selected; change it if you like.',
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
              '${_matchingColor!.name} $other selected',
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

  Widget _shirtPanel() => SurfaceCard(
    padding: const EdgeInsets.all(18),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'What are you starting with?',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 10),
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
        const SizedBox(height: 12),
        Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Container(
                width: 72,
                height: 72,
                color: ThreadTheme.softGreen,
                child: _photo == null
                    ? GarmentArt(
                        kind: _startingPiece == StartingPiece.pants
                            ? GarmentKind.pants
                            : GarmentKind.shirt,
                        color: Color(_shirt.argb),
                        size: 70,
                      )
                    : Image.memory(
                        _photo!,
                        fit: BoxFit.contain,
                        cacheWidth: 180,
                      ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${_shirt.name} ${_startingPiece.itemLabel.toLowerCase()}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Choose its color below.',
                    style: TextStyle(color: ThreadTheme.muted),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 2,
          runSpacing: 2,
          children: [
            for (final color in ShirtColor.presets)
              Semantics(
                button: true,
                selected: _shirt.argb == color.argb,
                label:
                    '${color.name} ${_startingPiece.itemLabel.toLowerCase()}',
                child: Tooltip(
                  message: color.name,
                  child: InkWell(
                    key: Key('starting_color_${color.name}'),
                    onTap: () => _chooseAnchor(color),
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
                              color: _shirt.argb == color.argb
                                  ? ThreadTheme.green
                                  : Colors.black12,
                              width: _shirt.argb == color.argb ? 2 : 1,
                            ),
                          ),
                          child: _shirt.argb == color.argb
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
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            TextButton.icon(
              key: const Key('add_photo'),
              onPressed: _picking ? null : () => _pickPhoto(),
              icon: const Icon(Icons.add_a_photo_outlined, size: 18),
              label: Text(_picking ? 'Opening photo…' : 'Use a photo'),
            ),
            IconButton(
              tooltip: 'Choose from gallery',
              onPressed: _picking
                  ? null
                  : () => _pickPhoto(source: ImageSource.gallery),
              icon: const Icon(Icons.photo_library_outlined, size: 20),
            ),
          ],
        ),
      ],
    ),
  );

  Widget _occasionPanel() => SurfaceCard(
    padding: const EdgeInsets.all(18),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Where are you headed?',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        Text(
          '${_shirt.name} ${_startingPiece == StartingPiece.pants ? 'pants' : 'shirt'} + '
          '${_matchingColor?.name ?? ''} ${_startingPiece == StartingPiece.pants ? 'top' : 'pants'}. '
          '',
          style: const TextStyle(fontSize: 12, color: ThreadTheme.muted),
        ),
        const SizedBox(height: 18),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            for (final occasion in Occasion.values)
              ChoiceChip(
                key: ValueKey('occasion_${occasion.name}'),
                avatar: Icon(occasionIcon(occasion), size: 17),
                label: Text(occasion.label),
                selected: occasion == _occasion,
                onSelected: (_) => _invalidate(() => _occasion = occasion),
              ),
          ],
        ),
        const SizedBox(height: 15),
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: const Text(
            'Include a layer',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
          ),
          value: _includeLayer,
          onChanged: (value) => _invalidate(() => _includeLayer = value),
        ),
        const SizedBox(height: 8),
        const SizedBox(height: 18),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            key: const Key('generate_outfits'),
            onPressed: _generate,
            icon: const Icon(Icons.auto_awesome, size: 18),
            label: const Text('Show my outfit'),
          ),
        ),
      ],
    ),
  );

  Widget _results() => Column(
    key: _resultsKey,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        '${_occasion.label} · ${_shirt.name} ${_startingPiece.itemLabel.toLowerCase()}',
        style: const TextStyle(color: ThreadTheme.muted),
      ),
      const SizedBox(height: 12),
      _outfitGrid(_showMoreOutfits ? _outfits : _outfits.take(1).toList()),
      if (_outfits.length > 1 && !_showMoreOutfits) ...[
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            key: const Key('show_more_outfits'),
            onPressed: () => setState(() => _showMoreOutfits = true),
            child: Text('Show ${_outfits.length - 1} more outfits'),
          ),
        ),
      ],
    ],
  );

  Widget _outfitGrid(List<OutfitRecommendation> outfits) => LayoutBuilder(
    builder: (context, constraints) {
      final columns = outfits.length == 1
          ? 1
          : constraints.maxWidth > 950
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
                  'Create an outfit and tap Favorite outfit to keep it here.',
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
