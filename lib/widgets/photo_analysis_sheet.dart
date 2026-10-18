import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';

import '../models/style_models.dart';
import '../services/auto_photo_analyzer.dart';
import '../services/photo_analyzer.dart';

/// Local pose-based estimates with visible user confirmation and guided edits.
class PhotoAnalysisSheet extends StatefulWidget {
  const PhotoAnalysisSheet({
    super.key,
    required this.bytes,
    this.sampleSkin = false,
    this.measureBody = false,
  }) : assert(!(sampleSkin && measureBody));

  final Uint8List bytes;
  final bool sampleSkin;
  final bool measureBody;

  @override
  State<PhotoAnalysisSheet> createState() => _PhotoAnalysisSheetState();
}

class _PhotoAnalysisSheetState extends State<PhotoAnalysisSheet> {
  static const _green = Color(0xFF334D3D);
  static const _ink = Color(0xFF20352A);
  static const _steps = [
    'Tap one outer shoulder edge',
    'Tap the other outer shoulder edge',
    'Tap one waist edge',
    'Tap the other waist edge',
    'Tap one hip edge',
    'Tap the other hip edge',
  ];

  ui.Image? _image;
  Uint8List? _rgba;
  String? _error;
  String? _tapHint;
  int? _sampledArgb;
  Offset? _samplePoint;
  final List<Offset> _points = [];
  final _autoAnalyzer = AutoPhotoAnalyzer();
  bool _analyzing = false;
  bool _automaticSelection = false;
  String? _autoMessage;
  BodyShape? _autoBody;
  List<Offset> _autoBodyPoints = [];
  var _manualRevision = 0;

  @override
  void initState() {
    super.initState();
    _decode();
  }

