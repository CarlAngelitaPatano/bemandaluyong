import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'theme.dart';
import 'motion.dart';

// ===========================================================================
// City Events — managed by CCAT staff.
//
// Staff create and update events in the shared Firestore database, so new
// festivals and activities appear in the app immediately without a rebuild.
// After an event they can also file a short report (attendance, outcome,
// notes) for the office's records.
//
// ---------------------------------------------------------------------------
// SHARED SCHEMA — collection `events`
//   title, description, venue, category
//   startsAt      timestamp
//   status        'upcoming' | 'ongoing' | 'completed' | 'cancelled'
//   report        string   post-event notes (optional)
//   attendance    number   estimated turnout (optional)
//   createdBy     string   staff email
//   createdAt / updatedAt  timestamp
// ===========================================================================

const String kEventsCollection = 'events';

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

  const CityEvent({
    required this.id,
    required this.title,
    required this.description,
    required this.venue,
    required this.category,
    required this.status,
    required this.report,
    required this.attendance,
    this.startsAt,
  });

  factory CityEvent.fromDoc(QueryDocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data();
    final ts = m['startsAt'];
    return CityEvent(
      id: d.id,
      title: (m['title'] ?? '').toString(),
      description: (m['description'] ?? '').toString(),
      venue: (m['venue'] ?? '').toString(),
      category: (m['category'] ?? 'Other').toString(),
      startsAt: ts is Timestamp ? ts.toDate() : null,
      status: eventStatusFromId(m['status']?.toString()),
      report: (m['report'] ?? '').toString(),
      attendance: (m['attendance'] as num?)?.toInt() ?? 0,
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

class EventsService {
  EventsService._();

  /// All events, soonest first.
  static Stream<List<CityEvent>> stream() => FirebaseFirestore.instance
      .collection(kEventsCollection)
      .orderBy('startsAt')
      .snapshots()
      .map((s) => s.docs.map(CityEvent.fromDoc).toList());

  static Future<void> save({
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
    final data = {
      'title': title,
      'description': description,
      'venue': venue,
      'category': category,
      'startsAt': Timestamp.fromDate(startsAt),
      'status': status.id,
      'report': report,
      'attendance': attendance,
      'updatedAt': FieldValue.serverTimestamp(),
      'createdBy': FirebaseAuth.instance.currentUser?.email ?? '',
    };
    final col = FirebaseFirestore.instance.collection(kEventsCollection);
    if (id == null) {
      await col.add({...data, 'createdAt': FieldValue.serverTimestamp()});
    } else {
      await col.doc(id).update(data);
    }
  }

  static Future<void> delete(String id) =>
      FirebaseFirestore.instance.collection(kEventsCollection).doc(id).delete();
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

class _EventsManagerBody extends StatelessWidget {
  const _EventsManagerBody();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const EventFormPage()),
        ),
        icon: const Icon(Icons.add),
        label: const Text('New event'),
      ),
      body: StreamBuilder<List<CityEvent>>(
        stream: EventsService.stream(),
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
                          ?.copyWith(color: colors.outline),
                    ),
                  ],
                ),
              ),
            );
          }

          return ListView(
            padding: const EdgeInsets.fromLTRB(
                AppSpacing.l, AppSpacing.l, AppSpacing.l, 90),
            children: [
              Text('${events.length} event${events.length == 1 ? '' : 's'}',
                  style: text.titleMedium),
              const SizedBox(height: AppSpacing.m),
              for (int i = 0; i < events.length; i++)
                Reveal(
                  delayMs: i * 50,
                  child: _EventCard(event: events[i]),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _EventCard extends StatelessWidget {
  const _EventCard({required this.event});
  final CityEvent event;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.m),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.md),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => EventFormPage(existing: event)),
        ),
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
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 9, vertical: 3),
                    decoration: BoxDecoration(
                      color: event.status.color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(99),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(event.status.icon,
                            size: 12, color: event.status.color),
                        const SizedBox(width: 4),
                        Text(event.status.label,
                            style: TextStyle(
                                color: event.status.color,
                                fontSize: 11,
                                fontWeight: FontWeight.w700)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(Icons.schedule, size: 13, color: colors.outline),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(event.dateLabel,
                        style: text.bodySmall
                            ?.copyWith(color: colors.outline)),
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
                              ?.copyWith(color: colors.outline)),
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
    setState(() => _saving = true);
    try {
      await EventsService.save(
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(widget.existing == null
              ? 'Event published — it now appears in the app'
              : 'Event updated'),
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
    await EventsService.delete(widget.existing!.id);
    if (mounted) Navigator.pop(context);
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
                for (final c in kEventCategories)
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
