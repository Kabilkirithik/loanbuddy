import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';

class StampRequest {
  final Uint8List sourceBytes;
  final String outputPath;
  final String siteLabel;
  final String loanAccountNo;
  final String milestoneLabel;
  final double lat;
  final double lng;
  final double accuracyMeters;
  final DateTime capturedAt;

  const StampRequest({
    required this.sourceBytes,
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
  final Uint8List bytes;
  final File? file;
  final String sha256Hex;
  final int byteLength;

  const StampedImage({
    required this.bytes,
    this.file,
    required this.sha256Hex,
    required this.byteLength,
  });
}

class StampService {
  static const int maxLongEdge = 1600;
  static const int jpegQuality = 85;

  Future<StampedImage> stamp(StampRequest req) async {
    final Uint8List stampedBytes;
    if (kIsWeb) {
      stampedBytes = _renderStamp(req);
    } else {
      stampedBytes = await Isolate.run(() => _renderStamp(req));
    }

    File? out;
    if (!kIsWeb && req.outputPath.isNotEmpty) {
      try {
        out = File(req.outputPath);
        await out.writeAsBytes(stampedBytes, flush: true);
      } catch (_) {}
    }

    return StampedImage(
      bytes: stampedBytes,
      file: out,
      sha256Hex: sha256.convert(stampedBytes).toString(),
      byteLength: stampedBytes.length,
    );
  }

  Future<String> stampedOutputPath(String milestoneId) async {
    if (kIsWeb) return 'memory_$milestoneId.jpg';
    try {
      final dir = await getApplicationDocumentsDirectory();
      final captures = Directory('${dir.path}/captures');
      if (!await captures.exists()) await captures.create(recursive: true);
      final ts = DateTime.now().millisecondsSinceEpoch;
      return '${captures.path}/${milestoneId}_$ts.jpg';
    } catch (_) {
      return '';
    }
  }
}

/// Runs in background isolate on native, or synchronously on Web.
Uint8List _renderStamp(StampRequest req) {
  final raw = img.decodeImage(req.sourceBytes);
  if (raw == null) {
    throw const FormatException('Could not decode the photo bytes. Take it again.');
  }

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