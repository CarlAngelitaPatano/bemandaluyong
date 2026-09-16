import 'package:flutter/material.dart';

import 'theme.dart';
import 'motion.dart';
import 'tcims_api.dart';

// ===========================================================================
// City Events — created by CCAT staff, cleared by an administrator.
//
// An event a staff member adds here is submitted to the office's shared
// database as PENDING. It appears on the administrator's page on the website,
// where it is approved or rejected; only once approved does it reach the
// public listing in the app or on the site.
//
// These records used to live in Firestore, which the website cannot read — so
// an event created in the app was invisible to the administrator, and there
// was nothing to approve. Both halves now write to the same table.
//
// ---------------------------------------------------------------------------
// COLUMN NAMES are the website's, and differ from this app's older field
// names. The mapping is done in CityEvent.fromRow and EventsService.save:
//
//   app title      -> name
//   app startsAt   -> event_date + start_time (+ month, spelled out)
//   app report     -> post_event_report
//   app attendance -> participants
//
// Two separate ideas share similar words and must not be confused:
//   status           Upcoming | Ongoing | Completed | Cancelled  (the event)
//   approval_status  Pending  | Approved | Rejected              (the office)
// ===========================================================================

const List<String> kEventCategories = [
  'Festival',
  'Religious',
  'Cultural',
  'Sports',
  'Civic / Government',
  'Community',
  'Other',
];

enum EventStatus { upcoming, ongoing, completed, cancelled }

EventStatus eventStatusFromId(String? id) => switch (id) {
      'ongoing' => EventStatus.ongoing,
      'completed' => EventStatus.completed,
      'cancelled' => EventStatus.cancelled,
      _ => EventStatus.upcoming,
    };

extension EventStatusInfo on EventStatus {
  String get id => switch (this) {
        EventStatus.upcoming => 'upcoming',
        EventStatus.ongoing => 'ongoing',
        EventStatus.completed => 'completed',
        EventStatus.cancelled => 'cancelled',
      };

  String get label => switch (this) {
        EventStatus.upcoming => 'Upcoming',
        EventStatus.ongoing => 'Ongoing',
        EventStatus.completed => 'Completed',
        EventStatus.cancelled => 'Cancelled',
      };

  Color get color => switch (this) {
        EventStatus.upcoming => const Color(0xFF1E88E5),
        EventStatus.ongoing => const Color(0xFF2E7D32),
        EventStatus.completed => const Color(0xFF6B7280),
        EventStatus.cancelled => const Color(0xFFC62828),
      };

  IconData get icon => switch (this) {
        EventStatus.upcoming => Icons.event_available_outlined,
        EventStatus.ongoing => Icons.play_circle_outline,
        EventStatus.completed => Icons.check_circle_outline,
        EventStatus.cancelled => Icons.cancel_outlined,
      };
}

/// Whether the office has cleared an event for the public.
///
/// Deliberately separate from [EventStatus]. That one says where an event is in
/// its own life — upcoming, ongoing, finished, called off. This says whether an
/// administrator has agreed it should be visible at all. An event can be
/// Approved and Cancelled at the same time, and the two must never be conflated.
enum EventApproval { pending, approved, rejected }

EventApproval approvalFromId(String? id) => switch (id?.toLowerCase()) {
      'approved' => EventApproval.approved,
      'rejected' => EventApproval.rejected,
      _ => EventApproval.pending,
    };

extension EventApprovalInfo on EventApproval {
  String get label => switch (this) {
        EventApproval.pending => 'Pending approval',
        EventApproval.approved => 'Approved',
        EventApproval.rejected => 'Rejected',
      };

  Color get color => switch (this) {
        EventApproval.pending => const Color(0xFFEF6C00),
        EventApproval.approved => const Color(0xFF2E7D32),
        EventApproval.rejected => const Color(0xFFC62828),
      };

  IconData get icon => switch (this) {
        EventApproval.pending => Icons.hourglass_empty_rounded,
        EventApproval.approved => Icons.verified_rounded,
        EventApproval.rejected => Icons.block_rounded,
      };

