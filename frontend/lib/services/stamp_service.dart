import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:image/image.dart' as img;
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';

/// Inputs for the burn-in, kept as a plain value type so the whole job can be
/// handed to a background isolate. Decoding and re-encoding a 12 MP JPEG on the
/// UI isolate freezes the app for a second or more on the low-end Android
/// phones most borrowers are using.
class StampRequest {
  final String sourcePath;
  final String outputPath;
  final String siteLabel;
  final String loanAccountNo;
  final String milestoneLabel;
  final double lat;
  final double lng;
  final double accuracyMeters;
  final DateTime capturedAt;

  const StampRequest({
    required this.sourcePath,
    required this.outputPath,
    required this.siteLabel,
    required this.loanAccountNo,
    required this.milestoneLabel,
    required this.lat,
    required this.lng,
    required this.accuracyMeters,
    required this.capturedAt,
  });
}

class StampedImage {
  final File file;
  final String sha256Hex;
  final int bytes;
  const StampedImage(this.file, this.sha256Hex, this.bytes);
}

class StampService {
  /// Long edge after downscaling. Big enough for a reviewer to read rebar and
  /// brickwork, small enough to upload over a weak rural connection.
  static const int maxLongEdge = 1600;

  static const int jpegQuality = 85;

  Future<StampedImage> stamp(StampRequest req) async {
    final bytes = await Isolate.run(() => _renderStamp(req));
    final out = File(req.outputPath);
    await out.writeAsBytes(bytes, flush: true);
    return StampedImage(out, sha256.convert(bytes).toString(), bytes.length);
  }

  Future<String> stampedOutputPath(String milestoneId) async {
    final dir = await getApplicationDocumentsDirectory();
    final captures = Directory('${dir.path}/captures');
    if (!await captures.exists()) await captures.create(recursive: true);
    final ts = DateTime.now().millisecondsSinceEpoch;
    return '${captures.path}/${milestoneId}_$ts.jpg';
  }
}

/// Runs on a background isolate. Pure function of [req] — no plugin calls.
Uint8List _renderStamp(StampRequest req) {
  final raw = img.decodeImage(File(req.sourcePath).readAsBytesSync());
  if (raw == null) {
    throw const FormatException('Could not read the photo. Take it again.');
  }

  // bakeOrientation applies the EXIF rotation to the actual pixels, so the
  // stamp lands along the true bottom edge rather than sideways.
  var image = img.bakeOrientation(raw);

  if (image.width > image.height) {
    if (image.width > StampService.maxLongEdge) {
      image = img.copyResize(image, width: StampService.maxLongEdge);
    }
  } else if (image.height > StampService.maxLongEdge) {
    image = img.copyResize(image, height: StampService.maxLongEdge);
  }

  final lines = <String>[
    '${req.siteLabel}  ·  ${req.milestoneLabel}',
    'Loan ${req.loanAccountNo}',
    '${req.lat.toStringAsFixed(6)}, ${req.lng.toStringAsFixed(6)}'
        '  ±${req.accuracyMeters.round()}m',
    DateFormat('dd MMM yyyy, HH:mm:ss').format(req.capturedAt) +
        _offsetSuffix(req.capturedAt),
  ];

  // Two font sizes so the stamp stays legible on a small preview and on a
  // full-resolution review screen without hardcoding pixel sizes.
  final font = image.width >= 1000 ? img.arial24 : img.arial14;
  final lineHeight = (font.lineHeight * 1.25).round();
  final pad = (image.width * 0.02).round().clamp(8, 32);

  final bandHeight = lineHeight * lines.length + pad * 2;
  final bandTop = image.height - bandHeight;

  img.fillRect(
    image,
    x1: 0,
    y1: bandTop,
    x2: image.width,
    y2: image.height,
    color: img.ColorRgba8(12, 18, 26, 205),
  );

  // Accent rule along the top of the band — a cheap, hard-to-recreate visual
  // cue that a reviewer can spot at a glance in a grid of thumbnails.
  img.fillRect(
    image,
    x1: 0,
    y1: bandTop,
    x2: image.width,
    y2: bandTop + 3,
    color: img.ColorRgba8(232, 184, 40, 255),
  );

  var y = bandTop + pad;
  for (final line in lines) {
    img.drawString(
      image,
      line,
      font: font,
      x: pad,
      y: y,
      color: img.ColorRgba8(255, 255, 255, 255),
    );
    y += lineHeight;
  }

  return Uint8List.fromList(img.encodeJpg(image, quality: StampService.jpegQuality));
}

String _offsetSuffix(DateTime t) {
  final off = t.timeZoneOffset;
  final sign = off.isNegative ? '-' : '+';
  final h = off.inHours.abs().toString().padLeft(2, '0');
  final m = (off.inMinutes.abs() % 60).toString().padLeft(2, '0');
  return ' GMT$sign$h:$m';
}