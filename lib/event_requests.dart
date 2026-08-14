import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'theme.dart';
import 'motion.dart';
import 'events_manager.dart';
import 'content_filter.dart'; // profanity / threat / spam screening

// ===========================================================================
// Community event requests.
//
// Mandaleños can propose an activity for the city — a barangay fiesta, a
// clean-up drive, a sports league. CCAT staff review the request and, if it
// is approved, publish it as an official event.
//
// ---------------------------------------------------------------------------
// SHARED SCHEMA — collection `event_requests`
//   title, description, venue, category
//   proposedDate  timestamp
//   organizer, contact
//   requestedBy   uid      requestedByName / requestedByEmail
//   status        'pending' | 'approved' | 'declined'
//   staffNote     string    reply from CCAT
//   createdAt / reviewedAt  timestamp
// ===========================================================================

const String kEventRequestCollection = 'event_requests';

enum RequestStatus { pending, approved, declined }

RequestStatus requestStatusFromId(String? id) => switch (id) {
      'approved' => RequestStatus.approved,
      'declined' => RequestStatus.declined,
      _ => RequestStatus.pending,
    };

extension RequestStatusInfo on RequestStatus {
  String get id => switch (this) {
        RequestStatus.pending => 'pending',
        RequestStatus.approved => 'approved',
        RequestStatus.declined => 'declined',
      };

  String get label => switch (this) {
        RequestStatus.pending => 'Pending review',
        RequestStatus.approved => 'Approved',
        RequestStatus.declined => 'Declined',
      };

  Color get color => switch (this) {
        RequestStatus.pending => const Color(0xFFEF6C00),
        RequestStatus.approved => const Color(0xFF2E7D32),
        RequestStatus.declined => const Color(0xFFC62828),
      };

  IconData get icon => switch (this) {
        RequestStatus.pending => Icons.hourglass_top_outlined,
        RequestStatus.approved => Icons.check_circle_outline,
        RequestStatus.declined => Icons.cancel_outlined,
      };
}

class EventRequest {
  final String id;
  final String title;
  final String description;
  final String venue;
  final String category;
  final String organizer;
  final String contact;
  final String requestedByName;
  final String requestedByEmail;
  final String staffNote;
  final RequestStatus status;
  final DateTime? proposedDate;
  final DateTime? createdAt;

  const EventRequest({
    required this.id,
    required this.title,
    required this.description,
    required this.venue,
    required this.category,
    required this.organizer,
    required this.contact,
    required this.requestedByName,
    required this.requestedByEmail,
    required this.staffNote,
    required this.status,
    this.proposedDate,
    this.createdAt,
  });

  factory EventRequest.fromDoc(QueryDocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data();
    DateTime? asDate(dynamic v) => v is Timestamp ? v.toDate() : null;
    return EventRequest(
      id: d.id,
      title: (m['title'] ?? '').toString(),
      description: (m['description'] ?? '').toString(),
      venue: (m['venue'] ?? '').toString(),
      category: (m['category'] ?? 'Community').toString(),
      organizer: (m['organizer'] ?? '').toString(),
      contact: (m['contact'] ?? '').toString(),
      requestedByName: (m['requestedByName'] ?? 'Resident').toString(),
      requestedByEmail: (m['requestedByEmail'] ?? '').toString(),
      staffNote: (m['staffNote'] ?? '').toString(),
      status: requestStatusFromId(m['status']?.toString()),
      proposedDate: asDate(m['proposedDate']),
      createdAt: asDate(m['createdAt']),
    );
  }

  String get dateLabel {
    final d = proposedDate;
    if (d == null) return 'No date proposed';
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${d.day} ${months[d.month - 1]} ${d.year}';
  }
}

class EventRequestService {
  EventRequestService._();

  /// All requests, newest first (for staff).
  static Stream<List<EventRequest>> streamAll() => FirebaseFirestore.instance
      .collection(kEventRequestCollection)
      .orderBy('createdAt', descending: true)
      .snapshots()
      .map((s) => s.docs.map(EventRequest.fromDoc).toList());

  /// This resident's own requests.
  static Stream<List<EventRequest>> streamMine() {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '_';
    return FirebaseFirestore.instance
        .collection(kEventRequestCollection)
        .where('requestedBy', isEqualTo: uid)
        .snapshots()
        .map((s) => s.docs.map(EventRequest.fromDoc).toList());
  }

