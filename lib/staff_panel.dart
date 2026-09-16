import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'theme.dart';
import 'motion.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'events_manager.dart';
import 'announcements.dart';
import 'analytics_dashboard.dart';
import 'event_requests.dart';
import 'staff_report.dart';
import 'local_notifs.dart';
import 'staff_access.dart' show kAnnouncementPublisher;
import 'tcims_api.dart'; // reviews come from the shared database, not Firestore

// ===========================================================================
// CCAT Staff console.
//
// The staff tier handles day-to-day operations:
//   • create and update city events, and file post-event reports
//   • publish announcements to every app user
//   • read visitor feedback from tourists and Mandaleños
//
// Accreditation decisions and user records stay with administrators.
// ===========================================================================

/// Watches the two things staff need to know about, and raises a phone
/// notification the first time each one is seen:
///   • a Mandaleño submitted an event request
///   • a visitor left new feedback and a rating
class StaffAlerts {
  StaffAlerts._();

  static const String _seenKey = 'staff_seen_alert_ids';

  static Future<Set<String>> _seen() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList(_seenKey) ?? const <String>[]).toSet();
  }

  static Future<void> _markSeen(Iterable<String> ids) async {
    final prefs = await SharedPreferences.getInstance();
    final all = (prefs.getStringList(_seenKey) ?? <String>[]).toSet()
      ..addAll(ids);
    await prefs.setStringList(_seenKey, all.toList());
  }

  /// Checks all three sources and notifies about anything new.
  static Future<void> check() async {
    try {
      final db = FirebaseFirestore.instance;
      final seen = await _seen();
      final fresh = <String>[];
      final messages = <({String title, String body})>[];

      // 1. New community event requests
      final reqs = await db
          .collection(kEventRequestCollection)
          .where('status', isEqualTo: 'pending')
          .get();
      for (final d in reqs.docs) {
        final key = 'req_${d.id}';
        if (seen.contains(key)) continue;
        fresh.add(key);
        messages.add((
          title: 'New event request',
          body: '${d.data()['requestedByName'] ?? 'A resident'} proposed '
              '"${d.data()['title'] ?? 'an activity'}"',
        ));
      }

      // 2. New visitor feedback
      final fb = await db
          .collection('feedback')
          .orderBy('createdAt', descending: true)
          .limit(20)
          .get();
      for (final d in fb.docs) {
        final key = 'fb_${d.id}';
        if (seen.contains(key)) continue;
        fresh.add(key);
        final m = d.data();
        final rating = (m['rating'] as num?)?.toInt() ?? 0;
        final sentiment = (m['sentiment'] ?? '').toString();
        messages.add((
          title: 'New feedback · rating $rating of 5'
              '${sentiment.isEmpty ? '' : ' · $sentiment'}',
          body: (m['message'] ?? '').toString(),
        ));
      }

      if (fresh.isEmpty) return;

      // First run: remember everything quietly instead of a burst of alerts.
      if (seen.isEmpty) {
        await _markSeen(fresh);
        return;
      }

      for (final m in messages.take(4)) {
        await LocalNotifs.showNow(
          title: m.title,
          body: m.body.length > 120 ? '${m.body.substring(0, 117)}…' : m.body,
        );
      }
      await _markSeen(fresh);
    } catch (_) {
      // Permissions or connectivity — alerts are best-effort.
    }
  }
}

/// How far back the console's figures look.
///
/// Queues — pending requests, unfiled reports, upcoming events — are not
/// filtered by this: an event request from two months ago is still waiting
/// today. It applies to what was *received* in a period, which is what an
/// officer is reporting on when they say what happened.
enum StaffPeriod {
  week('This week', 7),
  month('This month', 30),
  all('All time', 0);

  const StaffPeriod(this.label, this.days);
  final String label;
  final int days;

  /// Null for [all] — everything counts.
  DateTime? get since => days == 0
      ? null
      : DateTime.now().subtract(Duration(days: days));
}

/// One review, as the console needs it.
class _Review {
  const _Review({
    required this.id,
    required this.place,
    required this.comment,
    required this.sentiment,
    required this.rating,
    required this.createdAt,
  });

  final String id;
  final String place;
  final String comment;
  final String sentiment; // lowercase: positive / neutral / negative
  final int rating;
  final DateTime? createdAt;

