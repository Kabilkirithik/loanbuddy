import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../main.dart';
import '../models.dart';
import '../services/submission_service.dart';

/// Last stop before the photo leaves the phone. The borrower can retake, but
/// cannot edit — everything shown here is already burned into the file.
class ReviewScreen extends StatefulWidget {
  const ReviewScreen({
    super.key,
    required this.image,
    required this.evidence,
    required this.site,
    required this.milestone,
    required this.submissions,
  });

  final File image;
  final CaptureEvidence evidence;
  final Site site;
  final Milestone milestone;
  final SubmissionService submissions;

  @override
  State<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends State<ReviewScreen> {
  final _note = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _sending = true);

    final result = await widget.submissions.submit(
      widget.image,
      widget.evidence.copyWith(
        borrowerNote: _note.text.trim().isEmpty ? null : _note.text.trim(),
      ),
    );

    if (!mounted) return;
    setState(() => _sending = false);

    switch (result.state) {
      case SubmissionState.submitted:
        _showOutcome(
          title: 'Sent for verification',
          body: 'Your lender will see the result of the automatic checks '
              'within a few minutes. You will be told if anything needs a '
              'second photo.',
          pop: true,
        );
      case SubmissionState.queued:
        _showOutcome(
          title: 'Saved on your phone',
          body: result.message ??
              'It will be sent automatically once you have signal.',
          pop: true,
        );
      case SubmissionState.failed:
      case SubmissionState.uploading:
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result.message ?? 'Submission was not accepted.'),
          ),
        );
    }
  }

  void _showOutcome({
    required String title,
    required String body,
    required bool pop,
  }) {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(body, style: const TextStyle(height: 1.45)),
        actions: [
          FilledButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              if (pop) Navigator.of(context).pop(true);
            },
            style: FilledButton.styleFrom(
              minimumSize: const Size(120, 44),
            ),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.evidence;

    return Scaffold(
      appBar: AppBar(title: const Text('Check and send')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: Image.file(widget.image, fit: BoxFit.cover),
          ),
          const SizedBox(height: 16),

          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Palette.surface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Palette.line),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('What is being sent with this photo',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 12),
                _Fact('Site', widget.site.label),
                _Fact('Stage',
                    'Tranche ${widget.milestone.tranche} — ${widget.milestone.label}'),
                _Fact('Taken at',
                    DateFormat('dd MMM yyyy, h:mm a').format(e.capturedAtDevice)),
                _Fact('Location',
                    '${e.distanceFromSiteMeters.round()} m from the registered point'),
                _Fact('Photo fingerprint',
                    '${e.imageSha256.substring(0, 12)}…'),
                if (e.mockLocationDetected) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFCEEEC),
                      border: Border.all(color: const Color(0xFFF0C9C3)),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text(
                      'This phone is reporting a simulated location. Turn off '
                      'any mock location app, or this photo will be sent for '
                      'manual review.',
                      style: TextStyle(fontSize: 13.5, height: 1.4),
                    ),
                  ),
                ],
              ],
            ),
          ),

          const SizedBox(height: 16),
          TextField(
            controller: _note,
            maxLines: 3,
            maxLength: 240,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              labelText: 'Add a note for the reviewer (optional)',
              hintText: 'For example: slab poured on Monday, curing now.',
              filled: true,
              fillColor: Palette.surface,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: const BorderSide(color: Palette.line),
              ),
            ),
          ),

          const SizedBox(height: 8),
          FilledButton(
            onPressed: _sending ? null : _submit,
            child: _sending
                ? const SizedBox(
                    height: 22,
                    width: 22,
                    child: CircularProgressIndicator(
                        strokeWidth: 2.5, color: Colors.white),
                  )
                : const Text('Send for verification'),
          ),
          const SizedBox(height: 10),
          TextButton(
            onPressed: _sending ? null : () => Navigator.of(context).pop(false),
            style: TextButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            child: const Text('Retake the photo'),
          ),
        ],
      ),
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 128,
            child: Text(label,
                style: Theme.of(context).textTheme.bodySmall),
          ),
          Expanded(
            child: Text(value, style: const TextStyle(fontSize: 14.5, height: 1.35)),
          ),
        ],
      ),
    );
  }
}