  bool get isPublic => this == EventApproval.approved;
}

class CityEvent {
  final String id;
  final String title;
  final String description;
  final String venue;
  final String category;
  final DateTime? startsAt;
  final EventStatus status;
  final String report;
  final int attendance;

  /// Whether an administrator has cleared this for the public.
  final EventApproval approval;

  /// The administrator's reason, when an event was turned down.
  final String approvalRemarks;

  const CityEvent({
    required this.id,
    required this.title,
    required this.description,
    required this.venue,
    required this.category,
    required this.status,
    required this.report,
    required this.attendance,
    this.approval = EventApproval.pending,
    this.approvalRemarks = '',
    this.startsAt,
  });

  /// Builds an event from a `crud.php?table=events` row.
  ///
  /// The column names are the website's, not the app's — `name` rather than
  /// title, `post_event_report` rather than report, `participants` rather than
  /// attendance — and the date arrives split across `event_date` and
  /// `start_time`. Every number comes back as a string through mysqli.
  factory CityEvent.fromRow(Map<String, dynamic> m) {
    DateTime? startsAt;
    final date = (m['event_date'] ?? '').toString().trim();
    if (date.isNotEmpty) {
      final time = (m['start_time'] ?? '00:00:00').toString().trim();
      startsAt = DateTime.tryParse('$date $time') ?? DateTime.tryParse(date);
    }

    return CityEvent(
      id: '${m['id'] ?? ''}',
      title: (m['name'] ?? '').toString(),
      description: (m['description'] ?? '').toString(),
      venue: (m['venue'] ?? '').toString(),
      category: (m['category'] ?? 'Other').toString(),
      startsAt: startsAt,
      // The backend capitalises these; the app's ids are lower case.
      status: eventStatusFromId(m['status']?.toString().toLowerCase()),
      report: (m['post_event_report'] ?? '').toString(),
      attendance: int.tryParse('${m['participants'] ?? ''}') ?? 0,
      approval: approvalFromId(m['approval_status']?.toString()),
      approvalRemarks: (m['approval_remarks'] ?? '').toString(),
    );
  }

  String get dateLabel {
    final d = startsAt;
    if (d == null) return 'Date to be announced';
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
    final ampm = d.hour < 12 ? 'AM' : 'PM';
    final min = d.minute.toString().padLeft(2, '0');
    return '${d.day} ${months[d.month - 1]} ${d.year} · $h:$min $ampm';
  }
}

// ===========================================================================
// Events live in the office's shared database.
//
// They used to be Firestore records, which meant the administrator could not
// see them at all — an event created in the app simply did not exist as far as
// the website was concerned, so there was nothing to approve. They now go to
// the same table the website manages, arriving as Pending until an
// administrator clears them.
//
// The app never decides approval. It is set by the server on submission and
// changed only from the administrator's page; anything this client sends for
// approval_status, submitted_by or approved_by is ignored.
// ===========================================================================
class EventsService {
  EventsService._();

  static const String _path = '/api/crud.php?table=events';

