import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;

/// Guided portrait camera: detects a face, framing, light and image sharpness
/// entirely on the device. This is NOT face identification or authentication.
class PortraitCamera extends StatefulWidget {
  const PortraitCamera({super.key});
  @override State<PortraitCamera> createState() => _PortraitCameraState();
}

class _PortraitCameraState extends State<PortraitCamera> with WidgetsBindingObserver {
  CameraController? _controller;
  late final FaceDetector _detector = FaceDetector(
    options: FaceDetectorOptions(performanceMode: FaceDetectorMode.fast,
      enableLandmarks: false, enableContours: false, minFaceSize: 0.18),
  );
  List<CameraDescription> _available = [];
  CameraDescription? _selected;
  String _message = 'در حال آماده‌سازی دوربین…';
  bool _processing = false, _taking = false, _ready = false, _disposed = false;
  int _goodFrames = 0;
  int _qualityPercent = 0;
  bool _faceOk = false, _framingOk = false, _lightOk = false, _sharpOk = false, _poseOk = false;
  bool _guideExpanded = false;
  DateTime _lastFrame = DateTime(2000);

  static const _rotations = <DeviceOrientation, int>{
    DeviceOrientation.portraitUp: 0,
    DeviceOrientation.landscapeLeft: 90,
    DeviceOrientation.portraitDown: 180,
    DeviceOrientation.landscapeRight: 270,
  };

