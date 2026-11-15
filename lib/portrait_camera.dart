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
          sharpPoints + (pose ? 10 : 0)).clamp(0, 100);
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

  @override Widget build(BuildContext context) {
    final cam = _controller;
    return Scaffold(
      backgroundColor: const Color(0xFF0D2322),
      appBar: AppBar(title: const Text('دوربین هوشمند جان‌فدا'),
        backgroundColor: const Color(0xFF0D2322), foregroundColor: Colors.white,
        actions: [IconButton(tooltip: 'تعویض دوربین', onPressed: _switch,
          icon: const Icon(Icons.cameraswitch_outlined))]),
      body: SafeArea(child: Column(children: [
        Expanded(child: Container(
          margin: const EdgeInsets.all(12), clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(color: Colors.black,
            borderRadius: BorderRadius.circular(22)),
          child: Stack(fit: StackFit.expand, children: [
            if (cam != null && cam.value.isInitialized)
              Center(child: CameraPreview(cam))
            else const Center(child: CircularProgressIndicator(color: Color(0xFFC6A15A))),
            IgnorePointer(child: CustomPaint(painter: _PortraitOverlay(ready: _ready))),
            Positioned(top: 14, right: 12, left: 12,
              child: Center(child: Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(color: Colors.black.withValues(alpha: .62), borderRadius: BorderRadius.circular(25)),
                child: const Text('صورت روبه‌رو • بدون عینک تیره • نور یکنواخت',
                  style: TextStyle(color: Colors.white, fontSize: 12))))),
          ]),
        )),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
          child: AnimatedContainer(duration: const Duration(milliseconds: 220),
            width: double.infinity, padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
            decoration: BoxDecoration(color: _ready ? const Color(0xFF147D48) : const Color(0xFF483A2B),
              borderRadius: BorderRadius.circular(15)),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(_ready ? Icons.check_circle : Icons.face_outlined, color: Colors.white),
              const SizedBox(width: 9),
              Flexible(child: Text(_message, textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700))),
            ]))),
        Padding(padding: const EdgeInsets.fromLTRB(22, 5, 22, 22),
          child: SizedBox(width: double.infinity, child: FilledButton.icon(
            onPressed: _ready && !_taking ? _capture : null,
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFF188452),
              disabledBackgroundColor: Colors.grey.shade700,
              padding: const EdgeInsets.symmetric(vertical: 15)),
            icon: _taking ? const SizedBox(width: 20, height: 20,
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.camera_alt_outlined),
            label: Text(_taking ? 'در حال بررسی عکس…' : 'گرفتن عکس واضح'),
          ))),
      ])),
    );
  }
}

class _PortraitOverlay extends CustomPainter {
  const _PortraitOverlay({required this.ready});
  final bool ready;
  @override void paint(Canvas canvas, Size size) {
    final oval = Rect.fromCenter(center: Offset(size.width * 0.5, size.height * 0.47),
      width: size.width * 0.72, height: math.min(size.height * 0.66, size.width * 1.06));
    final shade = Path()..addRect(Offset.zero & size)..fillType = PathFillType.evenOdd;
    shade.addOval(oval);
    canvas.drawPath(shade, Paint()..color = Colors.black.withValues(alpha: .28));
    canvas.drawOval(oval, Paint()..style = PaintingStyle.stroke..strokeWidth = 4
      ..color = ready ? const Color(0xFF25E07B) : const Color(0xFFD9B56C));
    final center = Offset(size.width / 2, oval.bottom + 20);
    canvas.drawLine(Offset(center.dx - 32, center.dy), Offset(center.dx + 32, center.dy),
      Paint()..color = Colors.white70..strokeWidth = 2);
  }
  @override bool shouldRepaint(covariant _PortraitOverlay old) => old.ready != ready;
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