  bool get isNegative => sentiment == 'negative';
}

class StaffHomeView extends StatefulWidget {
  const StaffHomeView({super.key});

  @override
  State<StaffHomeView> createState() => _StaffHomeViewState();
}

class _StaffHomeViewState extends State<StaffHomeView> {
  int? _upcoming;
  int? _needsReport;
  int? _requests;

  /// Events submitted but not yet cleared by the administrator.
  int _awaitingApproval = 0;

  /// Every review the office holds. Filtered by [_period] for display, so
  /// changing the period costs nothing — no second request.
  List<_Review>? _reviews;

  /// Negative reviews the staff member has already dealt with.
  Set<String> _handled = <String>{};

  StaffPeriod _period = StaffPeriod.week;

  static const String _handledKey = 'staff_handled_reviews';

  /// Reviews inside the chosen period.
  List<_Review> get _inPeriod {
    final all = _reviews ?? const <_Review>[];
    final since = _period.since;
    if (since == null) return all;
    return all
        .where((r) => r.createdAt != null && r.createdAt!.isAfter(since))
        .toList();
  }

  int? get _feedback => _reviews == null ? null : _inPeriod.length;
  int get _positive =>
      _inPeriod.where((r) => r.sentiment == 'positive').length;
  int get _negative => _inPeriod.where((r) => r.isNegative).length;
  int get _neutral => _inPeriod.length - _positive - _negative;

  /// Negative reviews in the period that nobody has marked as handled —
  /// the actual work, as opposed to the count.
  List<_Review> get _needsAttention => _inPeriod
      .where((r) => r.isNegative && !_handled.contains(r.id))
      .toList()
    ..sort((a, b) => (b.createdAt ?? DateTime(1970))
        .compareTo(a.createdAt ?? DateTime(1970)));

  @override
  void initState() {
    super.initState();
    _load();
    StaffAlerts.check(); // notify about new requests, feedback, decisions
  }

  Future<void> _load() async {
    // Events and requests are Firestore records; feedback is not. Reviews live
    // in the office's shared database, the same rows the website reports on —
    // this tile used to count a Firestore collection that stopped being the
    // real source, so the dashboard and the screen it opened disagreed.
    await Future.wait([_loadFirestore(), _loadFeedback()]);
  }

  Future<void> _loadFirestore() async {
    try {
      // Requests are still the app's own Firestore records; events moved to
      // the shared database when they gained an approval step.
      final pending = await FirebaseFirestore.instance
          .collection(kEventRequestCollection)
          .where('status', isEqualTo: 'pending')
          .get();
      final events = await EventsService.list();
      if (!mounted) return;
      setState(() {
        _upcoming =
            events.where((e) => e.status == EventStatus.upcoming).length;
        // Finished events that still have no report filed.
        _needsReport = events
            .where((e) =>
                e.status == EventStatus.completed && e.report.trim().isEmpty)
            .length;
        // Events the office has not yet cleared — work the staff member is
        // waiting on rather than work they owe.
        _awaitingApproval =
            events.where((e) => e.approval == EventApproval.pending).length;
        _requests = pending.docs.length;
      });
    } catch (_) {
      // Permission or connectivity — tiles show a dash.
    }
  }

  Future<void> _loadFeedback() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final handled = prefs.getStringList(_handledKey)?.toSet() ?? <String>{};

      final rows = await TcimsApi.get('/api/crud.php?table=reviews');
      if (rows is! List || !mounted) return;

      final parsed = <_Review>[];
      for (final r in rows) {
        if (r is! Map) continue;
        final place = (r['place'] ?? '').toString();
        parsed.add(_Review(
          id: '${r['id'] ?? ''}',
          place: place.isEmpty ? 'General' : place,
          comment: (r['comment'] ?? '').toString(),
          // The server's label, which is what the website shows for the same
          // review. ml_sentiment is a shadow experiment and is not used here.
          sentiment: (r['sentiment'] ?? 'neutral').toString().toLowerCase(),
          // mysqli returns every column as a string.
          rating: int.tryParse('${r['rating'] ?? ''}') ?? 0,
          // UTC on the server, unmarked — see TcimsApi.parseServerTime. This
          // drives the week/month filter and the "2 days ago" labels, so an
          // eight-hour error here moved reviews across day boundaries.
          createdAt: TcimsApi.parseServerTime(r['created_at']),
        ));
      }