  @override void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initialize();
  }

  Future<void> _initialize({CameraLensDirection? preferred}) async {
    try {
      _available = await availableCameras();
      if (_available.isEmpty) throw CameraException('no_camera', 'دوربین در دستگاه یافت نشد.');
      final wanted = preferred ?? CameraLensDirection.front;
      _selected = _available.firstWhere((c) => c.lensDirection == wanted,
        orElse: () => _available.first);
      final cam = CameraController(_selected!, ResolutionPreset.high,
        enableAudio: false, imageFormatGroup: ImageFormatGroup.nv21);
      _controller = cam;
      await cam.initialize();
      await cam.lockCaptureOrientation(DeviceOrientation.portraitUp);
      if (_disposed) { await cam.dispose(); return; }
      await cam.startImageStream(_onFrame);
      if (mounted) setState(() => _message = 'صورت را در کادر قرار دهید.');
    } catch (e) {
      if (mounted) setState(() => _message = 'راه‌اندازی دوربین ممکن نشد؛ دسترسی دوربین را بررسی کنید.');
    }
  }

  Future<void> _switch() async {
    if (_taking || _available.length < 2) return;
    final next = _selected?.lensDirection == CameraLensDirection.front
        ? CameraLensDirection.back : CameraLensDirection.front;
    setState(() { _ready = false; _goodFrames = 0; _qualityPercent = 0; _message = 'در حال تعویض دوربین…'; });
    final previous = _controller;
    _controller = null;
    if (previous != null) {
      try { if (previous.value.isStreamingImages) await previous.stopImageStream(); } catch (_) {}
      await previous.dispose();
    }
    if (mounted) await _initialize(preferred: next);
  }

  void _onFrame(CameraImage frame) {
    if (_processing || _taking || _disposed || DateTime.now().difference(_lastFrame).inMilliseconds < 350) return;
    _processing = true;
    _lastFrame = DateTime.now();
    _inspect(frame).whenComplete(() => _processing = false);
  }

  Future<void> _inspect(CameraImage frame) async {
    final cam = _controller;
    final selected = _selected;
    if (cam == null || selected == null) return;
    try {
      // NV21 is required by ML Kit for CameraImage byte streams on Android.
      final format = InputImageFormatValue.fromRawValue(frame.format.raw);
      if (format == null || format != InputImageFormat.nv21 || frame.planes.length != 1) {
        _qualityUpdate(0, false, false, false, false, false, 'تحلیل زنده با این دوربین سازگار نیست؛ دوربین دیگری را امتحان کنید.');
        return;
      }
      final compensation = _rotations[cam.value.deviceOrientation] ?? 0;
      final rotationDegrees = selected.lensDirection == CameraLensDirection.front
          ? (selected.sensorOrientation + compensation) % 360
          : (selected.sensorOrientation - compensation + 360) % 360;
      final rotation = InputImageRotationValue.fromRawValue(rotationDegrees);
      if (rotation == null) return;
      final plane = frame.planes.first;
      final input = InputImage.fromBytes(bytes: plane.bytes,
        metadata: InputImageMetadata(
          size: Size(frame.width.toDouble(), frame.height.toDouble()),
          rotation: rotation, format: format, bytesPerRow: plane.bytesPerRow));
      final faces = await _detector.processImage(input);
      if (faces.length != 1) {
        _qualityUpdate(0, false, false, false, false, false,
          faces.isEmpty ? 'چهره در تصویر پیدا نشد؛ صورت را داخل بیضی قرار دهید.' : 'فقط یک چهره در کادر دیده شود.');
        return;
      }
      final b = faces.first.boundingBox;
      final rotated = rotationDegrees == 90 || rotationDegrees == 270;
      final width = rotated ? frame.height.toDouble() : frame.width.toDouble();
      final height = rotated ? frame.width.toDouble() : frame.height.toDouble();
      final cx = b.center.dx / width, cy = b.center.dy / height;
      final faceWidth = b.width / width, faceHeight = b.height / height;
      final framing = (cx - 0.5).abs() <= 0.19 &&
          (cy - 0.47).abs() <= 0.21 &&
          faceWidth >= 0.20 && faceWidth <= 0.83 &&
          faceHeight >= 0.23 && faceHeight <= 0.86;
      final turn = faces.first.headEulerAngleY?.abs() ?? 0.0;
      final tilt = faces.first.headEulerAngleZ?.abs() ?? 0.0;
      final pose = turn <= 18 && tilt <= 16;
      final light = FrameQuality.fromNv21(frame);
      final wellLit = light.brightness >= 55 && light.brightness <= 214;
      final sharp = light.edgeEnergy >= 68;
      final proximity = math.max((cx - 0.5).abs() / .19, (cy - .47).abs() / .21);
      final framePoints = framing ? 25 : (25 * (1 - math.min(1.0, proximity / 2))).round();
      final brightnessPoints = wellLit ? 20 : (
        light.brightness >= 40 && light.brightness <= 230 ? 8 : 0);
      final sharpPoints = (20 * (light.edgeEnergy / 100).clamp(0.0, 1.0)).round();
      final total = (25 + framePoints + brightnessPoints +
          sharpPoints + (pose ? 10 : 0)).clamp(0, 100).toInt();
      final passes = framing && pose && wellLit && sharp && total >= 85;
      String guidance;
      if (!framing) {
        guidance = 'صورت را در مرکز بیضی و با فاصله مناسب قرار دهید.';
      } else if (!pose) {
        guidance = 'روبه‌روی دوربین بایستید و سر را صاف نگه دارید.';
      } else if (light.brightness < 55) {
        guidance = 'نور کم است؛ روبه‌روی نور ملایم قرار بگیرید.';
      } else if (light.brightness > 214) {
        guidance = 'نور زیاد است؛ از نور مستقیم فاصله بگیرید.';
      } else if (!sharp) {
        guidance = 'کمی ثابت بمانید تا تصویر واضح شود.';
      } else {
        guidance = 'کیفیت مناسب است؛ برای ثبت عکس آماده شوید.';
      }
      _qualityUpdate(total, true, framing, wellLit, sharp, pose, guidance, passes: passes);
    } catch (_) {
      _qualityUpdate(0, false, false, false, false, false,
        'بررسی تصویر انجام نشد؛ دوباره تلاش کنید.');
    }
  }

  void _qualityUpdate(int quality, bool face, bool framed, bool light,
      bool sharp, bool pose, String message, {bool passes = false}) {
    if (!mounted || _disposed) return;
    _goodFrames = passes ? math.min(_goodFrames + 1, 4) : 0;
    final ready = _goodFrames >= 3;
    setState(() {
      _qualityPercent = quality;
      _faceOk = face;
      _framingOk = framed;
      _lightOk = light;
      _sharpOk = sharp;
      _poseOk = pose;
      _ready = ready;
      _message = ready ? 'چهره واضح است؛ می‌توانید عکس بگیرید.' : message;
    });
  }

  Future<void> _capture() async {
    final cam = _controller;
    if (!_ready || _taking || cam == null || !cam.value.isInitialized) return;
    setState(() => _taking = true);
    XFile? file;
    try {
      if (cam.value.isStreamingImages) await cam.stopImageStream();
      file = await cam.takePicture();
      final raw = await file.readAsBytes();
      final decoded = img.decodeImage(raw);
      if (decoded == null) throw const FormatException('فایل تصویر قابل خواندن نیست.');
      final corrected = img.bakeOrientation(decoded);
      final fitted = corrected.width > 1400 ? img.copyResize(corrected, width: 1400) : corrected;
      final quality = FrameQuality.fromRgb(fitted);
      final faces = await _detector.processImage(InputImage.fromFilePath(file.path));
      if (faces.length != 1 || quality.edgeEnergy < 42 || quality.brightness < 40 || quality.brightness > 224) {
        throw const FormatException('عکس نهایی واضح نیست یا چهره کامل دیده نمی‌شود؛ دوباره عکس بگیرید.');
      }
      final jpeg = Uint8List.fromList(img.encodeJpg(fitted, quality: 84));
      if (jpeg.length > 5 * 1024 * 1024) throw const FormatException('حجم عکس بیش از ۵ مگابایت است.');
      if (mounted) Navigator.of(context).pop(jpeg);
    } catch (e) {
      if (mounted) {
        setState(() { _ready = false; _goodFrames = 0; _qualityPercent = 0; _message = e.toString().replaceFirst('FormatException: ', ''); });
        try { if (!cam.value.isStreamingImages) await cam.startImageStream(_onFrame); } catch (_) {}
      }
    } finally {
      // Camera plugin writes a temporary unencrypted photo; discard after reading.
      if (file != null) { try { await File(file.path).delete(); } catch (_) {} }
      if (mounted) setState(() => _taking = false);
    }
  }

  @override void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive) {
      _ready = false;
      final old = _controller;
      _controller = null;
      if (old != null) {
        () async { try { if (old.value.isStreamingImages) await old.stopImageStream(); } catch (_) {} await old.dispose(); }();
      }
    } else if (state == AppLifecycleState.resumed && _controller == null && !_disposed) {
      _initialize(preferred: _selected?.lensDirection);
    }
  }

  @override void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    final cam = _controller;
    if (cam != null) {
      () async { try { if (cam.value.isStreamingImages) await cam.stopImageStream(); } catch (_) {} await cam.dispose(); }();
    }
    _detector.close();
    super.dispose();
  }

  Widget _chip(IconData icon, String title, bool ok) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
    decoration: BoxDecoration(
      color: ok ? const Color(0xFFE3F3E9) : const Color(0xFFF0EAE0),
      borderRadius: BorderRadius.circular(12)),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 16, color: ok ? const Color(0xFF117847) : const Color(0xFF9B7E4A)),
      const SizedBox(width: 4),
      Text(title, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
        color: ok ? const Color(0xFF135443) : const Color(0xFF625949))),
      const SizedBox(width: 4),
      Icon(ok ? Icons.check_circle : Icons.radio_button_unchecked, size: 14,
        color: ok ? const Color(0xFF168D54) : Colors.grey),
    ]),
  );

  @override Widget build(BuildContext context) {
    final cam = _controller;
    return Scaffold(
      backgroundColor: const Color(0xFFF8F2E9),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF8F2E9),
        foregroundColor: const Color(0xFF0B4D40),
        centerTitle: true,
        title: const Column(mainAxisSize: MainAxisSize.min, children: [
          Text('جان فدا | وارثین', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
          Text('دوربین هوشمند ثبت چهره', style: TextStyle(fontSize: 11)),
        ]),
        actions: [IconButton(tooltip: 'تعویض دوربین', onPressed: _switch,
          icon: const Icon(Icons.cameraswitch_outlined))]),
      body: SafeArea(child: LayoutBuilder(builder: (context, limits) {
        final compact = limits.maxHeight < 660;
        return Column(children: [
          Expanded(child: Container(
            margin: const EdgeInsets.fromLTRB(12, 8, 12, 6),
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: const Color(0xFF132D28),
              borderRadius: BorderRadius.circular(20)),
            child: Stack(fit: StackFit.expand, children: [
              if (cam != null && cam.value.isInitialized)
                Center(child: CameraPreview(cam))
              else const Center(child: CircularProgressIndicator(color: Color(0xFFCAA865))),
              IgnorePointer(child: CustomPaint(
                painter: _PortraitOverlay(ready: _ready, score: _qualityPercent))),
              Positioned(top: 10, right: 10, left: 10, child: Align(
                alignment: Alignment.centerRight,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: .70),
                    borderRadius: BorderRadius.circular(20)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.auto_awesome_outlined, size: 16,
                      color: _ready ? const Color(0xFF4BEE8A) : const Color(0xFFD8B66E)),
                    const SizedBox(width: 6),
                    const Text('سنجش زنده کیفیت چهره',
                      style: TextStyle(color: Colors.white, fontSize: 11)),
                  ]),
                ),
              )),
              Positioned(bottom: 10, right: 10, left: 10, child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: .64),
                    borderRadius: BorderRadius.circular(12)),
                  child: const Text('صورت روبه‌روی دوربین، درون بیضی و با نور یکنواخت',
                    maxLines: 2, textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 11, color: Colors.white)),
                ),
              )),
            ]),
          )),
          Padding(padding: const EdgeInsets.fromLTRB(14, 4, 14, 4),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              decoration: BoxDecoration(
                color: const Color(0xFF075648),
                borderRadius: BorderRadius.circular(17)),
              padding: const EdgeInsets.all(12),
              child: Column(children: [
                Row(children: [
                  Icon(_ready ? Icons.check_circle : Icons.face_retouching_natural,
                    color: _ready ? const Color(0xFF61F49A) : const Color(0xFFE3C281)),
                  const SizedBox(width: 8),
                  const Expanded(child: Text('کیفیت تصویر',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800))),
                  Text('$_qualityPercent٪',
                    textDirection: TextDirection.ltr,
                    style: const TextStyle(color: Colors.white,
                      fontWeight: FontWeight.w900, fontSize: 22)),
                ]),
                const SizedBox(height: 8),
                ClipRRect(borderRadius: BorderRadius.circular(10),
                  child: LinearProgressIndicator(
                    minHeight: 9, value: _qualityPercent / 100,
                    backgroundColor: const Color(0xFF64867A),
                    valueColor: AlwaysStoppedAnimation<Color>(
                      _ready ? const Color(0xFF4CF08D) : const Color(0xFFE4BA6A)),
                  )),
                const SizedBox(height: 8),
                Text(_message, textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontSize: 12)),
              ]),
            ),
          ),
          Padding(padding: const EdgeInsets.fromLTRB(10, 5, 10, 3),
            child: Wrap(spacing: 6, runSpacing: 6, alignment: WrapAlignment.center,
              children: [
                _chip(Icons.face_outlined, 'چهره شناسایی شد', _faceOk),
                _chip(Icons.center_focus_strong, 'داخل کادر', _framingOk),
                _chip(Icons.light_mode_outlined, 'نور مناسب', _lightOk),
                _chip(Icons.high_quality_outlined, 'تصویر واضح', _sharpOk),
                _chip(Icons.visibility_outlined, 'نگاه مستقیم', _poseOk),
              ]),
          ),
          Padding(padding: const EdgeInsets.fromLTRB(12, 2, 12, 1),
            child: TextButton.icon(
              onPressed: () => setState(() => _guideExpanded = !_guideExpanded),
              icon: Icon(_guideExpanded ? Icons.expand_less : Icons.tips_and_updates_outlined,
                size: 19),
              label: Text(_guideExpanded ? 'بستن راهنمای عکاسی'
                : 'راهنمای عکاسی: نور ملایم، گوشی ثابت، صورت در کادر'),
            ),
          ),
          if (_guideExpanded) Container(
            margin: const EdgeInsets.fromLTRB(14, 1, 14, 4),
            padding: const EdgeInsets.all(10),
            width: double.infinity,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12)),
            child: Text(
              '۱. مقابل نور ملایم و یکنواخت بایستید.\n'
              '۲. صورت را کاملاً در بیضی قرار دهید و مستقیم نگاه کنید.\n'
              '۳. گوشی را ثابت نگه دارید و در صورت امکان عینک تیره را بردارید.\n'
              '۴. وقتی رنگ کادر سبز شد و دکمه فعال بود، عکس بگیرید.',
              style: TextStyle(fontSize: compact ? 10 : 12, height: 1.55,
                color: const Color(0xFF19483E)),
            ),
          ),
          Padding(padding: const EdgeInsets.fromLTRB(14, 5, 14, 12),
            child: SizedBox(width: double.infinity, child: FilledButton.icon(
              onPressed: _ready && !_taking ? _capture : null,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF08604B),
                disabledBackgroundColor: const Color(0xFFB5B8B2),
                padding: const EdgeInsets.symmetric(vertical: 15),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
              icon: _taking
                ? const SizedBox(width: 20, height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.camera_alt_outlined),
              label: Text(_taking ? 'در حال بررسی عکس…'
                : (_ready ? 'گرفتن عکس' : 'تا سبزشدن کامل کادر صبر کنید')),
            )),
          ),
        ]);
      })),
    );
  }
}

