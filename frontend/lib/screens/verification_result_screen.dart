import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../models.dart';

class VerificationResultScreen extends StatelessWidget {
  const VerificationResultScreen({
    super.key,
    required this.report,
    required this.imageBytes,
    this.image,
    required this.site,
    required this.milestone,
    this.captureRef,
  });

  final InspectionReport report;
  final Uint8List imageBytes;
  final File? image;
  final Site site;
  final Milestone milestone;
  final String? captureRef;

  @override
  Widget build(BuildContext context) {
    final isApproved = report.finalDecision.toUpperCase() == 'APPROVED';
    final isRejected = report.finalDecision.toUpperCase() == 'REJECTED';

    final Color statusColor = isApproved
        ? const Color(0xFF10B981)
        : isRejected
            ? const Color(0xFFEF4444)
            : const Color(0xFFF59E0B);

    final IconData statusIcon = isApproved
        ? Icons.verified_rounded
        : isRejected
            ? Icons.gpp_bad_rounded
            : Icons.warning_amber_rounded;

    final String statusTitle = isApproved
        ? 'PHYSICALLY VERIFIED'
        : isRejected
            ? 'VERIFICATION REJECTED'
            : 'FLAGGED FOR MANUAL AUDIT';

    final String statusSubtitle = isApproved
        ? 'All 3 anti-fraud defense layers passed with high confidence.'
        : isRejected
            ? 'Physical reality violations detected. Disbursement blocked.'
            : 'Suspicious anomalies detected. Forwarded to risk officer.';

    final percentScore = (report.overallConfidenceScore * 100).toStringAsFixed(1);

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E293B),
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'Inspection Audit Result',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).popUntil((route) => route.isFirst),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Banner Card
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: statusColor.withOpacity(0.12),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: statusColor.withOpacity(0.4), width: 1.5),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: statusColor.withOpacity(0.2),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(statusIcon, color: statusColor, size: 36),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            statusTitle,
                            style: TextStyle(
                              color: statusColor,
                              fontWeight: FontWeight.w800,
                              fontSize: 18,
                              letterSpacing: 0.5,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            statusSubtitle,
                            style: const TextStyle(
                              color: Color(0xFFCBD5E1),
                              fontSize: 13.5,
                              height: 1.3,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Divider(color: Color(0xFF334155), height: 1),
                const SizedBox(height: 14),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _MetricPill(
                      label: 'Reality Score',
                      value: '$percentScore%',
                      color: statusColor,
                    ),
                    _MetricPill(
                      label: 'Decision',
                      value: report.finalDecision,
                      color: statusColor,
                    ),
                    _MetricPill(
                      label: 'Audit ID',
                      value: report.inspectionId.substring(0, 11),
                      color: const Color(0xFF94A3B8),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // Captured Image & Context
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF334155)),
            ),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.memory(
                    imageBytes,
                    width: 72,
                    height: 72,
                    fit: BoxFit.cover,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        site.label,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Stage: ${milestone.label}',
                        style: const TextStyle(
                          color: Color(0xFF94A3B8),
                          fontSize: 13,
                        ),
                      ),
                      if (captureRef != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          'Ref: $captureRef',
                          style: const TextStyle(
                            color: Color(0xFF64748B),
                            fontSize: 11.5,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // Section Title
          const Text(
            '3-LAYER FORENSIC AUDIT BREAKDOWN',
            style: TextStyle(
              color: Color(0xFF94A3B8),
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.1,
            ),
          ),
          const SizedBox(height: 12),

          // Layer 1: Depth Check
          _LayerCard(
            layerNumber: 'LAYER 1',
            title: '3D Monocular Depth & Motion Parallax',
            engine: 'Depth-Anything-V2 (PyTorch)',
            passed: !report.layer1Depth.isFlatSurface &&
                report.layer1Depth.verdict.toUpperCase() == 'PASS',
            summary: report.layer1Depth.isFlatSurface
                ? 'FAIL: Planar 2D Surface Detected (Screen / Print Attack)'
                : 'PASS: Genuine 3D Spatial Geometry Verified',
            metrics: [
              'Plane Fit R²: ${report.layer1Depth.planeFitR2.toStringAsFixed(3)} (threshold < 0.88)',
              'Depth Variance: ${report.layer1Depth.depthStdDev.toStringAsFixed(3)}',
              'Verdict: ${report.layer1Depth.verdict}',
            ],
            reasons: report.layer1Depth.reasons,
          ),

          const SizedBox(height: 14),

          // Layer 2: Recapture & GenAI
          _LayerCard(
            layerNumber: 'LAYER 2',
            title: 'Digital Screen Recapture & GenAI Provenance',
            engine: '2D-FFT Moiré Grid + C2PA Cryptography',
            passed: !report.layer2Recapture.screenRecaptureDetected &&
                !report.layer2Recapture.aiGenerationDetected &&
                report.layer2Recapture.verdict.toUpperCase() == 'PASS',
            summary: report.layer2Recapture.screenRecaptureDetected
                ? 'FAIL: LCD/OLED Pixel Grid Moiré Peaks Detected'
                : report.layer2Recapture.aiGenerationDetected
                    ? 'FAIL: C2PA Cryptographic GenAI Watermark Detected'
                    : 'PASS: Authentic Optical Sensor Capture (No Screen/AI)',
            metrics: [
              'Moiré High-Freq Energy: ${report.layer2Recapture.localMoireEnergy.toStringAsFixed(3)}',
              'Screen Recapture: ${report.layer2Recapture.screenRecaptureDetected ? "DETECTED" : "None"}',
              'AI Generation: ${report.layer2Recapture.aiGenerationDetected ? "DETECTED" : "None"}',
            ],
            reasons: report.layer2Recapture.reasons,
          ),

          const SizedBox(height: 14),

          // Layer 3: Geospatial & Satellite
          _LayerCard(
            layerNumber: 'LAYER 3',
            title: 'Geospatial Lock & Satellite Structural Match',
            engine: 'ESRI Slippy Tiles + LightGlue Feature Alignment',
            passed: report.layer3Geospatial.withinGeofence &&
                report.layer3Geospatial.verdict.toUpperCase() != 'FAIL',
            summary: !report.layer3Geospatial.withinGeofence
                ? 'FAIL: Device Outside Authorized Plot Geofence'
                : 'PASS: Geofence Verified & Satellite Features Aligned',
            metrics: [
              'Distance to Registered Point: ${report.layer3Geospatial.gpsDistanceMeters.toStringAsFixed(1)} m',
              'Within Geofence: ${report.layer3Geospatial.withinGeofence ? "YES" : "NO"}',
              'LightGlue Keypoints: ${report.layer3Geospatial.lightglueMatchesCount} matches, ${report.layer3Geospatial.ransacInliersCount} inliers',
            ],
            reasons: report.layer3Geospatial.reasons,
          ),

          const SizedBox(height: 20),

          // Flagged Security Violations (if any)
          if (report.flaggedReasons.isNotEmpty) ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF7F1D1D).withOpacity(0.2),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFEF4444).withOpacity(0.5)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.shield_outlined, color: Color(0xFFEF4444), size: 20),
                      SizedBox(width: 8),
                      Text(
                        'Flagged Security Violations',
                        style: TextStyle(
                          color: Color(0xFFFCA5A5),
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  ...report.flaggedReasons.map(
                    (r) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('• ', style: TextStyle(color: Color(0xFFEF4444), fontSize: 16)),
                          Expanded(
                            child: Text(
                              r,
                              style: const TextStyle(color: Color(0xFFFEE2E2), fontSize: 13),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
          ],

          // Recommended Action
          if (report.recommendedAction.isNotEmpty) ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF334155)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Recommended Action',
                    style: TextStyle(
                      color: Color(0xFF94A3B8),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    report.recommendedAction,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
          ],

          // Done Button
          FilledButton(
            onPressed: () => Navigator.of(context).popUntil((route) => route.isFirst),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF3B82F6),
              minimumSize: const Size.fromHeight(52),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text(
              'Back to Inspection Home',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _MetricPill extends StatelessWidget {
  const _MetricPill({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.bold,
            fontSize: 14,
          ),
        ),
      ],
    );
  }
}

class _LayerCard extends StatelessWidget {
  const _LayerCard({
    required this.layerNumber,
    required this.title,
    required this.engine,
    required this.passed,
    required this.summary,
    required this.metrics,
    required this.reasons,
  });

  final String layerNumber;
  final String title;
  final String engine;
  final bool passed;
  final String summary;
  final List<String> metrics;
  final List<String> reasons;

  @override
  Widget build(BuildContext context) {
    final statusColor = passed ? const Color(0xFF10B981) : const Color(0xFFEF4444);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: passed ? const Color(0xFF334155) : const Color(0xFFEF4444).withOpacity(0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                layerNumber,
                style: TextStyle(
                  color: statusColor,
                  fontWeight: FontWeight.bold,
                  fontSize: 11,
                  letterSpacing: 1.0,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      passed ? Icons.check_circle_rounded : Icons.cancel_rounded,
                      color: statusColor,
                      size: 14,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      passed ? 'PASSED' : 'FLAGGED',
                      style: TextStyle(
                        color: statusColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: 15,
            ),
          ),
          Text(
            engine,
            style: const TextStyle(color: Color(0xFF64748B), fontSize: 12),
          ),
          const SizedBox(height: 10),
          Text(
            summary,
            style: TextStyle(
              color: passed ? const Color(0xFF34D399) : const Color(0xFFF87171),
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFF0F172A),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: metrics.map(
                (m) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Text(
                    m,
                    style: const TextStyle(
                      color: Color(0xFF94A3B8),
                      fontSize: 12,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
              ).toList(),
            ),
          ),
          if (reasons.isNotEmpty) ...[
            const SizedBox(height: 8),
            ...reasons.map(
              (r) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 1),
                child: Text(
                  '⚠ $r',
                  style: const TextStyle(color: Color(0xFFF87171), fontSize: 12),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