  static Future<void> submit({
    required String title,
    required String description,
    required String venue,
    required String category,
    required String organizer,
    required String contact,
    required DateTime proposedDate,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    await FirebaseFirestore.instance.collection(kEventRequestCollection).add({
      'title': title,
      'description': description,
      'venue': venue,
      'category': category,
      'organizer': organizer,
      'contact': contact,
      'proposedDate': Timestamp.fromDate(proposedDate),
      'requestedBy': user?.uid ?? '',
      'requestedByName': user?.displayName ?? 'Resident',
      'requestedByEmail': user?.email ?? '',
      'status': RequestStatus.pending.id,
      'staffNote': '',
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  static Future<void> decide({
    required String id,
    required RequestStatus status,
    String note = '',
  }) =>
      FirebaseFirestore.instance
          .collection(kEventRequestCollection)
          .doc(id)
          .update({
        'status': status.id,
        'staffNote': note,
        'reviewedAt': FieldValue.serverTimestamp(),
        'reviewedBy': FirebaseAuth.instance.currentUser?.email ?? '',
      });
}

// ---------------------------------------------------------------------------
// Resident side — propose an event, and track your requests
// ---------------------------------------------------------------------------
class EventRequestPage extends StatelessWidget {
  const EventRequestPage({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Request an Event')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const EventRequestFormPage()),
        ),
        icon: const Icon(Icons.add),
        label: const Text('New request'),
      ),
      body: StreamBuilder<List<EventRequest>>(
        stream: EventRequestService.streamMine(),
        builder: (context, snap) {
          final items = snap.data ?? [];
          items.sort((a, b) => (b.createdAt ?? DateTime(2000))
              .compareTo(a.createdAt ?? DateTime(2000)));

          return ListView(
            padding: const EdgeInsets.fromLTRB(
                AppSpacing.l, AppSpacing.l, AppSpacing.l, 90),
            children: [
              Reveal(
                delayMs: 0,
                child: Text('Propose a city activity', style: text.titleLarge),
              ),
              const SizedBox(height: 4),
              Reveal(
                delayMs: 40,
                child: Text(
                  'Residents can suggest events for Mandaluyong — fiestas, '
                  'clean-up drives, sports leagues, cultural programs. CCAT '
                  'staff review each request and publish the approved ones.',
                  style: text.bodyMedium?.copyWith(color: colors.outline),
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              if (items.isEmpty)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.xl),
                    child: Column(
                      children: [
                        Icon(Icons.campaign_outlined,
                            size: 44, color: colors.outline),
                        const SizedBox(height: AppSpacing.m),
                        Text('No requests yet', style: text.titleSmall),
                        const SizedBox(height: 4),
                        Text(
                          'Tap "New request" to propose your first activity.',
                          textAlign: TextAlign.center,
                          style: text.bodySmall
                              ?.copyWith(color: colors.outline),
                        ),
                      ],
                    ),
                  ),
                )
              else
                for (int i = 0; i < items.length; i++)
                  Reveal(
                    delayMs: i * 60,
                    child: _RequestCard(request: items[i], staffView: false),
                  ),
            ],
          );
        },
      ),
    );
  }
}

class _RequestCard extends StatelessWidget {
  const _RequestCard({required this.request, required this.staffView});
  final EventRequest request;
  final bool staffView;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.m),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.l),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(request.title,
                      style: text.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w700)),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                  decoration: BoxDecoration(
                    color: request.status.color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(request.status.icon,
                          size: 12, color: request.status.color),
                      const SizedBox(width: 4),
                      Text(request.status.label,
                          style: TextStyle(
                              color: request.status.color,
                              fontSize: 11,
                              fontWeight: FontWeight.w700)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text('${request.dateLabel} · ${request.category}',
                style: text.bodySmall?.copyWith(color: colors.outline)),
            if (request.venue.isNotEmpty)
              Text(request.venue,
                  style: text.bodySmall?.copyWith(color: colors.outline)),
            const SizedBox(height: AppSpacing.s),
            Text(request.description, style: text.bodyMedium),
            if (staffView) ...[
              const SizedBox(height: AppSpacing.s),
              Text(
                'Requested by ${request.requestedByName}'
                '${request.contact.isEmpty ? '' : ' · ${request.contact}'}',
                style: text.labelSmall?.copyWith(color: colors.outline),
              ),
            ],
            if (request.staffNote.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.s),
              Container(
                padding: const EdgeInsets.all(AppSpacing.s),
                decoration: BoxDecoration(
                  color: colors.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.chat_bubble_outline,
                        size: 14, color: colors.primary),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text('CCAT: ${request.staffNote}',
                          style: text.bodySmall),
                    ),
                  ],
                ),
              ),
            ],
            if (staffView && request.status == RequestStatus.pending) ...[
              const SizedBox(height: AppSpacing.m),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => _decide(context, RequestStatus.approved),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF2E7D32),
                        foregroundColor: Colors.white,
                      ),
                      icon: const Icon(Icons.check, size: 18),
                      label: const Text('Approve'),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.s),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _decide(context, RequestStatus.declined),
                      style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFFC62828)),
                      icon: const Icon(Icons.close, size: 18),
                      label: const Text('Decline'),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _decide(BuildContext context, RequestStatus status) async {
    final noteCtl = TextEditingController();
    final approved = status == RequestStatus.approved;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(approved ? 'Approve request?' : 'Decline request?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(approved
                ? 'The resident will be told it was approved. You can then '
                    'publish it as an official event.'
                : 'The resident will be told it was declined.'),
            const SizedBox(height: AppSpacing.m),
            TextField(
              controller: noteCtl,
              decoration: const InputDecoration(
                labelText: 'Message to the requester (optional)',
                border: OutlineInputBorder(),
              ),
              maxLines: 2,
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(approved ? 'Approve' : 'Decline'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    await EventRequestService.decide(
        id: request.id, status: status, note: noteCtl.text.trim());

    if (!context.mounted) return;
    if (approved) {
      // Offer to publish it straight away as a real event.
      final publish = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Publish as an event?'),
          content: const Text(
              'Open the event form pre-filled with this request so it appears '
              'in the app for everyone.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Later')),
            FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Publish')),
          ],
        ),
      );
      if (publish == true && context.mounted) {
        await EventsService.save(
          title: request.title,
          description: request.description,
          venue: request.venue,
          category: request.category,
          startsAt: request.proposedDate ?? DateTime.now(),
          status: EventStatus.upcoming,
        );
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Published to the Events page')),
          );
        }
      }
    }
  }
}