  static const List<String> _monthNames = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ];

  static String _two(int n) => n.toString().padLeft(2, '0');

  /// Events the signed-in account is allowed to see, soonest first.
  ///
  /// A staff token returns everything, including Pending and Rejected, so an
  /// officer can follow their own submissions. Without one the backend returns
  /// only Approved — which is what a visitor should see.
  static Future<List<CityEvent>> list() async {
    final raw = await TcimsApi.get(_path);
    if (raw is! List) return const [];
    final events = <CityEvent>[];
    for (final row in raw) {
      if (row is Map) {
        events.add(CityEvent.fromRow(row.cast<String, dynamic>()));
      }
    }
    events.sort((a, b) => (a.startsAt ?? DateTime(2100))
        .compareTo(b.startsAt ?? DateTime(2100)));
    return events;
  }

  /// Only what the public may see.
  ///
  /// Needed because a staff member browsing the visitor-facing listing carries
  /// a staff token, and would otherwise find unapproved events sitting among
  /// the published ones — including wording still being worked on.
  static Future<List<CityEvent>> listPublic() async =>
      (await list()).where((e) => e.approval.isPublic).toList();

  /// Creates or updates an event. Returns true on success.
  ///
  /// Editing an approved event sends it back to Pending — the backend does
  /// this deliberately, since an event whose date or venue has changed has not
  /// been reviewed in its new form. Callers are expected to say so first.
  static Future<bool> save({
    String? id,
    required String title,
    required String description,
    required String venue,
    required String category,
    required DateTime startsAt,
    required EventStatus status,
    String report = '',
    int attendance = 0,
  }) async {
    // The backend keeps the date and time in separate columns, and wants the
    // month spelled out for the calendar grouping the website renders.
    final body = <String, dynamic>{
      'name': title,
      'description': description,
      'venue': venue,
      'category': category,
      'event_date': '${startsAt.year}-${_two(startsAt.month)}-'
          '${_two(startsAt.day)}',
      'start_time': '${_two(startsAt.hour)}:${_two(startsAt.minute)}:00',
      // No end time is collected in the app, so a conventional three-hour
      // block is assumed rather than sending nothing.
      'end_time': '${_two((startsAt.hour + 3) % 24)}:'
          '${_two(startsAt.minute)}:00',
      'month': _monthNames[startsAt.month - 1],
      // Capitalised label, not the app's lower-case id.
      'status': status.label,
      if (report.trim().isNotEmpty) 'post_event_report': report.trim(),
      if (attendance > 0) 'participants': attendance,
    };

    // approval_status, approval_remarks, submitted_by, approved_by and
    // reported_at are all the server's to set — sending them is pointless and
    // would only suggest the app has a say.
    final res = id == null
        ? await TcimsApi.post(_path, body)
        : await TcimsApi.put('$_path&id=$id', body);

    return res is Map && (res['success'] == true || res['id'] != null);
  }

  /// Files the narrative and headcount after an event has happened.
  ///
  /// The server stamps `reported_at` itself, so the office's clock records
  /// when a report was filed rather than whatever the phone happens to say.
  static Future<bool> fileReport({
    required String id,
    required String report,
    required int participants,
  }) async {
    final res = await TcimsApi.put('$_path&id=$id', {
      'post_event_report': report,
      'participants': participants,
    });
    return res is Map && res['success'] == true;
  }

  static Future<bool> delete(String id) =>
      TcimsApi.delete('$_path&id=$id');
}

// ---------------------------------------------------------------------------
// Staff screen: list + manage events
// ---------------------------------------------------------------------------
class EventsManagerPage extends StatelessWidget {
  const EventsManagerPage({super.key, this.embedded = false});
  final bool embedded;

  @override
  Widget build(BuildContext context) {
    final body = const _EventsManagerBody();
    if (embedded) return body;
    return Scaffold(
      appBar: AppBar(title: const Text('Manage Events')),
      body: body,
    );
  }
}

class _EventsManagerBody extends StatefulWidget {
  const _EventsManagerBody();

  @override
  State<_EventsManagerBody> createState() => _EventsManagerBodyState();
}

class _EventsManagerBodyState extends State<_EventsManagerBody> {
  // A REST list rather than a live stream, so it is reloaded after anything
  // that could have changed it — and after an administrator's decision, which
  // happens on the website and cannot notify this screen.
  late Future<List<CityEvent>> _future = EventsService.list();

  Future<void> _reload() async {
    setState(() => _future = EventsService.list());
    await _future;
  }