class _PortraitOverlay extends CustomPainter {
  const _PortraitOverlay({required this.ready, required this.score});
  final bool ready;
  final int score;
  @override void paint(Canvas canvas, Size size) {
    final oval = Rect.fromCenter(
      center: Offset(size.width * .5, size.height * .47),
      width: size.width * .72,
      height: math.min(size.height * .66, size.width * 1.06));
    final mask = Path()..addRect(Offset.zero & size)
      ..fillType = PathFillType.evenOdd;
    mask.addOval(oval);
    canvas.drawPath(mask, Paint()..color = Colors.black.withValues(alpha: .24));
    canvas.drawOval(oval, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.5
      ..color = const Color(0xAADDCC8A));
    if (ready) {
      canvas.drawOval(oval, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5
        ..color = const Color(0xFF47F58A));
    } else {
      canvas.drawArc(oval, -math.pi / 2, math.pi * 2 * (score / 100),
        false, Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = 5
          ..color = score >= 75 ? const Color(0xFF79DA88)
            : const Color(0xFFDDAD57));
    }
  }
  @override bool shouldRepaint(covariant _PortraitOverlay old) =>
    old.ready != ready || old.score != score;
}

class FrameQuality {
  const FrameQuality(this.brightness, this.edgeEnergy);
  final double brightness;
  final double edgeEnergy;