      setState(() {
        _reviews = parsed;
        _handled = handled;
      });
    } catch (_) {
      // Offline, or the account is not permitted to read reviews — the tile
      // keeps its dash rather than showing a zero that reads as "no feedback".
    }
  }

  /// Marks a complaint as dealt with. Kept on the device rather than the
  /// server: it records that *this officer* has seen it, which is a personal
  /// working note, not a change to the review itself.
  Future<void> _markHandled(String id) async {
    setState(() => _handled = {..._handled, id});
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_handledKey, _handled.toList());
  }

  void _open(Widget page) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => page))
        .then((_) => _load());
  }

  /// One-line summary of what needs doing today.
  String _workloadLine() {
    if (_requests == null) return 'Loading your workload…';
    final complaints = _needsAttention.length;
    final parts = <String>[];
    if ((_requests ?? 0) > 0) {
      parts.add('$_requests request${_requests == 1 ? '' : 's'}');
    }
    if ((_needsReport ?? 0) > 0) {
      parts.add('$_needsReport report${_needsReport == 1 ? '' : 's'}');
    }
    // An unanswered complaint is work too — it used to be left out of this
    // line entirely, so the header could say "all caught up" while people
    // were waiting on a reply.
    if (complaints > 0) {
      parts.add('$complaints complaint${complaints == 1 ? '' : 's'}');
    }
    if (parts.isEmpty) return 'Nothing pending — you\'re all caught up';
    return '${parts.join(' · ')} waiting for you';
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final name = FirebaseAuth.instance.currentUser?.displayName;
    final hour = DateTime.now().hour;
    final greeting = hour < 12
        ? 'Good morning'
        : (hour < 18 ? 'Good afternoon' : 'Good evening');

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(AppSpacing.l),
        children: [
          // ---- Staff header ----
          Reveal(
            delayMs: 0,
            child: Container(
              padding: const EdgeInsets.all(AppSpacing.xl),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF12305F), Color(0xFF1E4B8F)],
                ),
                borderRadius: BorderRadius.circular(AppRadius.xl),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF12305F).withValues(alpha: 0.22),
                    blurRadius: 14,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 46,
                        height: 46,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                          border: Border.all(
                              color: AppTheme.brandGold.withValues(alpha: 0.7),
                              width: 1.5),
                        ),
                        child: const Icon(Icons.badge_outlined,
                            color: Colors.white, size: 22),
                      ),
                      const SizedBox(width: AppSpacing.m),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'CCAT STAFF',
                              style: text.labelSmall?.copyWith(
                                color: AppTheme.brandGold,
                                letterSpacing: 1.2,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              (name == null || name.trim().isEmpty)
                                  ? 'Staff member'
                                  : name.trim(),
                              style: text.titleLarge?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.l),
                  Container(
                    width: 44,
                    height: 3,
                    decoration: BoxDecoration(
                      color: AppTheme.brandGold,
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.m),
                  Row(
                    children: [
                      Icon(Icons.wb_sunny_outlined,
                          size: 15,
                          color: Colors.white.withValues(alpha: 0.75)),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          '$greeting · ${_today()}',
                          style: text.bodySmall?.copyWith(
                              color: Colors.white.withValues(alpha: 0.85)),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(Icons.task_alt,
                          size: 15,
                          color: Colors.white.withValues(alpha: 0.75)),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          _workloadLine(),
                          style: text.bodySmall?.copyWith(
                              color: Colors.white.withValues(alpha: 0.85)),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.l),

          // ---- Community requests waiting ----
          if ((_requests ?? 0) > 0)
            Reveal(
              delayMs: 30,
              child: Container(
                margin: const EdgeInsets.only(bottom: AppSpacing.m),
                padding: const EdgeInsets.all(AppSpacing.m),
                decoration: BoxDecoration(
                  color: colors.primary.withValues(alpha: 0.07),
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  border: Border.all(
                      color: colors.primary.withValues(alpha: 0.35)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.inbox_rounded, color: colors.primary, size: 20),
                    const SizedBox(width: AppSpacing.s),
                    Expanded(
                      child: Text(
                        '$_requests event request'
                        '${_requests == 1 ? '' : 's'} from residents',
                        style: text.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: colors.primary),
                      ),
                    ),
                    TextButton(
                      onPressed: () =>
                          _open(const EventRequestsReviewPage()),
                      child: const Text('Review'),
                    ),
                  ],
                ),
              ),
            ),

          // ---- Waiting on the administrator ----
          // Not the officer's work, but they should know it is sitting there
          // rather than wondering why an event never appeared publicly.
          if (_awaitingApproval > 0)
            Reveal(
              delayMs: 35,
              child: Container(
                margin: const EdgeInsets.only(bottom: AppSpacing.m),
                padding: const EdgeInsets.all(AppSpacing.m),
                decoration: BoxDecoration(
                  color: AppTheme.brandGold.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  border: Border.all(
                      color: AppTheme.brandGold.withValues(alpha: 0.5)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.hourglass_empty_rounded,
                        color: Color(0xFF8A6A00), size: 20),
                    const SizedBox(width: AppSpacing.s),
                    Expanded(
                      child: Text(
                        '$_awaitingApproval event'
                        '${_awaitingApproval == 1 ? '' : 's'} waiting for the '
                        'administrator to approve',
                        style: text.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFF8A6A00)),
                      ),
                    ),
                    TextButton(
                      onPressed: () => _open(const EventsManagerPage()),
                      child: const Text('View'),
                    ),
                  ],
                ),
              ),
            ),

          // ---- Reports outstanding ----
          if ((_needsReport ?? 0) > 0)
            Reveal(
              delayMs: 40,
              child: Container(
                margin: const EdgeInsets.only(bottom: AppSpacing.l),
                padding: const EdgeInsets.all(AppSpacing.m),
                decoration: BoxDecoration(
                  color: const Color(0xFFEF6C00).withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  border: Border.all(
                      color: const Color(0xFFEF6C00).withValues(alpha: 0.4)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.edit_note_rounded,
                        color: Color(0xFFEF6C00), size: 20),
                    const SizedBox(width: AppSpacing.s),
                    Expanded(
                      child: Text(
                        '$_needsReport completed event'
                        '${_needsReport == 1 ? '' : 's'} still need a report',
                        style: text.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFFEF6C00)),
                      ),
                    ),
                    TextButton(
                      onPressed: () => _open(const EventsManagerPage()),
                      child: const Text('File'),
                    ),
                  ],
                ),
              ),
            ),

          // ---- Complaints waiting on someone ----
          // Placed above the numbers on purpose: a count of negative reviews
          // is information, but an unanswered complaint is work.
          if (_needsAttention.isNotEmpty) ...[
            Reveal(
              delayMs: 50,
              child: _AttentionList(
                reviews: _needsAttention,
                onHandled: _markHandled,
                onOpen: () => _open(const AnalyticsDashboardPage()),
              ),
            ),
            const SizedBox(height: AppSpacing.l),
          ],

          // ---- Metrics ----
          Reveal(
            delayMs: 60,
            child: Row(
              children: [
                Expanded(
                  child: Text('AT A GLANCE',
                      style: text.labelSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.0,
                        color: colors.outline,
                      )),
                ),
                // What "received" counts. Queues below are unaffected — a
                // request from last month is still waiting today.
                DropdownButton<StaffPeriod>(
                  value: _period,
                  underline: const SizedBox.shrink(),
                  isDense: true,
                  style: text.labelMedium?.copyWith(color: colors.primary),
                  items: [
                    for (final p in StaffPeriod.values)
                      DropdownMenuItem(value: p, child: Text(p.label)),
                  ],
                  onChanged: (p) {
                    if (p != null) setState(() => _period = p);
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.m),
          Reveal(
            delayMs: 90,
            child: Row(
              children: [
                _StaffStat(
                  label: 'Upcoming events',
                  value: _upcoming?.toString() ?? '—',
                  icon: Icons.event_available_outlined,
                  onTap: () => _open(const EventsManagerPage()),
                ),
                const SizedBox(width: AppSpacing.m),
                _StaffStat(
                  label: 'Feedback · ${_period.label.toLowerCase()}',
                  value: _feedback?.toString() ?? '—',
                  icon: Icons.forum_outlined,
                  onTap: () => _open(const AnalyticsDashboardPage()),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.m),
          Reveal(
            delayMs: 120,
            child: Row(
              children: [
                _StaffStat(
                  label: 'Event requests',
                  value: _requests?.toString() ?? '—',
                  icon: Icons.inbox_outlined,
                  highlight: (_requests ?? 0) > 0,
                  onTap: () => _open(const EventRequestsReviewPage()),
                ),
                const SizedBox(width: AppSpacing.m),
                _StaffStat(
                  label: 'Reports pending',
                  value: _needsReport?.toString() ?? '—',
                  icon: Icons.edit_note_outlined,
                  highlight: (_needsReport ?? 0) > 0,
                  onTap: () => _open(const EventsManagerPage()),
                ),
              ],
            ),
          ),
          // A one-line read on how visitors are feeling. Tapping opens the
          // full breakdown.
          if ((_feedback ?? 0) > 0) ...[
            const SizedBox(height: AppSpacing.m),
            Reveal(
              delayMs: 140,
              child: _SentimentBar(
                positive: _positive,
                neutral: _neutral,
                negative: _negative,
                onTap: () => _open(const AnalyticsDashboardPage()),
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.xxl),

          // ---- Tasks ----
          Reveal(
            delayMs: 160,
            child: Text('MY WORK',
                style: text.labelSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.0,
                  color: colors.outline,
                )),
          ),
          const SizedBox(height: AppSpacing.m),
          Reveal(
            delayMs: 190,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppRadius.lg),
                border: Border.all(color: colors.outlineVariant),
              ),
              child: Column(
                children: [
                  _WorkRow(
                    icon: Icons.event_note_outlined,
                    title: 'Manage events',
                    subtitle: 'Add activities and file post-event reports',
                    onTap: () => _open(const EventsManagerPage()),
                  ),
                  Divider(height: 1, color: colors.outlineVariant),
                  _WorkRow(
                    icon: Icons.inbox_outlined,
                    title: 'Event requests',
                    subtitle: 'Proposals from Mandaleño residents',
                    onTap: () => _open(const EventRequestsReviewPage()),
                  ),
                  Divider(height: 1, color: colors.outlineVariant),
                  _WorkRow(
                    icon: Icons.campaign_outlined,
                    title: 'Publish an announcement',
                    subtitle: 'Notify every app user instantly',
                    onTap: () => _open(const StaffAnnouncementPage()),
                  ),
                  Divider(height: 1, color: colors.outlineVariant),
                  _WorkRow(
                    icon: Icons.insights_outlined,
                    title: 'Visitor feedback',
                    subtitle: 'What tourists and Mandaleños are saying',
                    onTap: () => _open(const AnalyticsDashboardPage()),
                  ),
                  Divider(height: 1, color: colors.outlineVariant),
                  _WorkRow(
                    icon: Icons.picture_as_pdf_outlined,
                    title: 'Generate report',
                    subtitle: 'Printable PDF or CSV to send the administrator',
                    onTap: () => _open(const StaffReportPage()),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          Center(
            child: Text('Be@Mandaluyong · Staff Console',
                style: text.labelSmall?.copyWith(color: colors.onSurfaceVariant)),
          ),
        ],
      ),
    );
  }
}

String _today() {
  const months = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December'
  ];
  final d = DateTime.now();
  return '${d.day} ${months[d.month - 1]} ${d.year}';
}

/// The complaints nobody has dealt with yet.
///
/// A dashboard that reports "12 negative" tells an officer there is a problem
/// but not what it is. This lists them — the place, when, and what was said —
/// so the screen holds work rather than a statistic, and each one can be
/// ticked off once it has been looked into.
class _AttentionList extends StatelessWidget {
  const _AttentionList({
    required this.reviews,
    required this.onHandled,
    required this.onOpen,
  });

  final List<_Review> reviews;
  final ValueChanged<String> onHandled;
  final VoidCallback onOpen;

  String _when(DateTime? d) {
    if (d == null) return '';
    final days = DateTime.now().difference(d).inDays;
    if (days == 0) return 'today';
    if (days == 1) return 'yesterday';
    if (days < 7) return '$days days ago';
    return '${d.day}/${d.month}';
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    // Three at a time — a wall of complaints is as unhelpful as a number.
    final shown = reviews.take(3).toList();

    return Container(
      padding: const EdgeInsets.all(AppSpacing.l),
      decoration: BoxDecoration(
        color: AppTheme.cityRed.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppTheme.cityRed.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.report_problem_outlined,
                  color: AppTheme.cityRed, size: 20),
              const SizedBox(width: AppSpacing.s),
              Expanded(
                child: Text(
                  reviews.length == 1
                      ? '1 complaint needs attention'
                      : '${reviews.length} complaints need attention',
                  style: text.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700, color: AppTheme.cityRed),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.m),
          for (final r in shown)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.m),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          r.place,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: text.bodyMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ),
                      Text(_when(r.createdAt),
                          style: text.labelSmall
                              ?.copyWith(color: colors.onSurfaceVariant)),
                    ],
                  ),
                  if (r.comment.isNotEmpty)
                    Text(
                      r.comment,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: text.bodySmall
                          ?.copyWith(color: colors.onSurfaceVariant),
                    ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () => onHandled(r.id),
                      icon: const Icon(Icons.check, size: 16),
                      label: const Text('Mark as handled'),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        minimumSize: const Size(0, 32),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          if (reviews.length > shown.length)
            TextButton(
              onPressed: onOpen,
              child: Text('See all ${reviews.length} in Feedback'),
            ),
        ],
      ),
    );
  }
}

