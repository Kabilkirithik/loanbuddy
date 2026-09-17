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

/// 3-Layer Anti-Fraud Inspection Report returned by the backend portal.
class Layer1DepthReport {
  final String verdict;
  final double confidenceScore;
  final double depthStdDev;
  final double planeFitR2;
  final bool isFlatSurface;
  final bool? motionParallaxDetected;
  final List<String> reasons;

  const Layer1DepthReport({
    required this.verdict,
    required this.confidenceScore,
    required this.depthStdDev,
    required this.planeFitR2,
    required this.isFlatSurface,
    this.motionParallaxDetected,
    required this.reasons,
  });

  factory Layer1DepthReport.fromJson(Map<String, dynamic> j) => Layer1DepthReport(
        verdict: j['verdict'] as String? ?? 'UNKNOWN',
        confidenceScore: (j['confidence_score'] as num?)?.toDouble() ?? 0.0,
        depthStdDev: (j['depth_std_dev'] as num?)?.toDouble() ?? 0.0,
        planeFitR2: (j['plane_fit_r2'] as num?)?.toDouble() ?? 0.0,
        isFlatSurface: j['is_flat_surface'] as bool? ?? false,
        motionParallaxDetected: j['motion_parallax_detected'] as bool?,
        reasons: (j['reasons'] as List?)?.map((e) => e.toString()).toList() ?? [],
      );
}

class Layer2RecaptureReport {
  final String verdict;
  final double confidenceScore;
  final bool screenRecaptureDetected;
  final bool aiGenerationDetected;
  final double localMoireEnergy;
  final List<String> reasons;
  final Map<String, dynamic> details;

  const Layer2RecaptureReport({
    required this.verdict,
    required this.confidenceScore,
    required this.screenRecaptureDetected,
    required this.aiGenerationDetected,
    required this.localMoireEnergy,
    required this.reasons,
    required this.details,
  });

  factory Layer2RecaptureReport.fromJson(Map<String, dynamic> j) => Layer2RecaptureReport(
        verdict: j['verdict'] as String? ?? 'UNKNOWN',
        confidenceScore: (j['confidence_score'] as num?)?.toDouble() ?? 0.0,
        screenRecaptureDetected: j['screen_recapture_detected'] as bool? ?? false,
        aiGenerationDetected: j['ai_generation_detected'] as bool? ?? false,
        localMoireEnergy: (j['local_moire_energy'] as num?)?.toDouble() ?? 0.0,
        reasons: (j['reasons'] as List?)?.map((e) => e.toString()).toList() ?? [],
        details: j['details'] as Map<String, dynamic>? ?? {},
      );
}

class Layer3GeospatialReport {
  final String verdict;
  final double confidenceScore;
  final bool withinGeofence;
  final double gpsDistanceMeters;
  final int lightglueMatchesCount;
  final int ransacInliersCount;
  final List<String> reasons;

  const Layer3GeospatialReport({
    required this.verdict,
    required this.confidenceScore,
    required this.withinGeofence,
    required this.gpsDistanceMeters,
    required this.lightglueMatchesCount,
    required this.ransacInliersCount,
    required this.reasons,
  });

  factory Layer3GeospatialReport.fromJson(Map<String, dynamic> j) => Layer3GeospatialReport(
        verdict: j['verdict'] as String? ?? 'UNKNOWN',
        confidenceScore: (j['confidence_score'] as num?)?.toDouble() ?? 0.0,
        withinGeofence: j['within_geofence'] as bool? ?? false,
        gpsDistanceMeters: (j['gps_distance_meters'] as num?)?.toDouble() ?? 0.0,
        lightglueMatchesCount: j['lightglue_matches_count'] as int? ?? 0,
        ransacInliersCount: j['ransac_inliers_count'] as int? ?? 0,
        reasons: (j['reasons'] as List?)?.map((e) => e.toString()).toList() ?? [],
      );
}

class InspectionReport {
  final String inspectionId;
  final String timestamp;
  final double overallConfidenceScore;
  final String finalDecision;
  final Layer1DepthReport layer1Depth;
  final Layer2RecaptureReport layer2Recapture;
  final Layer3GeospatialReport layer3Geospatial;
  final List<String> flaggedReasons;
  final String recommendedAction;

  const InspectionReport({
    required this.inspectionId,
    required this.timestamp,
    required this.overallConfidenceScore,
    required this.finalDecision,
    required this.layer1Depth,
    required this.layer2Recapture,
    required this.layer3Geospatial,
    required this.flaggedReasons,
    required this.recommendedAction,
  });

  factory InspectionReport.fromJson(Map<String, dynamic> j) => InspectionReport(
        inspectionId: j['inspection_id'] as String? ?? 'INSP-UNKNOWN',
        timestamp: j['timestamp'] as String? ?? '',
        overallConfidenceScore:
            (j['overall_confidence_score'] as num?)?.toDouble() ?? 0.0,
        finalDecision: j['final_decision'] as String? ?? 'UNKNOWN',
        layer1Depth: Layer1DepthReport.fromJson(
            j['layer1_depth'] as Map<String, dynamic>? ?? {}),
        layer2Recapture: Layer2RecaptureReport.fromJson(
            j['layer2_recapture'] as Map<String, dynamic>? ?? {}),
        layer3Geospatial: Layer3GeospatialReport.fromJson(
            j['layer3_geospatial'] as Map<String, dynamic>? ?? {}),
        flaggedReasons: (j['flagged_reasons'] as List?)
                ?.map((e) => e.toString())
                .toList() ??
            [],
        recommendedAction: j['recommended_action'] as String? ?? '',
      );
}