  Future<void> _openForm([CityEvent? existing]) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => EventFormPage(existing: existing)),
    );
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openForm(),
        icon: const Icon(Icons.add),
        label: const Text('New event'),
      ),
      body: FutureBuilder<List<CityEvent>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.xl),
                child: Text(
                  'Could not load events. Check that this account is '
                  'registered CCAT staff.',
                  textAlign: TextAlign.center,
                  style: text.bodyMedium,
                ),
              ),
            );
          }
          final events = snap.data ?? [];
          if (events.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.xxl),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.event_outlined,
                        size: 52, color: colors.outline),
                    const SizedBox(height: AppSpacing.m),
                    Text('No events yet', style: text.titleMedium),
                    const SizedBox(height: 4),
                    Text(
                      'Tap "New event" to publish the first city activity.',
                      textAlign: TextAlign.center,
                      style: text.bodySmall
                          ?.copyWith(color: colors.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            );
          }

          final waiting =
              events.where((e) => e.approval == EventApproval.pending).length;

          return RefreshIndicator(
            onRefresh: _reload,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.l, AppSpacing.l, AppSpacing.l, 90),
              children: [
                Text('${events.length} event${events.length == 1 ? '' : 's'}',
                    style: text.titleMedium),
                if (waiting > 0) ...[
                  const SizedBox(height: 2),
                  Text(
                    '$waiting waiting for the administrator to approve',
                    style: text.bodySmall
                        ?.copyWith(color: const Color(0xFFEF6C00)),
                  ),
                ],
                const SizedBox(height: AppSpacing.m),
                for (int i = 0; i < events.length; i++)
                  Reveal(
                    delayMs: i * 50,
                    child: _EventCard(
                      event: events[i],
                      onEdit: () => _openForm(events[i]),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// A small pill: an icon, a word, one colour.
class _Pill extends StatelessWidget {
  const _Pill({required this.icon, required this.label, required this.color});
  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(99),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 4),
            Text(label,
                style: TextStyle(
                    color: color, fontSize: 11, fontWeight: FontWeight.w700)),
          ],
        ),
      );
}