/// A single proportional bar showing how the city's feedback is running.
///
/// Three numbers on a dashboard would have to be read and compared; one bar is
/// understood at a glance, which is the point of an at-a-glance panel.
class _SentimentBar extends StatelessWidget {
  const _SentimentBar({
    required this.positive,
    required this.neutral,
    required this.negative,
    required this.onTap,
  });

  final int positive;
  final int neutral;
  final int negative;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final total = positive + neutral + negative;
    if (total == 0) return const SizedBox.shrink();

    final success = AppTheme.successFor(Theme.of(context).brightness);
    final share = (positive / total * 100).round();

    return InkWell(
      borderRadius: BorderRadius.circular(AppRadius.lg),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.l),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: colors.outlineVariant),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('Visitor sentiment',
                      style: text.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w700)),
                ),
                Text('$share% positive',
                    style: text.labelLarge?.copyWith(
                        fontWeight: FontWeight.w800, color: success)),
              ],
            ),
            const SizedBox(height: AppSpacing.m),
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.pill),
              child: SizedBox(
                height: 10,
                child: Row(
                  children: [
                    if (positive > 0)
                      Expanded(flex: positive, child: ColoredBox(color: success)),
                    if (neutral > 0)
                      Expanded(
                          flex: neutral,
                          child: ColoredBox(color: colors.outlineVariant)),
                    if (negative > 0)
                      Expanded(
                          flex: negative,
                          child: const ColoredBox(color: AppTheme.cityRed)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.s),
            Text(
              '$positive positive · $neutral neutral · $negative negative',
              style: text.bodySmall?.copyWith(color: colors.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

class _StaffStat extends StatelessWidget {
  const _StaffStat({
    required this.label,
    required this.value,
    required this.icon,
    this.highlight = false,
    this.onTap,
  });

  final String label;
  final String value;
  final IconData icon;
  final bool highlight;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final accent = highlight ? const Color(0xFFEF6C00) : colors.primary;

    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.md),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.l),
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(
              color: highlight
                  ? accent.withValues(alpha: 0.55)
                  : colors.outlineVariant,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: accent, size: 18),
              const SizedBox(height: AppSpacing.m),
              Text(value,
                  style: text.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      height: 1.0,
                      color: highlight ? accent : colors.onSurface)),
              const SizedBox(height: 4),
              Text(label.toUpperCase(),
                  style: text.labelSmall?.copyWith(
                    color: colors.outline,
                    letterSpacing: 0.5,
                    fontWeight: FontWeight.w600,
                  )),
            ],
          ),
        ),
      ),
    );
  }
}

