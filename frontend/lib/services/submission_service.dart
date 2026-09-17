import 'dart:convert';
import 'dart:io';

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
///
/// Sites are often outside reliable coverage, so a failed upload is queued on
/// disk rather than discarded. The borrower is told the capture is safe and
/// will go out on its own — losing a capture means a second trip to the site.
class SubmissionService {
  SubmissionService({required this.baseUrl, required this.authToken});

  final String baseUrl;
  final String authToken;

  Future<SubmissionResult> submit(File image, CaptureEvidence evidence) async {
    try {
      final req = http.MultipartRequest(
        'POST',
        Uri.parse('$baseUrl/v1/captures'),
      )
        ..headers['Authorization'] = 'Bearer $authToken'
        // Sent as a header too so the server can reject a tampered or
        // truncated body before it buffers the whole file.
        ..headers['X-Image-SHA256'] = evidence.imageSha256
        ..fields['evidence'] = evidence.toJsonString()
        ..files.add(await http.MultipartFile.fromPath('image', image.path));

      final res = await http.Response.fromStream(
        await req.send().timeout(const Duration(seconds: 60)),
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
        // Server already holds this exact image hash — a reused photo.
        return const SubmissionResult(
          SubmissionState.failed,
          message: 'This photo has already been submitted. Take a new one.',
        );
      }

      if (res.statusCode >= 500) {
        await _enqueue(image, evidence);
        return const SubmissionResult(
          SubmissionState.queued,
          message: 'Saved. It will be sent when the server is back.',
        );
      }

      return SubmissionResult(
        SubmissionState.failed,
        message: _serverMessage(res.body) ?? 'Submission was not accepted.',
      );
    } on SocketException {
      await _enqueue(image, evidence);
      return const SubmissionResult(
        SubmissionState.queued,
        message: 'No connection. Saved and will be sent automatically.',
      );
    } catch (_) {
      await _enqueue(image, evidence);
      return const SubmissionResult(
        SubmissionState.queued,
        message: 'Saved and will be sent automatically.',
      );
    }
  }

  /// Retries everything on disk. Call on app start and when connectivity
  /// returns.
  Future<int> flushQueue() async {
    final dir = await _queueDir();
    final pending = dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.json'))
        .toList();

    var sent = 0;
    for (final manifest in pending) {
      try {
        final j = jsonDecode(await manifest.readAsString())
            as Map<String, dynamic>;
        final image = File(j['image_path'] as String);
        if (!await image.exists()) {
          await manifest.delete();
          continue;
        }
        final result = await submit(image, _evidenceFrom(j['evidence']));
        if (result.state == SubmissionState.submitted) {
          await manifest.delete();
          sent++;
        }
      } catch (_) {
        // Leave it queued for the next pass.
      }
    }
    return sent;
  }

  Future<int> pendingCount() async =>
      (await _queueDir()).listSync().whereType<File>().where((f) => f.path.endsWith('.json')).length;

  Future<void> _enqueue(File image, CaptureEvidence evidence) async {
    final dir = await _queueDir();
    final name = '${evidence.imageSha256.substring(0, 16)}.json';
    await File('${dir.path}/$name').writeAsString(jsonEncode({
      'image_path': image.path,
      'evidence': evidence.toJson(),
      'queued_at': DateTime.now().toUtc().toIso8601String(),
    }));
  }

  Future<Directory> _queueDir() async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}/outbox');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  static CaptureEvidence _evidenceFrom(dynamic j) {
    final m = j as Map<String, dynamic>;
    return CaptureEvidence(
      siteId: m['site_id'] as String,
      milestoneId: m['milestone_id'] as String,
      lat: (m['lat'] as num).toDouble(),
      lng: (m['lng'] as num).toDouble(),
      accuracyMeters: (m['accuracy_meters'] as num).toDouble(),
      distanceFromSiteMeters:
          (m['distance_from_site_meters'] as num).toDouble(),
      mockLocationDetected: m['mock_location_detected'] as bool,
      capturedAtDevice: DateTime.parse(m['captured_at_device'] as String),
      deviceModel: m['device_model'] as String,
      deviceId: m['device_id'] as String,
      imageSha256: m['image_sha256'] as String,
      imageBytes: m['image_bytes'] as int,
      borrowerNote: m['borrower_note'] as String?,
    );
  }

  static String? _serverMessage(String body) {
    try {
      return (jsonDecode(body) as Map<String, dynamic>)['message'] as String?;
    } catch (_) {
      return null;
    }
  }
}