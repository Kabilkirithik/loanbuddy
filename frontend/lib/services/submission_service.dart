import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../models.dart';

enum SubmissionState { queued, uploading, submitted, failed }

class SubmissionResult {
  final SubmissionState state;
  final String? serverRef;
  final String? message;
  final String? status;
  final InspectionReport? report;

  const SubmissionResult(
    this.state, {
    this.serverRef,
    this.message,
    this.status,
    this.report,
  });
}

/// Sends a stamped capture plus its evidence to the verification backend.
class SubmissionService {
  SubmissionService({required this.baseUrl, required this.authToken});

  final String baseUrl;
  final String authToken;

  Future<SubmissionResult> submit(
    Uint8List imageBytes,
    CaptureEvidence evidence, {
    File? image,
  }) async {
    try {
      final req = http.MultipartRequest(
        'POST',
        Uri.parse('$baseUrl/v1/captures'),
      )
        ..headers['Authorization'] = 'Bearer $authToken'
        ..headers['X-Image-SHA256'] = evidence.imageSha256
        ..fields['evidence'] = evidence.toJsonString()
        ..files.add(
          http.MultipartFile.fromBytes(
            'image',
            imageBytes,
            filename: 'capture.jpg',
          ),
        );

      final res = await http.Response.fromStream(
        await req.send().timeout(const Duration(seconds: 90)),
      );

      if (res.statusCode == 201 || res.statusCode == 200) {
        final body = jsonDecode(res.body) as Map<String, dynamic>;
        final reportMap = body['report'] as Map<String, dynamic>?;
        return SubmissionResult(
          SubmissionState.submitted,
          serverRef: body['capture_ref'] as String?,
          status: body['status'] as String?,
          report: reportMap != null ? InspectionReport.fromJson(reportMap) : null,
        );
      }

      if (res.statusCode == 409) {
        return const SubmissionResult(
          SubmissionState.failed,
          message: 'This photo has already been submitted. Take a new one.',
        );
      }

      if (res.statusCode >= 500) {
        await _enqueue(imageBytes, evidence, image: image);
        return const SubmissionResult(
          SubmissionState.queued,
          message: 'Saved. It will be sent when the server is back.',
        );
      }

      return SubmissionResult(
        SubmissionState.failed,
        message: _serverMessage(res.body) ?? 'Submission was not accepted.',
      );
    } catch (_) {
      await _enqueue(imageBytes, evidence, image: image);
      return const SubmissionResult(
        SubmissionState.queued,
        message: 'Saved and will be sent automatically.',
      );
    }
  }

  Future<int> flushQueue() async {
    if (kIsWeb) return 0;
    try {
      final dir = await _queueDir();
      final pending = dir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.json'))
          .toList();

      var sent = 0;
      for (final manifest in pending) {
        try {
          final j = jsonDecode(await manifest.readAsString()) as Map<String, dynamic>;
          final image = File(j['image_path'] as String);
          if (!await image.exists()) {
            await manifest.delete();
            continue;
          }
          final bytes = await image.readAsBytes();
          final result = await submit(bytes, _evidenceFrom(j['evidence']), image: image);
          if (result.state == SubmissionState.submitted) {
            await manifest.delete();
            sent++;
          }
        } catch (_) {}
      }
      return sent;
    } catch (_) {
      return 0;
    }
  }

  Future<int> pendingCount() async {
    if (kIsWeb) return 0;
    try {
      return (await _queueDir()).listSync().whereType<File>().where((f) => f.path.endsWith('.json')).length;
    } catch (_) {
      return 0;
    }
  }

  Future<void> _enqueue(Uint8List imageBytes, CaptureEvidence evidence, {File? image}) async {
    if (kIsWeb || image == null) return;
    try {
      final dir = await _queueDir();
      final name = '${evidence.imageSha256.substring(0, 16)}.json';
      await File('${dir.path}/$name').writeAsString(jsonEncode({
        'image_path': image.path,
        'evidence': evidence.toJson(),
      }));
    } catch (_) {}
  }

  Future<Directory> _queueDir() async {
    final dir = await getApplicationDocumentsDirectory();
    final outbox = Directory('${dir.path}/outbox');
    if (!await outbox.exists()) await outbox.create(recursive: true);
    return outbox;
  }

  String? _serverMessage(String body) {
    try {
      final j = jsonDecode(body);
      if (j is Map && j['detail'] != null) {
        final d = j['detail'];
        if (d is String) return d;
        if (d is List && d.isNotEmpty && d.first is Map) {
          return d.first['msg'] as String?;
        }
      }
    } catch (_) {}
    return null;
  }

  CaptureEvidence _evidenceFrom(dynamic raw) {
    final j = raw is String ? jsonDecode(raw) as Map<String, dynamic> : raw as Map<String, dynamic>;
    return CaptureEvidence(
      siteId: j['site_id'] as String,
      milestoneId: j['milestone_id'] as String,
      lat: (j['lat'] as num).toDouble(),
      lng: (j['lng'] as num).toDouble(),
      accuracyMeters: (j['accuracy_meters'] as num).toDouble(),
      distanceFromSiteMeters: (j['distance_from_site_meters'] as num).toDouble(),
      mockLocationDetected: j['mock_location_detected'] as bool,
      capturedAtDevice: DateTime.parse(j['captured_at_device'] as String),
      deviceModel: j['device_model'] as String,
      deviceId: j['device_id'] as String,
      imageSha256: j['image_sha256'] as String,
      imageBytes: j['image_bytes'] as int,
      borrowerNote: j['borrower_note'] as String?,
    );
  }
}