import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

import '../main.dart';
import '../models.dart';
import '../services/submission_service.dart';
import 'capture_screen.dart';

/// Loads lender construction sites and active milestones.
/// Dynamically pulls from GET /v1/sites when backend is available,
/// with automatic fallback to offline demo sites for testing.
class SiteRepository {
  final String? baseUrl;
  final String? authToken;

  const SiteRepository({this.baseUrl, this.authToken});

  Future<List<Site>> load() async {
    if (baseUrl != null && baseUrl!.isNotEmpty) {
      try {
        final res = await http.get(
          Uri.parse('$baseUrl/v1/sites'),
          headers: authToken != null ? {'Authorization': 'Bearer $authToken'} : null,
        ).timeout(const Duration(seconds: 4));

        if (res.statusCode == 200) {
          final list = jsonDecode(res.body) as List<dynamic>;
          return list.map((s) => Site.fromJson(s as Map<String, dynamic>)).toList();
        }
      } catch (_) {
        // Fall back to local test catalogue if backend is unreachable
      }
    }
    await Future<void>.delayed(const Duration(milliseconds: 200));
    return defaultSites;
  }

  static const List<Site> defaultSites = [
    Site(
      id: 'site_8812',
      label: 'Plot 14, Bagayam',
      borrowerName: 'R. Selvakumar',
      loanAccountNo: 'NBF-2291-0087',
      lat: 12.9165,
      lng: 79.1325,
      allowedRadiusMeters: 5000,
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
          lastApprovedPhotoUrl: 'https://cdn.example/ms_1.jpg',
        ),
        Milestone(
          id: 'ms_3',
          label: 'Roofing',
          tranche: 3,
          amountPaise: 55000000,
          status: MilestoneStatus.locked,
        ),
      ],
    ),
    Site(
      id: 'site_9034',
      label: 'Shed extension, Kalinjur',
      borrowerName: 'Meena Traders',
      loanAccountNo: 'NBF-2291-0143',
      lat: 12.9498,
      lng: 79.1602,
      allowedRadiusMeters: 90,
      milestones: [
        Milestone(
          id: 'ms_9',
          label: 'Steel frame erected',
          tranche: 1,
          amountPaise: 80000000,
          status: MilestoneStatus.rejected,
          reviewerNote:
              'The frame is clear but the surroundings do not match the '
              'registered plot. Shoot from the road-facing corner.',
        ),
      ],
    ),
  ];
}

class SiteListScreen extends StatefulWidget {
  const SiteListScreen({super.key, required this.submissions});

  final SubmissionService submissions;

  @override
  State<SiteListScreen> createState() => _SiteListScreenState();
}

class _SiteListScreenState extends State<SiteListScreen> {
  late final SiteRepository _repo;
  late Future<List<Site>> _sites;
  int _pending = 0;

  @override
  void initState() {
    super.initState();
    _repo = SiteRepository(
      baseUrl: widget.submissions.baseUrl,
      authToken: widget.submissions.authToken,
    );
    _sites = _repo.load();
    _refreshPending();
  }

  Future<void> _refreshPending() async {
    final n = await widget.submissions.pendingCount();
    if (mounted) setState(() => _pending = n);
  }

  Future<void> _reload() async {
    setState(() => _sites = _repo.load());
    await _refreshPending();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Your sites'),
        actions: [
          IconButton(
            onPressed: _reload,
            icon: const Icon(Icons.refresh),
            tooltip: 'Reload',
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _reload,
        child: FutureBuilder<List<Site>>(
          future: _sites,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snap.hasError) {
              return _Message(
                title: 'Could not load your sites',
                body: 'Check your connection and pull down to try again.',
              );
            }
            final sites = snap.data ?? const <Site>[];
            if (sites.isEmpty) {
              return _Message(
                title: 'No sites yet',
                body: 'Sites appear here once your lender registers them '
                    'against your loan.',
              );
            }

            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              children: [
                if (_pending > 0) _OutboxBanner(count: _pending),
                for (final site in sites) ...[
                  _SiteCard(
                    site: site,
                    onCapture: (m) => _openCapture(site, m),
                  ),
                  const SizedBox(height: 14),
                ],
              ],
            );
          },
        ),
      ),
    );
  }

  Future<void> _openCapture(Site site, Milestone milestone) async {
    final submitted = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => CaptureScreen(
          site: site,
          milestone: milestone,
          submissions: widget.submissions,
        ),
      ),
    );
    if (submitted == true) await _reload();
  }
}

