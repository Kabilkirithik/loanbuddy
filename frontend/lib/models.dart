import 'dart:convert';

/// A financed construction site, registered by the lender at loan origination.
/// [lat]/[lng] are the surveyed coordinates the capture is checked against.
class Site {
  final String id;
  final String label;
  final String borrowerName;
  final String loanAccountNo;
  final double lat;
  final double lng;

  /// How far from the registered point a capture may be and still count as
  /// on-site. Set per site at origination — a plot in a dense urban lane needs
  /// a tighter radius than a 2-acre warehouse build.
  final double allowedRadiusMeters;

  final List<Milestone> milestones;

  const Site({
    required this.id,
    required this.label,
    required this.borrowerName,
    required this.loanAccountNo,
    required this.lat,
    required this.lng,
    required this.allowedRadiusMeters,
    required this.milestones,
  });

  Milestone? get nextDue {
    for (final m in milestones) {
      if (m.status == MilestoneStatus.due ||
          m.status == MilestoneStatus.rejected) {
        return m;
      }
    }
    return null;
  }

  factory Site.fromJson(Map<String, dynamic> j) => Site(
        id: j['id'] as String,
        label: j['label'] as String,
        borrowerName: j['borrower_name'] as String,
        loanAccountNo: j['loan_account_no'] as String,
        lat: (j['lat'] as num).toDouble(),
        lng: (j['lng'] as num).toDouble(),
        allowedRadiusMeters:
            (j['allowed_radius_meters'] as num?)?.toDouble() ?? 75,
        milestones: (j['milestones'] as List)
            .map((m) => Milestone.fromJson(m as Map<String, dynamic>))
            .toList(),
      );
}

enum MilestoneStatus { locked, due, inReview, approved, rejected }

class Milestone {
  final String id;
  final String label;
  final int tranche;
  final int amountPaise;
  final MilestoneStatus status;

  /// Server-held URL of the last approved photo for this site. The capture
  /// screen shows it as a faint alignment overlay so the borrower shoots from
  /// roughly the same position each time — which is what makes visual
  /// continuity comparison work downstream.
  final String? lastApprovedPhotoUrl;

  final String? reviewerNote;

  const Milestone({
    required this.id,
    required this.label,
    required this.tranche,
    required this.amountPaise,
    required this.status,
    this.lastApprovedPhotoUrl,
    this.reviewerNote,
  });

  factory Milestone.fromJson(Map<String, dynamic> j) => Milestone(
        id: j['id'] as String,
        label: j['label'] as String,
        tranche: j['tranche'] as int,
        amountPaise: j['amount_paise'] as int,
        status: MilestoneStatus.values.firstWhere(
          (s) => s.name == j['status'],
          orElse: () => MilestoneStatus.locked,
        ),
        lastApprovedPhotoUrl: j['last_approved_photo_url'] as String?,
        reviewerNote: j['reviewer_note'] as String?,
      );
}

/// Everything captured alongside the pixels. This travels with the image and is
/// what the verification and integrity agents actually reason over.
class CaptureEvidence {
  final String siteId;
  final String milestoneId;

  final double lat;
  final double lng;
  final double accuracyMeters;

  /// Metres between the capture point and the site's registered coordinates.
  final double distanceFromSiteMeters;

  /// Android reports when a location came from a mock provider. A true value is
  /// not proof of fraud on its own, but it is a hard flag for the decision
  /// agent — legitimate borrowers do not run mock location apps.
  final bool mockLocationDetected;

  /// Device clock at capture. The server compares this against its own receipt
  /// time; a large gap means the device clock was moved.
  final DateTime capturedAtDevice;

  final String deviceModel;
  final String deviceId;

  /// SHA-256 of the final stamped bytes. Computed on device and sent with the
  /// upload so the server can confirm nothing was altered in transit, and so
  /// exact-duplicate resubmissions are caught before any vision cost is spent.
  final String imageSha256;

  final int imageBytes;
  final String? borrowerNote;

  const CaptureEvidence({
    required this.siteId,
    required this.milestoneId,
    required this.lat,
    required this.lng,
    required this.accuracyMeters,
    required this.distanceFromSiteMeters,
    required this.mockLocationDetected,
    required this.capturedAtDevice,
    required this.deviceModel,
    required this.deviceId,
    required this.imageSha256,
    required this.imageBytes,
    this.borrowerNote,
  });

  CaptureEvidence copyWith({String? borrowerNote}) => CaptureEvidence(
        siteId: siteId,
        milestoneId: milestoneId,
        lat: lat,
        lng: lng,
        accuracyMeters: accuracyMeters,
        distanceFromSiteMeters: distanceFromSiteMeters,
        mockLocationDetected: mockLocationDetected,
        capturedAtDevice: capturedAtDevice,
        deviceModel: deviceModel,
        deviceId: deviceId,
        imageSha256: imageSha256,
        imageBytes: imageBytes,
        borrowerNote: borrowerNote ?? this.borrowerNote,
      );

  Map<String, dynamic> toJson() => {
        'site_id': siteId,
        'milestone_id': milestoneId,
        'lat': lat,
        'lng': lng,
        'accuracy_meters': accuracyMeters,
        'distance_from_site_meters': distanceFromSiteMeters,
        'mock_location_detected': mockLocationDetected,
        'captured_at_device': capturedAtDevice.toUtc().toIso8601String(),
        'device_model': deviceModel,
        'device_id': deviceId,
        'image_sha256': imageSha256,
        'image_bytes': imageBytes,
        'borrower_note': borrowerNote,
      };

  String toJsonString() => jsonEncode(toJson());
}

/// Result of the on-device pre-check, shown to the borrower before they submit.
/// This is not the verification decision — it only catches problems the phone
/// can see, so the borrower can fix them instead of waiting three days for a
/// rejection.
class PreflightResult {
  final bool withinGeofence;
  final bool accuracyAcceptable;
  final bool clockPlausible;
  final bool mockLocationDetected;

  const PreflightResult({
    required this.withinGeofence,
    required this.accuracyAcceptable,
    required this.clockPlausible,
    required this.mockLocationDetected,
  });

  bool get canSubmit => withinGeofence && accuracyAcceptable && clockPlausible;
}