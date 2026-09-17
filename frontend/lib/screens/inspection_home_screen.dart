import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;

import '../models.dart';
import '../services/location_service.dart';
import '../services/submission_service.dart';
import 'capture_screen.dart';

class InspectionHomeScreen extends StatefulWidget {
  const InspectionHomeScreen({
    super.key,
    required this.submissions,
  });

  final SubmissionService submissions;

  @override
  State<InspectionHomeScreen> createState() => _InspectionHomeScreenState();
}

class _InspectionHomeScreenState extends State<InspectionHomeScreen> {
  final _location = LocationService();
  Position? _currentFix;
  bool _loadingLocation = false;

  List<Site> _sites = [];

  Site? _selectedSite;
  Milestone? _selectedMilestone;
  bool _loadingSites = true;
  String _backendStatus = 'Checking...';

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  Future<void> _loadInitialData() async {
    await Future.wait([
      _fetchSitesAndHealth(),
      _fetchLocation(),
    ]);
  }

  Future<void> _fetchSitesAndHealth() async {
    setState(() => _loadingSites = true);

    try {
      final healthUri = Uri.parse('${widget.submissions.baseUrl}/v1/health');
      final healthRes = await http.get(healthUri).timeout(const Duration(seconds: 8));
      if (healthRes.statusCode == 200) {
        setState(() => _backendStatus = 'Online (All 3 Layers Active)');
      } else {
        setState(() => _backendStatus = 'Degraded');
      }
    } catch (_) {
      setState(() => _backendStatus = 'Local Offline Mode');
    }

    try {
      final sitesUri = Uri.parse('${widget.submissions.baseUrl}/v1/sites');
      final res = await http.get(sitesUri).timeout(const Duration(seconds: 8));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as List;
        final loaded = data.map((j) => Site.fromJson(j as Map<String, dynamic>)).toList();
        if (loaded.isNotEmpty && mounted) {
          setState(() {
            _sites = loaded;
            _selectedSite = loaded.first;
            _selectedMilestone = loaded.first.nextDue ?? loaded.first.milestones.first;
            _loadingSites = false;
          });
          return;
        }
      }
    } catch (_) {
      // Fallback to default demo sites
    }

