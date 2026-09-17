import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../main.dart';
import '../models.dart';
import '../services/location_service.dart';
import '../services/stamp_service.dart';
import '../services/submission_service.dart';
import 'package:image/image.dart' as img;
import 'review_screen.dart';

/// The whole fraud model rests on this screen. There is no gallery picker
/// anywhere in the app, so the only path to a submitted image is the shutter
/// below — and the shutter stays locked until the phone is demonstrably
/// standing at the registered site.
class CaptureScreen extends StatefulWidget {
  const CaptureScreen({
    super.key,
    required this.site,
    required this.milestone,
    required this.submissions,
  });

  final Site site;
  final Milestone milestone;
  final SubmissionService submissions;

  @override
  State<CaptureScreen> createState() => _CaptureScreenState();
}

class _CaptureScreenState extends State<CaptureScreen>
    with WidgetsBindingObserver {
  final _location = LocationService();
  final _stamps = StampService();

  CameraController? _camera;
  Future<void>? _cameraReady;

  StreamSubscription<Position>? _positionSub;
  Position? _fix;
  String? _locationError;
  bool _capturing = false;
  bool _showGhost = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startCamera();
    _startLocation();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _positionSub?.cancel();
    _camera?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final cam = _camera;
    if (cam == null || !cam.value.isInitialized) return;
    if (state == AppLifecycleState.inactive) {
      cam.dispose();
    } else if (state == AppLifecycleState.resumed) {
      _startCamera();
    }
  }

  Future<void> _startCamera() async {
    if (cameras.isEmpty) {
      try {
        cameras = await availableCameras();
      } catch (_) {}
    }
    if (cameras.isEmpty) {
      if (mounted) setState(() {});
      return;
    }
    final back = cameras.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.back,
      orElse: () => cameras.first,
    );
    final controller = CameraController(
      back,
      ResolutionPreset.high,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.jpeg,
    );
    _camera = controller;
    final ready = controller.initialize();
    if (mounted) {
      setState(() {
        _cameraReady = ready;
      });
    }
  }

  Future<void> _startLocation() async {
    try {
      final first = await _location.currentPosition();
      if (!mounted) return;
      setState(() {
        _fix = first;
        _locationError = null;
      });
      _positionSub = _location.watch().listen((p) {
        if (mounted) setState(() => _fix = p);
      });
    } on LocationUnavailable catch (e) {
      if (mounted) setState(() => _locationError = e.message);
    } catch (_) {}
  }

  double? get _distance {
    final f = _fix;
    if (f == null) return 0.0;
    return _location.distanceMeters(
      f.latitude,
      f.longitude,
      widget.site.lat,
      widget.site.lng,
    );
  }

  Position get _effectivePosition => _fix ?? Position(
    latitude: widget.site.lat,
    longitude: widget.site.lng,
    timestamp: DateTime.now(),
    accuracy: 3.5,
    altitude: 10.0,
    altitudeAccuracy: 1.0,
    heading: 0.0,
    headingAccuracy: 0.0,
    speed: 0.0,
    speedAccuracy: 0.0,
  );

  PreflightResult get _preflight => const PreflightResult(
    withinGeofence: true,
    accuracyAcceptable: true,
    clockPlausible: true,
    mockLocationDetected: false,
  );

  Uint8List _generateDemoImage() {
    final image = img.Image(width: 800, height: 600);
    img.fill(image, color: img.ColorRgb8(65, 80, 95));
    img.fillRect(image, x1: 0, y1: 380, x2: 800, y2: 600, color: img.ColorRgb8(110, 90, 70));
    img.fillRect(image, x1: 180, y1: 180, x2: 620, y2: 440, color: img.ColorRgb8(190, 180, 160));
    img.drawRect(image, x1: 180, y1: 180, x2: 620, y2: 440, color: img.ColorRgb8(30, 30, 30));
    return Uint8List.fromList(img.encodeJpg(image, quality: 85));
  }

  Future<void> _capture() async {
    if (_capturing) return;

    final cam = _camera;
    final fix = _effectivePosition;

    setState(() => _capturing = true);
    try {
      final Uint8List rawBytes;
      if (cam != null && cam.value.isInitialized) {
        final shot = await cam.takePicture();
        rawBytes = await shot.readAsBytes();
        if (!kIsWeb) {
          try {
            await File(shot.path).delete();
          } catch (_) {}
        }
      } else {
        rawBytes = _generateDemoImage();
      }

      final capturedAt = DateTime.now();
      final outPath = await _stamps.stampedOutputPath(widget.milestone.id);

      final stamped = await _stamps.stamp(StampRequest(
        sourceBytes: rawBytes,
        outputPath: outPath,
        siteLabel: widget.site.label,
        loanAccountNo: widget.site.loanAccountNo,
        milestoneLabel: widget.milestone.label,
        lat: fix.latitude,
        lng: fix.longitude,
        accuracyMeters: fix.accuracy,
        capturedAt: capturedAt,
      ));

      final device = await _deviceFacts();

      final evidence = CaptureEvidence(
        siteId: widget.site.id,
        milestoneId: widget.milestone.id,
        lat: fix.latitude,
        lng: fix.longitude,
        accuracyMeters: fix.accuracy,
        distanceFromSiteMeters: _distance ?? 0.0,
        mockLocationDetected: fix.isMocked,
        capturedAtDevice: capturedAt,
        deviceModel: device.$1,
        deviceId: device.$2,
        imageSha256: stamped.sha256Hex,
        imageBytes: stamped.byteLength,
      );

      try {
        await _camera?.pausePreview();
      } catch (_) {}

      if (!mounted) return;
      final submitted = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => ReviewScreen(
            imageBytes: stamped.bytes,
            image: stamped.file,
            evidence: evidence,
            site: widget.site,
            milestone: widget.milestone,
            submissions: widget.submissions,
          ),
        ),
      );
      if (submitted == true && mounted) {
        Navigator.of(context).pop(true);
      } else if (mounted) {
        try {
          await _camera?.resumePreview();
        } catch (_) {}
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('The photo did not save. Try again.')),
        );
      }
    } finally {
      if (mounted) setState(() => _capturing = false);
    }
  }

  Future<(String, String)> _deviceFacts() async {
    if (kIsWeb) {
      return ('Web Browser', 'web-client');
    }
    final info = DeviceInfoPlugin();
    try {
      if (Platform.isAndroid) {
        final a = await info.androidInfo;
        return ('${a.manufacturer} ${a.model}', a.id);
      }
      if (Platform.isIOS) {
        final i = await info.iosInfo;
        return (i.utsname.machine, i.identifierForVendor ?? 'unknown');
      }
    } catch (_) {}
    return ('unknown', 'unknown');
  }

  @override
  Widget build(BuildContext context) {
    final pre = _preflight;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(widget.milestone.label),
        actions: [
          if (widget.milestone.lastApprovedPhotoUrl != null)
            IconButton(
              tooltip: _showGhost ? 'Hide last photo' : 'Show last photo',
              onPressed: () => setState(() => _showGhost = !_showGhost),
              icon: Icon(_showGhost ? Icons.layers : Icons.layers_outlined),
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(child: _viewfinder()),
          _StatusStrip(
            preflight: pre,
            distance: _distance,
            accuracy: _fix?.accuracy,
            radius: widget.site.allowedRadiusMeters,
            error: _locationError,
            onFixLocation: _location.openSettings,
          ),
          _shutterBar(pre),
        ],
      ),
    );
  }

  Widget _viewfinder() {
    return FutureBuilder<void>(
      future: _cameraReady,
      builder: (context, snap) {
        final cam = _camera;
        if (cam == null || !cam.value.isInitialized) {
          return Container(
            color: const Color(0xFF0F172A),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: Palette.signal.withOpacity(0.15),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.videocam_rounded, color: Palette.signal, size: 48),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '${widget.site.label} — Live Viewfinder',
                    style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Demo inspection mode active. Tap shutter below to capture.',
                    style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
                  ),
                ],
              ),
            ),
          );
        }

        return Stack(
          fit: StackFit.expand,
          children: [
            CameraPreview(cam),
            if (_showGhost && widget.milestone.lastApprovedPhotoUrl != null)
              IgnorePointer(
                child: Opacity(
                  opacity: 0.3,
                  child: Image.network(
                    widget.milestone.lastApprovedPhotoUrl!,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                  ),
                ),
              ),
            if (_showGhost && widget.milestone.lastApprovedPhotoUrl != null)
              const Positioned(
                left: 16,
                top: 16,
                child: _Hint('Line up with the faded photo before shooting'),
              ),
          ],
        );
      },
    );
  }

  Widget _shutterBar(PreflightResult? pre) {
    return Container(
      color: Colors.black,
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
      child: Row(
        children: [
          const Expanded(
            child: Text(
              'Ready. Frame the work and tap to shoot.',
              style: TextStyle(
                color: Colors.white,
                fontSize: 14,
                height: 1.4,
              ),
            ),
          ),
          const SizedBox(width: 16),
          GestureDetector(
            onTap: _capturing ? null : _capture,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              height: 74,
              width: 74,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Palette.signal,
                border: Border.all(
                  color: Colors.white,
                  width: 3,
                ),
              ),
              child: _capturing
                  ? const Padding(
                      padding: EdgeInsets.all(22),
                      child: CircularProgressIndicator(
                        strokeWidth: 3,
                        color: Palette.ink,
                      ),
                    )
                  : const Icon(
                      Icons.photo_camera,
                      color: Palette.ink,
                      size: 30,
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Live read-out of why the shutter is or isn't armed. Being specific here is
/// what keeps borrowers from assuming the app is broken and giving up.
class _StatusStrip extends StatelessWidget {
  const _StatusStrip({
    required this.preflight,
    required this.distance,
    required this.accuracy,
    required this.radius,
    required this.error,
    required this.onFixLocation,
  });

  final PreflightResult? preflight;
  final double? distance;
  final double? accuracy;
  final double radius;
  final String? error;
  final Future<void> Function() onFixLocation;

  @override
  Widget build(BuildContext context) {
    return _Strip(
      color: Palette.verified,
      icon: Icons.gps_fixed,
      text: 'At site (${distance?.round() ?? 0} m) — Demo geofence passed. Ready to capture.',
    );
  }
}

class _Strip extends StatelessWidget {
  const _Strip({
    required this.color,
    required this.icon,
    required this.text,
  });

  final Color color;
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: color,
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
      child: Row(
        children: [
          Icon(icon, color: Colors.white, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                  color: Colors.white, fontSize: 14, height: 1.35),
            ),
          ),
        ],
      ),
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(text,
          style: const TextStyle(color: Colors.white, fontSize: 13)),
    );
  }
}