// ---------------------------------------------------------------------------
// Resident request form
// ---------------------------------------------------------------------------
class EventRequestFormPage extends StatefulWidget {
  const EventRequestFormPage({super.key});

  @override
  State<EventRequestFormPage> createState() => _EventRequestFormPageState();
}

class _EventRequestFormPageState extends State<EventRequestFormPage> {
  final _formKey = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _desc = TextEditingController();
  final _venue = TextEditingController();
  final _organizer = TextEditingController();
  final _contact = TextEditingController();
  String _category = kEventCategories.first;
  DateTime? _date;
  bool _sending = false;

  @override
  void dispose() {
    _title.dispose();
    _desc.dispose();
    _venue.dispose();
    _organizer.dispose();
    _contact.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _date ?? now.add(const Duration(days: 14)),
      firstDate: now,
      lastDate: DateTime(now.year + 2),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_date == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please propose a date.')),
      );
      return;
    }
    // Screen the free-text fields before anything is uploaded.
    final moderation =
        ContentFilter.check('${_title.text} ${_desc.text} ${_organizer.text}');
    if (!moderation.isClean &&
        moderation.verdict != ModerationVerdict.tooShort) {
      await showDialog(
        context: context,
        builder: (context) => AlertDialog(
          icon: const Icon(Icons.edit_note_outlined,
              color: AppTheme.cityRed, size: 40),
          title: Text(moderation.title),
          content: Text(moderation.message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Edit my request'),
            ),
          ],
        ),
      );
      return;
    }

    setState(() => _sending = true);
    try {
      await EventRequestService.submit(
        title: _title.text.trim(),
        description: _desc.text.trim(),
        venue: _venue.text.trim(),
        category: _category,
        organizer: _organizer.text.trim(),
        contact: _contact.text.trim(),
        proposedDate: _date!,
      );
      if (!mounted) return;
      await showDialog(
        context: context,
        builder: (context) => AlertDialog(
          icon: const Icon(Icons.send_outlined,
              color: AppTheme.brandGold, size: 40),
          title: const Text('Request submitted'),
          content: const Text(
              'CCAT staff have been notified and will review your proposal. '
              'You can track its status here in the app.'),
          actions: [
            FilledButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Done')),
          ],
        ),
      );
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not submit. Check connection.')),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  String? _req(String? v) =>
      (v == null || v.trim().isEmpty) ? 'This field is required' : null;

  String get _dateLabel {
    final d = _date;
    if (d == null) return 'Choose a proposed date';
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${d.day} ${months[d.month - 1]} ${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('New event request')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.l),
          children: [
            Text('Tell CCAT about your activity', style: text.titleMedium),
            const SizedBox(height: AppSpacing.m),
            TextFormField(
              controller: _title,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Event title',
                prefixIcon: Icon(Icons.event_outlined),
                border: OutlineInputBorder(),
              ),
              validator: _req,
            ),
            const SizedBox(height: AppSpacing.m),
            TextFormField(
              controller: _desc,
              maxLines: 4,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'What is it about?',
                alignLabelWithHint: true,
                border: OutlineInputBorder(),
              ),
              validator: _req,
            ),
            const SizedBox(height: AppSpacing.m),
            InkWell(
              onTap: _pickDate,
              child: InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'Proposed date',
                  prefixIcon: Icon(Icons.calendar_today),
                  border: OutlineInputBorder(),
                ),
                child: Text(_dateLabel),
              ),
            ),
            const SizedBox(height: AppSpacing.m),
            TextFormField(
              controller: _venue,
              decoration: const InputDecoration(
                labelText: 'Proposed venue',
                prefixIcon: Icon(Icons.place_outlined),
                border: OutlineInputBorder(),
              ),
              validator: _req,
            ),
            const SizedBox(height: AppSpacing.m),
            DropdownButtonFormField<String>(
              initialValue: _category,
              decoration: const InputDecoration(
                labelText: 'Category',
                prefixIcon: Icon(Icons.label_outline),
                border: OutlineInputBorder(),
              ),
              items: [
                for (final c in kEventCategories)
                  DropdownMenuItem(value: c, child: Text(c)),
              ],
              onChanged: (v) => setState(() => _category = v ?? _category),
            ),
            const SizedBox(height: AppSpacing.m),
            TextFormField(
              controller: _organizer,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Organizer / group',
                prefixIcon: Icon(Icons.groups_outlined),
                border: OutlineInputBorder(),
              ),
              validator: _req,
            ),
            const SizedBox(height: AppSpacing.m),
            TextFormField(
              controller: _contact,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'Contact number',
                prefixIcon: Icon(Icons.phone_outlined),
                border: OutlineInputBorder(),
              ),
              validator: _req,
            ),
            const SizedBox(height: AppSpacing.xl),
            FilledButton.icon(
              onPressed: _sending ? null : _submit,
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.m),
              ),
              icon: _sending
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.send_rounded),
              label: Text(_sending ? 'Submitting…' : 'Submit request'),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Staff side — review incoming requests