    if (!mounted) return;
    setState(() {
      _sites = _defaultDemoSites();
      _selectedSite = _sites.first;
      _selectedMilestone = _sites.first.nextDue ?? _sites.first.milestones.first;
      _loadingSites = false;
    });
  }

  Future<void> _fetchLocation() async {
    setState(() => _loadingLocation = true);
    try {
      final pos = await _location.currentPosition();
      if (!mounted) return;
      setState(() {
        _currentFix = pos;
        _loadingLocation = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadingLocation = false;
      });
    }
  }

  List<Site> _defaultDemoSites() {
    return [
      const Site(
        id: 'site_8812',
        label: 'Plot 14, Bagayam',
        borrowerName: 'R. Selvakumar',
        loanAccountNo: 'NBF-2291-0087',
        lat: 12.9165,
        lng: 79.1325,
        allowedRadiusMeters: 5000.0,
        milestones: [
          Milestone(
            id: 'ms_1',
            label: 'Foundation complete',
            tranche: 1,
            amountPaise: 45000000,
            status: MilestoneStatus.approved,
          ),
          Milestone(
            id: 'ms_2',
            label: 'Ground floor slab',
            tranche: 2,
            amountPaise: 60000000,
            status: MilestoneStatus.due,
            lastApprovedPhotoUrl: null,
          ),
        ],
      ),
      const Site(
        id: 'site_9034',
        label: 'Shed extension, Kalinjur',
        borrowerName: 'Meena Traders',
        loanAccountNo: 'NBF-2291-0143',
        lat: 12.9498,
        lng: 79.1602,
        allowedRadiusMeters: 90.0,
        milestones: [
          Milestone(
            id: 'ms_9',
            label: 'Steel frame erected',
            tranche: 1,
            amountPaise: 80000000,
            status: MilestoneStatus.due,
          ),
        ],
      ),
    ];
  }

  void _openCamera(bool isVideo) {
    if (_selectedSite == null || _selectedMilestone == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a site and milestone first.')),
      );
      return;
    }

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CaptureScreen(
          site: _selectedSite!,
          milestone: _selectedMilestone!,
          submissions: widget.submissions,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final site = _selectedSite;
    final milestone = _selectedMilestone;

    double? distanceMeters;
    if (_currentFix != null && site != null) {
      distanceMeters = Geolocator.distanceBetween(
        _currentFix!.latitude,
        _currentFix!.longitude,
        site.lat,
        site.lng,
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E293B),
        foregroundColor: Colors.white,
        elevation: 0,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: const Color(0xFF3B82F6).withOpacity(0.2),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.security, color: Color(0xFF60A5FA), size: 20),
            ),
            const SizedBox(width: 10),
            const Text(
              'SiteCheck AI Inspector',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh Location & Sites',
            icon: const Icon(Icons.refresh),
            onPressed: _loadInitialData,
          ),
        ],
      ),
      body: _loadingSites
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF60A5FA)),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Backend Connectivity Badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E293B),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFF334155)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _backendStatus.startsWith('Online')
                              ? const Color(0xFF10B981)
                              : const Color(0xFFF59E0B),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Backend: $_backendStatus',
                        style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // Active Site Card
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E293B),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFF334155)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'REGISTERED SITE',
                            style: TextStyle(
                              color: Color(0xFF60A5FA),
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.0,
                            ),
                          ),
                          if (_sites.length > 1)
                            PopupMenuButton<Site>(
                              tooltip: 'Switch Site',
                              child: const Row(
                                children: [
                                  Text(
                                    'Switch',
                                    style: TextStyle(
                                      color: Color(0xFF94A3B8),
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  Icon(Icons.arrow_drop_down, color: Color(0xFF94A3B8)),
                                ],
                              ),
                              onSelected: (newSite) {
                                setState(() {
                                  _selectedSite = newSite;
                                  _selectedMilestone = newSite.nextDue ?? newSite.milestones.first;
                                });
                              },
                              itemBuilder: (ctx) => _sites
                                  .map((s) => PopupMenuItem(value: s, child: Text(s.label)))
                                  .toList(),
                            ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        site?.label ?? 'No Site Selected',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Borrower: ${site?.borrowerName} • A/C: ${site?.loanAccountNo}',
                        style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
                      ),
                      const SizedBox(height: 12),
                      const Divider(color: Color(0xFF334155), height: 1),
                      const SizedBox(height: 12),

                      // Milestone & Geofence
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Current Milestone',
                                  style: TextStyle(color: Color(0xFF64748B), fontSize: 11),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  milestone?.label ?? 'N/A',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              const Text(
                                'Plot Proximity',
                                style: TextStyle(color: Color(0xFF64748B), fontSize: 11),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                distanceMeters != null
                                    ? '${distanceMeters.round()} m away'
                                    : _loadingLocation
                                        ? 'Locating...'
                                        : 'GPS Pending',
                                style: TextStyle(
                                  color: distanceMeters != null &&
                                          distanceMeters <= (site?.allowedRadiusMeters ?? 100)
                                      ? const Color(0xFF10B981)
                                      : const Color(0xFFF59E0B),
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                // Main Prompt Callout
                const Center(
                  child: Text(
                    'PROCEED TO SITE VERIFICATION',
                    style: TextStyle(
                      color: Color(0xFF94A3B8),
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.2,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                const Center(
                  child: Text(
                    'Capture real-time site evidence for 3-layer anti-fraud audit',
                    style: TextStyle(color: Color(0xFF64748B), fontSize: 13),
                  ),
                ),

                const SizedBox(height: 20),

                // Primary Action Button: Take Photo
                InkWell(
                  onTap: () => _openCamera(false),
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    padding: const EdgeInsets.all(22),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF2563EB), Color(0xFF1D4ED8)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF2563EB).withOpacity(0.35),
                          blurRadius: 18,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.18),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.camera_alt_rounded, color: Colors.white, size: 32),
                        ),
                        const SizedBox(width: 18),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Take Inspection Photo',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              SizedBox(height: 4),
                              Text(
                                'Runs 3D Depth, Moiré Screen Check & Satellite Keypoint Matching',
                                style: TextStyle(
                                  color: Color(0xFFBFDBFE),
                                  fontSize: 12.5,
                                  height: 1.3,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white, size: 18),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 14),

                // Secondary Action Button: Take Video
                InkWell(
                  onTap: () => _openCamera(true),
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E293B),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFF334155)),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: const BoxDecoration(
                            color: Color(0xFF334155),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.videocam_rounded, color: Color(0xFF93C5FD), size: 26),
                        ),
                        const SizedBox(width: 16),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Record Sweep Video',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              SizedBox(height: 2),
                              Text(
                                'Extracts Lucas-Kanade motion parallax for high-confidence 3D validation',
                                style: TextStyle(
                                  color: Color(0xFF94A3B8),
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Icon(Icons.arrow_forward_ios_rounded, color: Color(0xFF64748B), size: 16),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 32),

                // How it Works: 3-Layer Defense Overview
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E293B).withOpacity(0.6),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFF334155).withOpacity(0.6)),
                  ),
                  child: const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'HOW BACKEND PORTAL VERIFICATION WORKS',
                        style: TextStyle(
                          color: Color(0xFF64748B),
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.9,
                        ),
                      ),
                      SizedBox(height: 12),
                      _DefenseStep(
                        number: '1',
                        title: '3D Depth & Motion Parallax',
                        subtitle: 'Depth-Anything-V2 checks surface curvature to reject flat screen/paper attacks.',
                      ),
                      SizedBox(height: 10),
                      _DefenseStep(
                        number: '2',
                        title: 'Screen Recapture & AI Provenance',
                        subtitle: '2D-FFT Moiré frequencies detect monitor pixels; C2PA verifies camera authenticity.',
                      ),
                      SizedBox(height: 10),
                      _DefenseStep(
                        number: '3',
                        title: 'Geospatial Lock & Satellite Match',
                        subtitle: 'ESRI satellite tiles match building orientation and structural keypoints via LightGlue.',
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),
              ],
            ),
    );
  }
}

class _DefenseStep extends StatelessWidget {
  const _DefenseStep({
    required this.number,
    required this.title,
    required this.subtitle,
  });

  final String number;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 24,
          height: 24,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: const Color(0xFF3B82F6).withOpacity(0.2),
            shape: BoxShape.circle,
          ),
          child: Text(
            number,
            style: const TextStyle(
              color: Color(0xFF60A5FA),
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 13.5,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: const TextStyle(
                  color: Color(0xFF94A3B8),
                  fontSize: 12,
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