  static FrameQuality fromNv21(CameraImage frame) {
    final y = frame.planes.first.bytes;
    final stride = frame.planes.first.bytesPerRow;
    return _sample(frame.width, frame.height, (x, yy) => y[yy * stride + x]);
  }

  static FrameQuality fromRgb(img.Image rgb) => _sample(rgb.width, rgb.height,
    (x, y) => ((rgb.getPixel(x, y).r * 77 + rgb.getPixel(x, y).g * 150 +
      rgb.getPixel(x, y).b * 29) / 256).round());

  static FrameQuality _sample(int w, int h, int Function(int x, int y) lum) {
    if (w < 24 || h < 24) return const FrameQuality(0, 0);
    var bright = 0.0, edges = 0.0, count = 0;
    final xStart = w ~/ 4, xEnd = w * 3 ~/ 4;
    final yStart = h ~/ 4, yEnd = h * 3 ~/ 4;
    final step = math.max(2, math.min(w, h) ~/ 95);
    for (var y = yStart + step; y < yEnd - step; y += step) {
      for (var x = xStart + step; x < xEnd - step; x += step) {
        final p = lum(x, y);
        bright += p;
        final lap = 4 * p - lum(x + step, y) - lum(x - step, y)
          - lum(x, y + step) - lum(x, y - step);
        edges += lap * lap;
        count++;
      }
    }
    return FrameQuality(bright / math.max(1, count), edges / math.max(1, count));
  }
}
