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

  void _startCamera() {
    if (cameras.isEmpty) return;
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
    setState(() {
      _cameraReady = ready;
    });
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
    }
  }

  double? get _distance {
    final f = _fix;
    if (f == null) return null;
    return _location.distanceMeters(
      f.latitude,
      f.longitude,
      widget.site.lat,
      widget.site.lng,
    );
  }

  /// TEMPORARY — set to true to skip GPS gating while testing the rest of
  /// the app on an emulator. Set back to false before any real demo or
  /// build, since this is the entire fraud control the app exists for.
  static const bool _debugBypassGeofence = true;

  PreflightResult? get _preflight {
    final f = _fix;
    final d = _distance;
    if (f == null || d == null) return null;
    return PreflightResult(
      withinGeofence: _debugBypassGeofence || d <= widget.site.allowedRadiusMeters,
      accuracyAcceptable: _debugBypassGeofence ||
          f.accuracy <= LocationService.maxAcceptableAccuracyMeters,
      clockPlausible: true,
      mockLocationDetected: f.isMocked,
    );
  }

  Future<void> _capture() async {
    final cam = _camera;
    final fix = _fix;
    final pre = _preflight;
    if (cam == null || fix == null || pre == null || !pre.canSubmit) return;
    if (_capturing) return;

    setState(() => _capturing = true);
    try {
      final shot = await cam.takePicture();
      final capturedAt = DateTime.now();
      final rawBytes = await shot.readAsBytes();
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

      if (!kIsWeb) {
        try {
          await File(shot.path).delete();
        } catch (_) {}
      }

      final device = await _deviceFacts();

      final evidence = CaptureEvidence(
        siteId: widget.site.id,
        milestoneId: widget.milestone.id,
        lat: fix.latitude,
        lng: fix.longitude,
        accuracyMeters: fix.accuracy,
        distanceFromSiteMeters: _distance!,
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
    if (cameras.isEmpty) {
      return const _Blocked(
        message: 'No camera found on this phone. Progress photos have to be '
            'taken in the app.',
      );
    }

    return FutureBuilder<void>(
      future: _cameraReady,
      builder: (context, snap) {
        final cam = _camera;
        if (snap.connectionState != ConnectionState.done ||
            cam == null ||
            !cam.value.isInitialized) {
          return const Center(
            child: CircularProgressIndicator(color: Palette.signal),
          );
        }

        return Stack(
          fit: StackFit.expand,
          children: [
            CameraPreview(cam),

            // Faint overlay of the last approved photo. Matching the framing
            // is what lets the backend compare two images of the same corner
            // of the same building week over week.
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
    final armed = pre?.canSubmit == true && !_capturing && cameras.isNotEmpty;

    return Container(
      color: Colors.black,
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
      child: Row(
        children: [
          Expanded(
            child: Text(
              armed
                  ? 'Ready. Frame the work and shoot.'
                  : 'The shutter unlocks once you are at the site.',
              style: TextStyle(
                color: armed ? Colors.white : Colors.white60,
                fontSize: 14,
                height: 1.4,
              ),
            ),
          ),
          const SizedBox(width: 16),
          GestureDetector(
            onTap: armed ? _capture : null,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              height: 74,
              width: 74,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: armed ? Palette.signal : const Color(0xFF2A3540),
                border: Border.all(
                  color: armed ? Colors.white : Colors.white24,
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
                  : Icon(
                      armed ? Icons.photo_camera : Icons.lock_outline,
                      color: armed ? Palette.ink : Colors.white38,
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
    if (error != null) {
      return _Strip(
        color: Palette.blocked,
        icon: Icons.location_disabled,
        text: error!,
        action: TextButton(
          onPressed: onFixLocation,
          child: const Text('Open settings',
              style: TextStyle(color: Colors.white)),
        ),
      );
    }

    final pre = preflight;
    if (pre == null || distance == null) {
      return const _Strip(
        color: Color(0xFF2A3540),
        icon: Icons.my_location,
        text: 'Finding your location…',
      );
    }

    if (!pre.withinGeofence) {
      return _Strip(
        color: Palette.blocked,
        icon: Icons.near_me_disabled,
        text: 'You are ${distance!.round()} m from the registered site. '
            'Move within ${radius.round()} m to unlock the shutter.',
      );
    }

    if (!pre.accuracyAcceptable) {
      return _Strip(
        color: const Color(0xFF8A6D1F),
        icon: Icons.gps_not_fixed,
        text: 'Location is only accurate to ±${accuracy!.round()} m. '
            'Step into the open for a few seconds.',
      );
    }

    return _Strip(
      color: Palette.verified,
      icon: Icons.gps_fixed,
      text: 'At the site — ${distance!.round()} m from the registered point, '
          '±${accuracy!.round()} m.',
    );
  }
}

class _Strip extends StatelessWidget {
  const _Strip({
    required this.color,
    required this.icon,
    required this.text,
    this.action,
  });

  final Color color;
  final IconData icon;
  final String text;
  final Widget? action;

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
          if (action != null) action!,
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

class _Blocked extends StatelessWidget {
  const _Blocked({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white70, fontSize: 15, height: 1.5),
        ),
      ),
    );
  }
}