class _EventCard extends StatelessWidget {
  const _EventCard({required this.event, required this.onEdit});
  final CityEvent event;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.m),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.md),
        onTap: onEdit,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.l),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(event.title,
                        style: text.titleSmall
                            ?.copyWith(fontWeight: FontWeight.w700)),
                  ),
                  _Pill(
                    icon: event.status.icon,
                    label: event.status.label,
                    color: event.status.color,
                  ),
                ],
              ),
              const SizedBox(height: 6),
              // Whether the office has cleared it — the thing a staff member
              // most wants to know after submitting, and separate from how the
              // event itself is going.
              Row(
                children: [
                  _Pill(
                    icon: event.approval.icon,
                    label: event.approval.label,
                    color: event.approval.color,
                  ),
                ],
              ),
              if (event.approval == EventApproval.rejected &&
                  event.approvalRemarks.trim().isNotEmpty) ...[
                const SizedBox(height: 6),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(AppSpacing.s),
                  decoration: BoxDecoration(
                    color: const Color(0xFFC62828).withValues(alpha: 0.07),
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                  child: Text(
                    'Administrator: ${event.approvalRemarks.trim()}',
                    style: text.bodySmall
                        ?.copyWith(color: const Color(0xFFC62828)),
                  ),
                ),
              ],
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(Icons.schedule, size: 13, color: colors.outline),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(event.dateLabel,
                        style: text.bodySmall
                            ?.copyWith(color: colors.onSurfaceVariant)),
                  ),
                ],
              ),
              if (event.venue.isNotEmpty) ...[
                const SizedBox(height: 2),
                Row(
                  children: [
                    Icon(Icons.place_outlined,
                        size: 13, color: colors.outline),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Text(event.venue,
                          style: text.bodySmall
                              ?.copyWith(color: colors.onSurfaceVariant)),
                    ),
                  ],
                ),
              ],
              if (event.report.isNotEmpty) ...[
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
                      Icon(Icons.description_outlined,
                          size: 14, color: colors.primary),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          event.attendance > 0
                              ? '${event.report}  ·  ~${event.attendance} attendees'
                              : event.report,
                          style: text.bodySmall,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Create / edit an event (and file its report)
// ---------------------------------------------------------------------------
class EventFormPage extends StatefulWidget {
  const EventFormPage({super.key, this.existing});
  final CityEvent? existing;

  @override
  State<EventFormPage> createState() => _EventFormPageState();
}

class _EventFormPageState extends State<EventFormPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _title;
  late final TextEditingController _desc;
  late final TextEditingController _venue;
  late final TextEditingController _report;
  late final TextEditingController _attendance;
  late String _category;
  late EventStatus _status;
  DateTime? _startsAt;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _title = TextEditingController(text: e?.title ?? '');
    _desc = TextEditingController(text: e?.description ?? '');
    _venue = TextEditingController(text: e?.venue ?? '');
    _report = TextEditingController(text: e?.report ?? '');
    _attendance = TextEditingController(
        text: (e?.attendance ?? 0) > 0 ? '${e!.attendance}' : '');
    _category = e?.category ?? kEventCategories.first;
    _status = e?.status ?? EventStatus.upcoming;
    _startsAt = e?.startsAt;
  }

  /// The categories to offer, including whatever this event already has.
  ///
  /// The app ships a short list — Festival, Religious, Cultural and so on —
  /// but the office's events table has its own vocabulary built up over time,
  /// with values like "Morning Programs" that the app has never heard of.
  /// Opening such an event crashed the form outright: a DropdownButton asserts
  /// that its current value appears exactly once among its items.
  ///
  /// The existing value is kept rather than replaced, because quietly
  /// rewriting an event's category to "Other" just for being opened would edit
  /// the office's record without anyone asking.
  List<String> get _categoryOptions {
    if (kEventCategories.contains(_category)) return kEventCategories;
    return [_category, ...kEventCategories];
  }

  @override
  void dispose() {
    _title.dispose();
    _desc.dispose();
    _venue.dispose();
    _report.dispose();
    _attendance.dispose();
    super.dispose();
  }

  Future<void> _pickDateTime() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: _startsAt ?? now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 5),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_startsAt ?? now),
    );
    if (!mounted) return;
    setState(() {
      _startsAt = DateTime(
        date.year,
        date.month,
        date.day,
        time?.hour ?? 8,
        time?.minute ?? 0,
      );
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_startsAt == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please set the event date and time.')),
      );
      return;
    }
    // Editing an approved event returns it to Pending — the office has to
    // look again at an event whose date or venue has moved. Said plainly
    // beforehand, because otherwise it reads as the event vanishing.
    if (widget.existing?.approval == EventApproval.approved) {
      final go = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          icon: const Icon(Icons.info_outline, size: 36),
          title: const Text('This will need approval again'),
          content: const Text(
            'This event has already been approved and is visible to the '
            'public. Saving a change sends it back to the administrator for '
            'review, and it will be hidden from the public listing until it '
            'is approved again.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Save anyway'),
            ),
          ],
        ),
      );
      if (go != true || !mounted) return;
    }

    setState(() => _saving = true);
    try {
      final ok = await EventsService.save(
        id: widget.existing?.id,
        title: _title.text.trim(),
        description: _desc.text.trim(),
        venue: _venue.text.trim(),
        category: _category,
        startsAt: _startsAt!,
        status: _status,
        report: _report.text.trim(),
        attendance: int.tryParse(_attendance.text.trim()) ?? 0,
      );
      if (!mounted) return;

      if (!ok) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            duration: Duration(seconds: 5),
            content: Text(
              'Could not save the event. Check your connection, and that '
              'this account is registered as CCAT Staff.',
            ),
          ),
        );
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 5),
          // Never says "published" any more: the office decides that, not the
          // app, and claiming otherwise would be a promise it cannot keep.
          content: Text(widget.existing == null
              ? 'Event submitted — waiting for the administrator to approve it'
              : 'Event updated — it goes back to the administrator for review'),
        ),
      );
      Navigator.pop(context);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not save. Check your connection.')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _confirmDelete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this event?'),
        content: const Text('It will be removed from the app for everyone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFC62828)),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final gone = await EventsService.delete(widget.existing!.id);
    if (!mounted) return;
    if (!gone) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not delete the event.')),
      );
      return;
    }
    Navigator.pop(context);
  }

  String get _dateLabel {
    final d = _startsAt;
    if (d == null) return 'Set date and time';
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
    final ampm = d.hour < 12 ? 'AM' : 'PM';
    return '${d.day} ${months[d.month - 1]} ${d.year} · $h:'
        '${d.minute.toString().padLeft(2, '0')} $ampm';
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final editing = widget.existing != null;

    return Scaffold(
      appBar: AppBar(
        title: Text(editing ? 'Edit event' : 'New event'),
        actions: [
          if (editing)
            IconButton(
              tooltip: 'Delete',
              icon: const Icon(Icons.delete_outline),
              onPressed: _confirmDelete,
            ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.l),
          children: [
            Text('Event details', style: text.titleMedium),
            const SizedBox(height: AppSpacing.m),
            TextFormField(
              controller: _title,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Event title',
                prefixIcon: Icon(Icons.event_outlined),
                border: OutlineInputBorder(),
              ),
              validator: (v) => (v == null || v.trim().isEmpty)
                  ? 'Enter the event title'
                  : null,
            ),
            const SizedBox(height: AppSpacing.m),
            TextFormField(
              controller: _desc,
              maxLines: 4,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Description',
                alignLabelWithHint: true,
                border: OutlineInputBorder(),
              ),
              validator: (v) => (v == null || v.trim().isEmpty)
                  ? 'Describe the event'
                  : null,
            ),
            const SizedBox(height: AppSpacing.m),
            TextFormField(
              controller: _venue,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Venue',
                prefixIcon: Icon(Icons.place_outlined),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: AppSpacing.m),
            InkWell(
              onTap: _pickDateTime,
              child: InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'Date & time',
                  prefixIcon: Icon(Icons.schedule),
                  border: OutlineInputBorder(),
                  suffixIcon: Icon(Icons.calendar_today, size: 18),
                ),
                child: Text(_dateLabel),
              ),
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
                for (final c in _categoryOptions)
                  DropdownMenuItem(value: c, child: Text(c)),
              ],
              onChanged: (v) => setState(() => _category = v ?? _category),
            ),
            const SizedBox(height: AppSpacing.m),
            DropdownButtonFormField<EventStatus>(
              initialValue: _status,
              decoration: const InputDecoration(
                labelText: 'Status',
                prefixIcon: Icon(Icons.flag_outlined),
                border: OutlineInputBorder(),
              ),
              items: [
                for (final s in EventStatus.values)
                  DropdownMenuItem(value: s, child: Text(s.label)),
              ],
              onChanged: (v) => setState(() => _status = v ?? _status),
            ),

            const SizedBox(height: AppSpacing.xxl),
            Text('Event report', style: text.titleMedium),
            const SizedBox(height: 2),
            Text(
              'Fill this in after the event for the office\'s records. '
              'It is not shown to the public.',
              style: text.bodySmall,
            ),
            const SizedBox(height: AppSpacing.m),
            TextFormField(
              controller: _report,
              maxLines: 4,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Report / notes',
                hintText: 'How did it go? Any issues or highlights?',
                alignLabelWithHint: true,
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: AppSpacing.m),
            TextFormField(
              controller: _attendance,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Estimated attendance',
                prefixIcon: Icon(Icons.groups_outlined),
                border: OutlineInputBorder(),
              ),
            ),

            const SizedBox(height: AppSpacing.xl),
            FilledButton.icon(
              onPressed: _saving ? null : _save,
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.m),
              ),
              icon: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.publish),
              label: Text(_saving
                  ? 'Saving…'
                  : (editing ? 'Save changes' : 'Publish event')),
            ),
          ],
        ),
      ),
    );
  }
}