class _WorkRow extends StatelessWidget {
  const _WorkRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.l, vertical: AppSpacing.m),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: colors.primary.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              child: Icon(icon, size: 19, color: colors.primary),
            ),
            const SizedBox(width: AppSpacing.m),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: text.bodyLarge
                          ?.copyWith(fontWeight: FontWeight.w600)),
                  Text(subtitle,
                      style: text.bodySmall
                          ?.copyWith(color: colors.onSurfaceVariant)),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: colors.outlineVariant),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Publish an announcement (staff version — same power as the admin form)
// ---------------------------------------------------------------------------
class StaffAnnouncementPage extends StatefulWidget {
  const StaffAnnouncementPage({super.key});

  @override
  State<StaffAnnouncementPage> createState() => _StaffAnnouncementPageState();
}

class _StaffAnnouncementPageState extends State<StaffAnnouncementPage> {
  final _formKey = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _body = TextEditingController();
  String _category = 'General';
  Audience _audience = Audience.everyone;
  bool _pinned = false;
  bool _sending = false;

  static const _categories = ['General', 'Advisory', 'Event', 'Emergency'];

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _publish() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _sending = true);
    try {
      await FirebaseFirestore.instance
          .collection(kAnnouncementCollection)
          .add({
        'title': _title.text.trim(),
        'body': _body.text.trim(),
        'category': _category,
        // Who this is for. Decided by the officer writing it, since only they
        // know whether a notice concerns residents, visitors, or the whole
        // city standing in it.
        'audience': _audience.id,
        'author': kAnnouncementPublisher,
        'pinned': _pinned,
        'publishedAt': FieldValue.serverTimestamp(),
        'postedBy': FirebaseAuth.instance.currentUser?.email ?? '',
      });
      if (!mounted) return;
      _title.clear();
      _body.clear();
      setState(() {
        _category = 'General';
        _audience = Audience.everyone;
        _pinned = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Published — every user has been notified')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not publish. Check connection.')),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('New announcement')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.l),
          children: [
            Text('Publish to all app users', style: text.titleMedium),
            const SizedBox(height: 4),
            Text(
              'Everyone receives a phone notification when this is posted.',
              style: text.bodySmall,
            ),
            const SizedBox(height: AppSpacing.l),
            TextFormField(
              controller: _title,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Headline',
                prefixIcon: Icon(Icons.title),
                border: OutlineInputBorder(),
              ),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Enter a headline' : null,
            ),
            const SizedBox(height: AppSpacing.m),
            TextFormField(
              controller: _body,
              maxLines: 5,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Details',
                alignLabelWithHint: true,
                border: OutlineInputBorder(),
              ),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Enter the details' : null,
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
                for (final c in _categories)
                  DropdownMenuItem(value: c, child: Text(c)),
              ],
              onChanged: (v) => setState(() => _category = v ?? _category),
            ),
            const SizedBox(height: AppSpacing.m),
            // Who receives it. Everyone by default, because most city notices
            // concern everyone — but a festival aimed at visitors should not
            // wake every resident, and a barangay advisory is not a tourist's
            // business.
            DropdownButtonFormField<Audience>(
              initialValue: _audience,
              decoration: const InputDecoration(
                labelText: 'Send to',
                prefixIcon: Icon(Icons.groups_outlined),
                border: OutlineInputBorder(),
              ),
              items: [
                for (final a in Audience.values)
                  DropdownMenuItem(
                    value: a,
                    child: Row(
                      children: [
                        Icon(a.icon, size: 18),
                        const SizedBox(width: AppSpacing.s),
                        Text(a.label),
                      ],
                    ),
                  ),
              ],
              onChanged: (v) => setState(() => _audience = v ?? _audience),
            ),
            const SizedBox(height: 4),
            Text(
              switch (_audience) {
                Audience.everyone =>
                  'Every signed-in person will be notified.',
                Audience.visitors =>
                  'Only visitors will see this. Mandaleños will not.',
                Audience.residents =>
                  'Only Mandaleños will see this. Visitors will not.',
              },
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            CheckboxListTile(
              value: _pinned,
              onChanged: (v) => setState(() => _pinned = v ?? false),
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: EdgeInsets.zero,
              title: const Text('Pin to the top'),
            ),
            const SizedBox(height: AppSpacing.m),
            FilledButton.icon(
              onPressed: _sending ? null : _publish,
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.m),
              ),
              icon: _sending
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.campaign_rounded),
              label: Text(_sending ? 'Publishing…' : 'Publish announcement'),
            ),
          ],
        ),
      ),
    );
  }
}