  Future<void> _decode() async {
    ui.Codec? codec;
    ui.Image? decoded;
    try {
      final buffer = await ui.ImmutableBuffer.fromUint8List(widget.bytes);
      // Encoded ImageDescriptor dimensions are unsupported on Flutter web.
      // This cross-platform decoder supplies intrinsic dimensions and owns
      // disposal of the buffer, including when decoding fails.
      codec = await ui.instantiateImageCodecWithSize(
        buffer,
        getTargetSize: (width, height) {
          final scale = math.min(1.0, 1000 / math.max(width, height));
          return ui.TargetImageSize(
            width: math.max(1, (width * scale).round()),
            height: math.max(1, (height * scale).round()),
          );
        },
      );
      final frame = await codec.getNextFrame();
      decoded = frame.image;
      final data = await decoded.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (data == null) throw const FormatException('No readable image pixels');
      if (!mounted) return;
      final pixels = data.buffer.asUint8List(
        data.offsetInBytes,
        data.lengthInBytes,
      );
      setState(() {
        _image = decoded;
        _rgba = pixels;
      });
      decoded = null; // The widget now owns the image and disposes it below.
      unawaited(_runAutoAnalysis());
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'This photo could not be opened. Try a different photo.';
        });
      }
    } finally {
      decoded?.dispose();
      codec?.dispose();
    }
  }

  @override
  void dispose() {
    _autoAnalyzer.dispose();
    _image?.dispose();
    super.dispose();
  }

  String get _title => widget.measureBody
      ? 'A guide to your proportions'
      : widget.sampleSkin
      ? 'Find your skin tone'
      : 'Find your shirt colour';

  String get _description => widget.measureBody
      ? 'Use a straight-on photo with your arms relaxed. Check the automatic '
            'shoulder-to-hip guide, or mark the shoulders, waist and hips yourself.'
      : widget.sampleSkin
      ? 'Check the estimated face sample, or tap exposed skin in even daylight. '
            'Avoid shadows, makeup and bright highlights.'
      : 'We will locate your torso and estimate the main shirt colour. '
            'Check the sample, then tap your shirt to adjust it if needed.';

  BodyShape? get _bodyShape {
    if (_points.isEmpty && _autoBody != null) return _autoBody;
    if (_points.length != 6 || _image == null) return null;
    final widths = <double>[];
    for (var index = 0; index < 6; index += 2) {
      final first = _points[index];
      final second = _points[index + 1];
      final width = (first.dx - second.dx).abs();
      if (width < _image!.width * 0.025 ||
          (first.dy - second.dy).abs() > width * 0.35) {
        return null;
      }
      widths.add(width);
    }
    return PhotoAnalyzer.classifyProportions(
      shoulderWidth: widths[0],
      waistWidth: widths[1],
      hipWidth: widths[2],
    );
  }

  Future<void> _runAutoAnalysis() async {
    final photo = _image;
    final pixels = _rgba;
    if (photo == null || pixels == null || _analyzing) return;
    final revision = _manualRevision;
    setState(() {
      _analyzing = true;
      _autoMessage = null;
    });
    try {
      final estimate = await _autoAnalyzer.analyze(
        rgba: pixels,
        width: photo.width,
        height: photo.height,
        sampleSkin: widget.sampleSkin,
      );
      // A late model result must never overwrite the user's guided correction.
      if (!mounted || revision != _manualRevision) return;
      setState(() {
        if (widget.measureBody) {
          _autoBody = estimate.bodyShape;
          _points.clear();
          _autoBodyPoints = [
            for (final index in [5, 6, 11, 12])
              Offset(
                estimate.landmarks[index].x * photo.width,
                estimate.landmarks[index].y * photo.height,
              ),
          ];
          _automaticSelection = _autoBody != null;
          _autoMessage = _autoBody == null
              ? 'The proportions are unclear. Mark the edges yourself below.'
              : 'Estimated from shoulder and hip joints. Waist shape is not '
                    'measured; use guided points for a fuller guide.';
        } else {
          final color = widget.sampleSkin
              ? estimate.skinToneArgb
              : estimate.shirtColor?.argb;
          if (color != null) {
            _sampledArgb = color;
            final point = estimate.samplePoint;
            _samplePoint = point == null ? null : Offset(point.x, point.y);
            _automaticSelection = true;
            _tapHint = null;
            _autoMessage = widget.sampleSkin
                ? 'Estimated face sample. Check it carefully; lighting, masks '
                      'and makeup can change the colour.'
                : 'Estimated torso colour. Patterns, jackets and shadows can '
                      'affect it. Tap your shirt to correct the sample.';
          } else {
            _autoMessage =
                'The colour is unclear. Tap a plain area to sample it.';
          }
        }
      });
    } on AutoPhotoException catch (error) {
      if (mounted && revision == _manualRevision) {
        setState(() => _autoMessage = error.message);
      }
    } catch (_) {
      if (mounted && revision == _manualRevision) {
        setState(() {
          _autoMessage =
              'Automatic analysis could not finish. '
              'You can still use the guided taps.';
        });
      }
    } finally {
      if (mounted) setState(() => _analyzing = false);
    }
  }

  void _onTap(Offset local, Size canvasSize) {
    final photo = _image;
    final pixels = _rgba;
    if (photo == null || pixels == null) return;
    final pixel = PhotoAnalyzer.pixelAtContainedPosition(
      localX: local.dx,
      localY: local.dy,
      viewportWidth: canvasSize.width,
      viewportHeight: canvasSize.height,
      imageWidth: photo.width,
      imageHeight: photo.height,
    );
    if (pixel == null) return;
    final point = Offset(pixel.x.toDouble(), pixel.y.toDouble());
    if (widget.measureBody) {
      if (_points.length >= 6) return;
      setState(() {
        _manualRevision++;
        _automaticSelection = false;
        _autoMessage = null;
        _autoBody = null;
        _autoBodyPoints = [];
        _points.add(point);
        _tapHint = null;
      });
      return;
    }
    final sampled = PhotoAnalyzer.sampleRgba(
      rgba: pixels,
      width: photo.width,
      height: photo.height,
      x: point.dx.round(),
      y: point.dy.round(),
    );
    setState(() {
      _manualRevision++;
      _automaticSelection = false;
      _autoMessage = null;
      if (sampled == null) {
        _tapHint = 'That area is transparent. Tap a visible part of the photo.';
      } else {
        _sampledArgb = sampled;
        _samplePoint = point;
        _tapHint = null;
      }
    });
  }

  void _confirm() {
    if (widget.measureBody) {
      final shape = _bodyShape;
      if (shape == null) return;
      Navigator.of(context).pop(PhotoAnalysisResult(bodyShape: shape));
    } else {
      final argb = _sampledArgb;
      if (argb == null) return;
      Navigator.of(context).pop(
        widget.sampleSkin
            ? PhotoAnalysisResult(skinToneArgb: argb)
            : PhotoAnalysisResult(
                shirtColor: PhotoAnalyzer.shirtColorFor(argb),
              ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final ready = widget.measureBody
        ? _bodyShape != null
        : _sampledArgb != null;
    return Container(
      height: MediaQuery.sizeOf(context).height * 0.9,
      decoration: const BoxDecoration(
        color: Color(0xFFF7F7F2),
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 12, 22, 18),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 38,
                    height: 4,
                    decoration: BoxDecoration(
                      color: const Color(0xFFD5DCD2),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _title,
                        style: textTheme.titleLarge?.copyWith(
                          color: _ink,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      tooltip: 'Close photo',
                      icon: const Icon(Icons.close_rounded, color: _ink),
                    ),
                  ],
                ),
                Text(
                  _description,
                  style: textTheme.bodyMedium?.copyWith(
                    color: const Color(0xFF627064),
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 14),
                SizedBox(
                  height: (MediaQuery.sizeOf(context).height * 0.4).clamp(
                    160.0,
                    380.0,
                  ),
                  child: _photo(),
                ),
                const SizedBox(height: 14),
                if (_error == null) ...[
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _image == null || _analyzing
                              ? null
                              : _runAutoAnalysis,
                          icon: const Icon(
                            Icons.auto_awesome_outlined,
                            size: 18,
                          ),
                          label: Text(
                            _analyzing
                                ? 'Analyzing on this device…'
                                : 'Auto analyze',
                          ),
                        ),
                      ),
                      if (widget.measureBody && _autoBody != null) ...[
                        const SizedBox(width: 8),
                        TextButton(
                          onPressed: () => setState(() {
                            _manualRevision++;
                            _autoBody = null;
                            _automaticSelection = false;
                            _autoBodyPoints = [];
                            _points.clear();
                          }),
                          child: const Text('Mark myself'),
                        ),
                      ],
                    ],
                  ),
                  if (_analyzing) ...[
                    const SizedBox(height: 6),
                    const LinearProgressIndicator(color: _green),
                  ],
                  if (_autoMessage != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      _autoMessage!,
                      style: textTheme.bodySmall?.copyWith(
                        color: const Color(0xFF627064),
                        height: 1.35,
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  _selection(textTheme),
                  const SizedBox(height: 10),
                  Text(
                    widget.measureBody
                        ? 'A rough styling guide. Pose, clothing and perspective '
                              'affect the result. You can change it in your profile.'
                        : 'Sampled on this device. Lighting affects colour; '
                              'you can adjust your selection later.',
                    style: textTheme.bodySmall?.copyWith(
                      color: const Color(0xFF627064),
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 14),
                ],
                FilledButton(
                  onPressed: ready ? _confirm : null,
                  style: FilledButton.styleFrom(
                    backgroundColor: _green,
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(50),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(15),
                    ),
                  ),
                  child: Text(
                    widget.measureBody
                        ? 'Use these proportions'
                        : widget.sampleSkin
                        ? 'Use this skin tone'
                        : 'Use this shirt colour',
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _photo() {
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.broken_image_outlined, size: 42, color: _green),
            const SizedBox(height: 12),
            Text(_error!, textAlign: TextAlign.center),
          ],
        ),
      );
    }
    final photo = _image;
    if (photo == null) {
      return const Center(child: CircularProgressIndicator(color: _green));
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: ColoredBox(
        color: const Color(0xFFE6EAE1),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final size = Size(constraints.maxWidth, constraints.maxHeight);
            return Semantics(
              label: widget.measureBody
                  ? 'Photo. Tap the indicated body edges.'
                  : 'Photo. Tap an area to sample its colour.',
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: (details) => _onTap(details.localPosition, size),
                child: CustomPaint(
                  size: size,
                  painter: _PhotoPainter(
                    photo: photo,
                    points: widget.measureBody
                        ? (_points.isEmpty ? _autoBodyPoints : List.of(_points))
                        : [if (_samplePoint != null) _samplePoint!],
                    numbered: widget.measureBody && _points.isNotEmpty,
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _selection(TextTheme textTheme) {
    if (widget.measureBody) {
      final shape = _bodyShape;
      final complete = _points.length == 6;
      return Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: const Color(0xFFE7ECDF),
              borderRadius: BorderRadius.circular(12),
            ),
            alignment: Alignment.center,
            child: Text(
              _autoBody != null ? 'Auto' : '${_points.length}/6',
              style: const TextStyle(
                color: _green,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              shape != null
                  ? '${_automaticSelection ? 'Estimated guide' : 'Approximate guide'}: ${shape.label}'
                  : complete
                  ? 'Keep each pair level and on opposite edges. Undo to adjust.'
                  : _steps[_points.length],
              style: textTheme.bodyMedium?.copyWith(
                color: _ink,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          IconButton(
            onPressed: _points.isEmpty
                ? null
                : () => setState(() => _points.removeLast()),
            icon: const Icon(Icons.undo_rounded),
            tooltip: 'Undo last point',
            color: _green,
          ),
        ],
      );
    }
    final argb = _sampledArgb;
    return Row(
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: argb == null ? const Color(0xFFE7ECDF) : Color(argb),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFD7DDCF)),
          ),
          child: argb == null
              ? const Icon(Icons.colorize_outlined, color: _green, size: 21)
              : null,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            _tapHint ??
                (argb == null
                    ? 'Tap the photo to choose a colour'
                    : widget.sampleSkin
                    ? 'Your selected skin tone'
                    : '${_automaticSelection ? 'Estimated colour' : 'Closest colour'}: ${PhotoAnalyzer.shirtColorFor(argb).name}'),
            style: textTheme.bodyMedium?.copyWith(
              color: _ink,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

Rect _imageRect(Size canvas, Size image) {
  final fitted = applyBoxFit(BoxFit.contain, image, canvas);
  return Alignment.center.inscribe(fitted.destination, Offset.zero & canvas);
}

class _PhotoPainter extends CustomPainter {
  _PhotoPainter({
    required this.photo,
    required this.points,
    required this.numbered,
  });

  final ui.Image photo;
  final List<Offset> points;
  final bool numbered;

  @override
  void paint(Canvas canvas, Size size) {
    paintImage(
      canvas: canvas,
      rect: Offset.zero & size,
      image: photo,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.medium,
    );
    final rect = _imageRect(
      size,
      Size(photo.width.toDouble(), photo.height.toDouble()),
    );
    final positions = points
        .map(
          (point) => Offset(
            rect.left + point.dx / photo.width * rect.width,
            rect.top + point.dy / photo.height * rect.height,
          ),
        )
        .toList();
    if (numbered) {
      for (var index = 0; index + 1 < positions.length; index += 2) {
        canvas.drawLine(
          positions[index],
          positions[index + 1],
          Paint()
            ..color = Colors.white
            ..strokeWidth = 3,
        );
      }
    }
    for (var index = 0; index < positions.length; index++) {
      final point = positions[index];
      canvas.drawCircle(
        point,
        numbered ? 12 : 13,
        Paint()..color = const Color(0xFF334D3D),
      );
      canvas.drawCircle(
        point,
        numbered ? 12 : 13,
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5,
      );
      if (numbered) {
        final painter = TextPainter(
          text: TextSpan(
            text: '${index + 1}',
            style: const TextStyle(
              fontFamily: 'ThreadSans',
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        painter.paint(
          canvas,
          point - Offset(painter.width / 2, painter.height / 2),
        );
        painter.dispose();
      } else {
        canvas.drawCircle(point, 3, Paint()..color = Colors.white);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _PhotoPainter oldDelegate) =>
      photo != oldDelegate.photo ||
      numbered != oldDelegate.numbered ||
      !listEquals(points, oldDelegate.points);
}