class _SiteCard extends StatelessWidget {
  const _SiteCard({required this.site, required this.onCapture});

  final Site site;
  final void Function(Milestone) onCapture;

  @override
  Widget build(BuildContext context) {
    final due = site.nextDue;

    return Container(
      decoration: BoxDecoration(
        color: Palette.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Palette.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(site.label,
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 2),
                Text('${site.borrowerName} · Loan ${site.loanAccountNo}',
                    style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
          const Divider(height: 1, color: Palette.line),
          for (final m in site.milestones)
            _MilestoneRow(milestone: m, isLast: m == site.milestones.last),
          if (due != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              child: FilledButton.icon(
                onPressed: () => onCapture(due),
                style: FilledButton.styleFrom(
                  backgroundColor: Palette.signal,
                  foregroundColor: Palette.ink,
                ),
                icon: const Icon(Icons.photo_camera_outlined),
                label: Text('Capture ${due.label.toLowerCase()}'),
              ),
            ),
        ],
      ),
    );
  }
}

class _MilestoneRow extends StatelessWidget {
  const _MilestoneRow({required this.milestone, required this.isLast});

  final Milestone milestone;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final money = NumberFormat.currency(
      locale: 'en_IN',
      symbol: '₹',
      decimalDigits: 0,
    ).format(milestone.amountPaise / 100);

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        border: isLast
            ? null
            : const Border(bottom: BorderSide(color: Palette.line)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Tranche ${milestone.tranche} — ${milestone.label}',
                  style: const TextStyle(fontSize: 15, height: 1.3),
                ),
              ),
              const SizedBox(width: 10),
              _StatusPill(status: milestone.status),
            ],
          ),
          const SizedBox(height: 2),
          Text(money, style: Theme.of(context).textTheme.bodySmall),
          if (milestone.reviewerNote != null) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFFCEEEC),
                border: Border.all(color: const Color(0xFFF0C9C3)),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                milestone.reviewerNote!,
                style: const TextStyle(fontSize: 13.5, height: 1.4),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.status});

  final MilestoneStatus status;

  @override
  Widget build(BuildContext context) {
    late final String label;
    late final Color fg;
    late final Color bg;

    switch (status) {
      case MilestoneStatus.approved:
        label = 'Released';
        fg = Palette.verified;
        bg = const Color(0xFFE6F2EC);
      case MilestoneStatus.due:
        label = 'Photo needed';
        fg = Palette.ink;
        bg = const Color(0xFFFBF1D2);
      case MilestoneStatus.inReview:
        label = 'In review';
        fg = Palette.inkMuted;
        bg = const Color(0xFFE9EDF1);
      case MilestoneStatus.rejected:
        label = 'Sent back';
        fg = Palette.blocked;
        bg = const Color(0xFFFCEEEC);
      case MilestoneStatus.locked:
        label = 'Not yet';
        fg = Palette.inkMuted;
        bg = const Color(0xFFE9EDF1);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: fg),
      ),
    );
  }
}

class _OutboxBanner extends StatelessWidget {
  const _OutboxBanner({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Palette.ink,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          const Icon(Icons.cloud_upload_outlined, color: Palette.signal),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              count == 1
                  ? '1 photo is waiting to be sent. It will go out as soon as '
                      'you have signal.'
                  : '$count photos are waiting to be sent. They will go out as '
                      'soon as you have signal.',
              style: const TextStyle(
                  color: Colors.white, fontSize: 14, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(28, 90, 28, 28),
      children: [
        Text(title, style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 8),
        Text(body, style: Theme.of(context).textTheme.bodyMedium),
      ],
    );
  }
}