// ---------------------------------------------------------------------------
class EventRequestsReviewPage extends StatelessWidget {
  const EventRequestsReviewPage({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Event Requests')),
      body: StreamBuilder<List<EventRequest>>(
        stream: EventRequestService.streamAll(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final items = snap.data ?? [];
          if (items.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.xxl),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.inbox_outlined,
                        size: 52, color: colors.outline),
                    const SizedBox(height: AppSpacing.m),
                    Text('No event requests', style: text.titleMedium),
                  ],
                ),
              ),
            );
          }
          final pending =
              items.where((r) => r.status == RequestStatus.pending).toList();
          final done =
              items.where((r) => r.status != RequestStatus.pending).toList();

          return ListView(
            padding: const EdgeInsets.all(AppSpacing.l),
            children: [
              if (pending.isNotEmpty) ...[
                Text('Awaiting review (${pending.length})',
                    style: text.titleMedium),
                const SizedBox(height: AppSpacing.m),
                for (final r in pending)
                  _RequestCard(request: r, staffView: true),
                const SizedBox(height: AppSpacing.l),
              ],
              if (done.isNotEmpty) ...[
                Text('Reviewed', style: text.titleMedium),
                const SizedBox(height: AppSpacing.m),
                for (final r in done)
                  _RequestCard(request: r, staffView: true),
              ],
            ],
          );
        },
      ),
    );
  }
}
