import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

import 'theme.dart';
import 'motion.dart';
import 'events_manager.dart';
import 'event_requests.dart';
import 'announcements.dart'; // Announcement + its collection name
import 'heritage.dart' show kChurches; // how many stops make a complete trail
import 'tcims_api.dart'; // reviews and trail activity from the shared database

// ===========================================================================
// Staff operations report.
//
// This is how the office reports upward. A staff member compiles what has
// happened in the app — events held and upcoming, community requests received,
// announcements published, visitor feedback with its sentiment, and
// participation in the Heritage Trail — into a printable PDF or a CSV for
// spreadsheets, then sends it to the administrator from the app.
//
// It draws on both stores: events, requests and announcements are the app's
// own Firestore records, while reviews and trail check-ins come from the
// shared database the website also reads, so the report cannot disagree with
// the dashboard the administrator is looking at.
// ===========================================================================

class ReportData {
  final List<CityEvent> events;
  final List<EventRequest> requests;

  /// Announcements staff published — the record of what was communicated.
  final List<Announcement> announcements;

  // --- Heritage Trail participation -----------------------------------------
  // Read from the shared database, so it counts everyone, not just this phone.

  /// False when the trail data could not be read. The report then says so
  /// rather than printing zeroes an administrator would read as "nobody is
  /// walking the trail".
  final bool trailAvailable;

  /// Stops that make a complete trail, as the SERVER counts them.
  final int trailTotal;

  /// People who have verified at least one stop.
  final int trailWalkers;

  /// People who have verified every stop.
  final int trailCompleted;

  /// Verified check-ins across all accounts.
  final int trailCheckins;

  /// Verified visits per church, most visited first.
  final Map<String, int> visitsByChurch;

  /// Per-visitor progress, for the detail table.
  final List<
      ({
        String who,
        int done,
        String status,
        String? rewardCode,
        String? rewardStatus
      })> trailVisitors;

  final int feedbackCount;
  final double averageRating;
  final int positive;
  final int neutral;
  final int negative;
  final Map<String, int> byCategory;
  final List<({String category, String subject, int rating, String sentiment, String message})>
      comments;

  const ReportData({
    required this.events,
    required this.requests,
    required this.announcements,
    required this.trailAvailable,
    required this.trailTotal,
    required this.trailWalkers,
    required this.trailCompleted,
    required this.trailCheckins,
    required this.visitsByChurch,
    required this.trailVisitors,
    required this.feedbackCount,
    required this.averageRating,
    required this.positive,
    required this.neutral,
    required this.negative,
    required this.byCategory,
    required this.comments,
  });

  /// Collects everything the report covers.
  ///
  /// Two sources, deliberately: events, requests and announcements are
  /// Firestore records the app itself owns, while reviews live in the office's
  /// shared database alongside the website's. This used to read feedback from
  /// Firestore, which meant the report an administrator received disagreed
  /// with the dashboard that administrator was looking at.
  static Future<ReportData> gather() async {
    final db = FirebaseFirestore.instance;
    final results = await Future.wait([
      db.collection(kEventRequestCollection).get(),
      db.collection(kAnnouncementCollection).get(),
    ]);

    // Events now come from the shared database — the same rows the
    // administrator approves — so the report reflects what the office has
    // actually cleared, not what was drafted in the app.
    final events = await EventsService.list();
    final requests = results[0].docs.map(EventRequest.fromDoc).toList();

    // What staff communicated to residents during the period. Parsed by the
    // announcements feature's own reader, so the report cannot drift from it.
    final announcements = results[1].docs.map(Announcement.fromDoc).toList()
      ..sort((a, b) => (b.publishedAt ?? DateTime(2000))
          .compareTo(a.publishedAt ?? DateTime(2000)));

    int pos = 0, neu = 0, neg = 0, rated = 0;
    double ratingSum = 0;
    final byCategory = <String, int>{};
    final comments =
        <({String category, String subject, int rating, String sentiment, String message})>[];

    // Reviews from the shared database — the same rows the website reports on.
    final raw = await TcimsApi.get('/api/crud.php?table=reviews');
    final rows = raw is List ? raw : const [];

    for (final row in rows) {
      if (row is! Map) continue;
      // The server's own classification, not the shadow ml_sentiment.
      final s = (row['sentiment'] ?? 'Neutral').toString().toLowerCase();
      if (s == 'positive') {
        pos++;
      } else if (s == 'negative') {
        neg++;
      } else {
        neu++;
      }
      // mysqli returns every column as a string.
      final r = int.tryParse('${row['rating'] ?? ''}') ?? 0;
      if (r > 0) {
        ratingSum += r;
        rated++;
      }
      final place = (row['place'] ?? '').toString();
      final cat = place.isEmpty ? 'General' : place;
      byCategory[cat] = (byCategory[cat] ?? 0) + 1;
      comments.add((
        category: cat,
        subject: place,
        rating: r,
        sentiment: s,
        message: (row['comment'] ?? '').toString(),
      ));
    }

    // ---- Heritage Trail participation -------------------------------------
    //
    // Read from the backend's own trail_progress endpoint rather than counted
    // from raw visit rows. That matters: the endpoint applies the SAME church
    // list and verified-only rule as the reward gate, so this report cannot
    // claim someone finished 9 of 9 while the server refuses them the mug.
    // Aggregating it here by hand is exactly how the 9-versus-12 mismatch and
    // the countable Explore taps went unnoticed.
    var trailAvailable = false;
    var trailTotal = kChurches.length;
    var trailWalkers = 0;
    var trailCompleted = 0;
    var trailCheckins = 0;
    final visitsByChurch = <String, int>{};
    final trailVisitors = <({
      String who,
      int done,
      String status,
      String? rewardCode,
      String? rewardStatus
    })>[];

    final trail = await TcimsApi.get('/api/trail_progress.php');
    if (trail is Map<String, dynamic>) {
      trailAvailable = true;
      trailTotal = (trail['total'] as num?)?.toInt() ?? kChurches.length;

      final summary = trail['summary'];
      if (summary is Map) {
        trailWalkers = (summary['walkers'] as num?)?.toInt() ?? 0;
        trailCompleted = (summary['completed'] as num?)?.toInt() ?? 0;
        trailCheckins = (summary['verified_checkins'] as num?)?.toInt() ?? 0;
      }

      final tourists = trail['tourists'];
      if (tourists is List) {
        for (final t in tourists) {
          if (t is! Map) continue;
          // Username is often null; the email is what identifies someone at a
          // counter, so it is the fallback rather than a bare user id.
          final who = (t['username'] ?? '').toString().trim().isNotEmpty
              ? t['username'].toString()
              : (t['email'] ?? 'user ${t['user_id']}').toString();

          trailVisitors.add((
            who: who,
            done: (t['done'] as num?)?.toInt() ?? 0,
            status: (t['status'] ?? '').toString(),
            rewardCode: t['reward_code']?.toString(),
            rewardStatus: t['reward_status']?.toString(),
          ));

          final places = t['places'];
          if (places is List) {
            for (final p in places) {
              final name = p.toString();
              visitsByChurch[name] = (visitsByChurch[name] ?? 0) + 1;
            }
          }
        }
        trailVisitors.sort((a, b) => b.done.compareTo(a.done));
      }
    }

    return ReportData(
      events: events,
      requests: requests,
      announcements: announcements,
      trailAvailable: trailAvailable,
      trailTotal: trailTotal,
      trailWalkers: trailWalkers,
      trailCompleted: trailCompleted,
      trailCheckins: trailCheckins,
      visitsByChurch: visitsByChurch,
      trailVisitors: trailVisitors,
      feedbackCount: rows.length,
      averageRating: rated == 0 ? 0 : ratingSum / rated,
      positive: pos,
      neutral: neu,
      negative: neg,
      byCategory: byCategory,
      comments: comments,
    );
  }
}

class ReportBuilder {
  ReportBuilder._();

  /// The report condensed into plain text for the administrator's inbox.
  ///
  /// `inquiries.php` accepts between 10 and 2000 characters, so this is a
  /// summary rather than the whole document — the figures an administrator
  /// needs to see at a glance, plus the complaints worth reading in full. The
  /// PDF remains the complete record and can still be shared alongside it.
  static String summaryText(ReportData d) {
    final b = StringBuffer();
    final now = DateTime.now();

    b.writeln('BE@MANDALUYONG — STAFF OPERATIONS REPORT');
    b.writeln('Compiled ${now.day}/${now.month}/${now.year}');
    b.writeln('');

    b.writeln('ACTIVITY');
    b.writeln('- Events on record: ${d.events.length}');
    b.writeln('- Announcements published: ${d.announcements.length}');
    b.writeln('- Community event requests: ${d.requests.length}');
    b.writeln('');

    b.writeln('VISITOR FEEDBACK');
    b.writeln('- Reviews received: ${d.feedbackCount}');
    if (d.feedbackCount > 0) {
      b.writeln('- Average rating: ${d.averageRating.toStringAsFixed(2)} / 5');
      b.writeln('- Positive ${d.positive} | Neutral ${d.neutral} '
          '| Negative ${d.negative}');
    }
    b.writeln('');

    b.writeln('HERITAGE TRAIL');
    if (!d.trailAvailable) {
      b.writeln('- Trail data unavailable when this report was compiled.');
    } else {
      b.writeln('- Started the trail: ${d.trailWalkers}');
      b.writeln('- Completed all ${d.trailTotal} stops: ${d.trailCompleted}');
      b.writeln('- Verified check-ins: ${d.trailCheckins}');
      final claimed = d.trailVisitors.where((v) => v.rewardCode != null);
      if (claimed.isNotEmpty) {
        b.writeln('- Mug rewards issued: ${claimed.length}');
      }
    }

    // Negative comments are the part an administrator most needs in words
    // rather than as a number, so they go last and get the remaining room.
    final negatives =
        d.comments.where((c) => c.sentiment.toLowerCase() == 'negative');
    if (negatives.isNotEmpty) {
      b.writeln('');
      b.writeln('COMPLAINTS RAISED');
      for (final c in negatives.take(5)) {
        final msg = c.message.length > 140
            ? '${c.message.substring(0, 140)}…'
            : c.message;
        b.writeln('- ${c.subject.isEmpty ? c.category : c.subject}: $msg');
      }
    }

    final out = b.toString().trim();
    // Hard cap with an honest marker, so nothing is silently lost.
    const limit = 1980;
    return out.length <= limit
        ? out
        : '${out.substring(0, limit)}\n[truncated — see attached PDF]';
  }

  static String _today() {
    const months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December'
    ];
    final d = DateTime.now();
    return '${d.day} ${months[d.month - 1]} ${d.year}';
  }

  // ---------------------------------------------------------------- PDF ----
  static Future<File> buildPdf(ReportData data) async {
    final doc = pw.Document();
    const navy = PdfColor.fromInt(0xFF12305F);
    const gold = PdfColor.fromInt(0xFFD9A520);
    final staff = FirebaseAuth.instance.currentUser?.email ?? 'CCAT staff';

    pw.Widget heading(String s) => pw.Padding(
          padding: const pw.EdgeInsets.only(top: 18, bottom: 6),
          child: pw.Text(s,
              style: pw.TextStyle(
                  fontSize: 13,
                  fontWeight: pw.FontWeight.bold,
                  color: navy)),
        );

    pw.Widget kv(String k, String v) => pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 3),
          child: pw.Row(children: [
            pw.SizedBox(
                width: 170,
                child: pw.Text(k, style: const pw.TextStyle(fontSize: 10))),
            pw.Text(v,
                style: pw.TextStyle(
                    fontSize: 10, fontWeight: pw.FontWeight.bold)),
          ]),
        );

    final upcoming =
        data.events.where((e) => e.status == EventStatus.upcoming).length;
    final completed =
        data.events.where((e) => e.status == EventStatus.completed).length;
    final pending =
        data.requests.where((r) => r.status == RequestStatus.pending).length;

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(36),
        footer: (ctx) => pw.Container(
          alignment: pw.Alignment.centerRight,
          margin: const pw.EdgeInsets.only(top: 10),
          child: pw.Text(
            'Be@Mandaluyong · CCAT Operations Report · '
            'Page ${ctx.pageNumber} of ${ctx.pagesCount}',
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
          ),
        ),
        build: (ctx) => [
          // ---- Title block ----
          pw.Text('City Cultural Affairs and Tourism',
              style: pw.TextStyle(
                  fontSize: 11,
                  color: PdfColors.grey700,
                  letterSpacing: 0.6)),
          pw.Text('Operations Report',
              style: pw.TextStyle(
                  fontSize: 22, fontWeight: pw.FontWeight.bold, color: navy)),
          pw.Container(width: 60, height: 3, color: gold),
          pw.SizedBox(height: 10),
          kv('Report date', _today()),
          kv('Prepared by', staff),
          kv('City', 'Mandaluyong City, Philippines'),

          // ---- Summary ----
          heading('1. Summary'),
          kv('Events on record', '${data.events.length}'),
          kv('Announcements published', '${data.announcements.length}'),
          kv('Upcoming events', '$upcoming'),
          kv('Completed events', '$completed'),
          kv('Community event requests', '${data.requests.length}'),
          kv('Requests awaiting review', '$pending'),
          kv('Feedback received', '${data.feedbackCount}'),
          kv('Average visitor rating',
              '${data.averageRating.toStringAsFixed(2)} out of 5'),

          // ---- Sentiment ----
          heading('2. Visitor sentiment analysis'),
          pw.Text(
            'Comments were classified automatically using the application\'s '
            'natural language processing module.',
            style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
          ),
          pw.SizedBox(height: 6),
          pw.TableHelper.fromTextArray(
            headers: ['Classification', 'Count', 'Share'],
            headerStyle: pw.TextStyle(
                fontSize: 9, fontWeight: pw.FontWeight.bold,
                color: PdfColors.white),
            headerDecoration: const pw.BoxDecoration(color: navy),
            cellStyle: const pw.TextStyle(fontSize: 9),
            cellAlignment: pw.Alignment.centerLeft,
            data: [
              for (final row in [
                ('Positive', data.positive),
                ('Neutral', data.neutral),
                ('Negative', data.negative),
              ])
                [
                  row.$1,
                  '${row.$2}',
                  data.feedbackCount == 0
                      ? '0%'
                      : '${(row.$2 / data.feedbackCount * 100).toStringAsFixed(0)}%',
                ],
            ],
          ),

          if (data.byCategory.isNotEmpty) ...[
            heading('3. Feedback by category'),
            pw.TableHelper.fromTextArray(
              headers: ['Category', 'Comments'],
              headerStyle: pw.TextStyle(
                  fontSize: 9, fontWeight: pw.FontWeight.bold,
                  color: PdfColors.white),
              headerDecoration: const pw.BoxDecoration(color: navy),
              cellStyle: const pw.TextStyle(fontSize: 9),
              data: [
                for (final e in data.byCategory.entries) [e.key, '${e.value}'],
              ],
            ),
          ],

          // ---- Events ----
          heading('4. Events'),
          if (data.events.isEmpty)
            pw.Text('No events on record.',
                style: const pw.TextStyle(fontSize: 9))
          else
            pw.TableHelper.fromTextArray(
              headers: ['Event', 'Date', 'Status', 'Attendance'],
              headerStyle: pw.TextStyle(
                  fontSize: 9, fontWeight: pw.FontWeight.bold,
                  color: PdfColors.white),
              headerDecoration: const pw.BoxDecoration(color: navy),
              cellStyle: const pw.TextStyle(fontSize: 9),
              columnWidths: {
                0: const pw.FlexColumnWidth(3),
                1: const pw.FlexColumnWidth(2.4),
                2: const pw.FlexColumnWidth(1.6),
                3: const pw.FlexColumnWidth(1.4),
              },
              data: [
                for (final e in data.events)
                  [
                    e.title,
                    e.dateLabel,
                    e.status.label,
                    e.attendance > 0 ? '${e.attendance}' : '—',
                  ],
              ],
            ),

          // ---- Heritage Trail ----
          heading('5. Heritage Trail participation'),
          if (!data.trailAvailable)
            pw.Text(
              'Trail data could not be read from the office database for this '
              'report.',
              style: const pw.TextStyle(fontSize: 9),
            )
          else ...[
            kv('Visitors who have started the trail', '${data.trailWalkers}'),
            kv('Visitors who have completed all ${data.trailTotal} stops',
                '${data.trailCompleted}'),
            kv('In progress',
                '${data.trailWalkers - data.trailCompleted}'),
            kv('Verified check-ins', '${data.trailCheckins}'),
            pw.SizedBox(height: 8),
            if (data.trailVisitors.isNotEmpty) ...[
              pw.TableHelper.fromTextArray(
                headers: ['Visitor', 'Stops', 'Status', 'Mug code'],
                headerStyle: pw.TextStyle(
                    fontSize: 9,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.white),
                headerDecoration: const pw.BoxDecoration(color: navy),
                cellStyle: const pw.TextStyle(fontSize: 9),
                columnWidths: {
                  0: const pw.FlexColumnWidth(3.2),
                  1: const pw.FlexColumnWidth(1.1),
                  2: const pw.FlexColumnWidth(1.6),
                  3: const pw.FlexColumnWidth(1.8),
                },
                data: [
                  for (final v in data.trailVisitors)
                    [
                      v.who,
                      '${v.done}/${data.trailTotal}',
                      v.status,
                      v.rewardCode == null
                          ? '—'
                          : '${v.rewardCode} (${v.rewardStatus ?? '—'})',
                    ],
                ],
              ),
              pw.SizedBox(height: 8),
            ],
            if (data.visitsByChurch.isNotEmpty)
              pw.TableHelper.fromTextArray(
                headers: ['Church', 'Verified visits'],
                headerStyle: pw.TextStyle(
                    fontSize: 9,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.white),
                headerDecoration: const pw.BoxDecoration(color: navy),
                cellStyle: const pw.TextStyle(fontSize: 9),
                columnWidths: {
                  0: const pw.FlexColumnWidth(4),
                  1: const pw.FlexColumnWidth(1.4),
                },
                data: [
                  for (final e in (data.visitsByChurch.entries.toList()
                        ..sort((a, b) => b.value.compareTo(a.value))))
                    [e.key, '${e.value}'],
                ],
              ),
          ],

          // ---- Announcements ----
          // The record of what the office told residents, and when.
          heading('6. Announcements published'),
          if (data.announcements.isEmpty)
            pw.Text('No announcements published.',
                style: const pw.TextStyle(fontSize: 9))
          else
            pw.TableHelper.fromTextArray(
              headers: ['Announcement', 'Category', 'Published'],
              headerStyle: pw.TextStyle(
                  fontSize: 9,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.white),
              headerDecoration: const pw.BoxDecoration(color: navy),
              cellStyle: const pw.TextStyle(fontSize: 9),
              columnWidths: {
                0: const pw.FlexColumnWidth(3.4),
                1: const pw.FlexColumnWidth(1.6),
                2: const pw.FlexColumnWidth(2.0),
              },
              data: [
                for (final a in data.announcements)
                  [
                    a.title,
                    a.category,
                    a.publishedAt == null
                        ? '—'
                        : '${a.publishedAt!.day}/${a.publishedAt!.month}/'
                            '${a.publishedAt!.year}',
                  ],
              ],
            ),

          // ---- Event reports ----
          if (data.events.any((e) => e.report.isNotEmpty)) ...[
            heading('7. Event reports'),
            for (final e in data.events.where((e) => e.report.isNotEmpty))
              pw.Container(
                margin: const pw.EdgeInsets.only(bottom: 8),
                padding: const pw.EdgeInsets.all(8),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: PdfColors.grey400, width: 0.5),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(e.title,
                        style: pw.TextStyle(
                            fontSize: 10, fontWeight: pw.FontWeight.bold)),
                    pw.Text('${e.dateLabel} · ${e.venue}',
                        style: const pw.TextStyle(
                            fontSize: 8, color: PdfColors.grey700)),
                    pw.SizedBox(height: 4),
                    pw.Text(e.report, style: const pw.TextStyle(fontSize: 9)),
                    if (e.attendance > 0)
                      pw.Text('Estimated attendance: ${e.attendance}',
                          style: const pw.TextStyle(
                              fontSize: 8, color: PdfColors.grey700)),
                  ],
                ),
              ),
          ],

          // ---- Requests ----
          heading('8. Community event requests'),
          if (data.requests.isEmpty)
            pw.Text('No requests submitted.',
                style: const pw.TextStyle(fontSize: 9))
          else
            pw.TableHelper.fromTextArray(
              headers: ['Proposed activity', 'Requested by', 'Date', 'Status'],
              headerStyle: pw.TextStyle(
                  fontSize: 9, fontWeight: pw.FontWeight.bold,
                  color: PdfColors.white),
              headerDecoration: const pw.BoxDecoration(color: navy),
              cellStyle: const pw.TextStyle(fontSize: 9),
              data: [
                for (final r in data.requests)
                  [r.title, r.requestedByName, r.dateLabel, r.status.label],
              ],
            ),

          pw.SizedBox(height: 24),
          pw.Divider(color: PdfColors.grey400),
          pw.Text(
            'Generated by the Be@Mandaluyong mobile application. '
            'Prepared for the Office of the City Cultural Affairs and Tourism.',
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
          ),
        ],
      ),
    );

    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/CCAT_Operations_Report.pdf');
    await file.writeAsBytes(await doc.save());
    return file;
  }

  // ---------------------------------------------------------------- CSV ----
  static String _esc(String s) => '"${s.replaceAll('"', '""')}"';

  static Future<File> buildCsv(ReportData data) async {
    final b = StringBuffer();

    b.writeln('CCAT OPERATIONS REPORT');
    b.writeln('Report date,${_esc(_today())}');
    b.writeln(
        'Prepared by,${_esc(FirebaseAuth.instance.currentUser?.email ?? '')}');
    b.writeln();

    b.writeln('SUMMARY');
    b.writeln('Metric,Value');
    b.writeln('Events on record,${data.events.length}');
    b.writeln('Community requests,${data.requests.length}');
    b.writeln('Announcements published,${data.announcements.length}');
    if (data.trailAvailable) {
      b.writeln('Trail participants,${data.trailWalkers}');
      b.writeln('Trail completions,${data.trailCompleted}');
    } else {
      b.writeln('Trail participants,unavailable');
      b.writeln('Trail completions,unavailable');
    }
    b.writeln('Feedback received,${data.feedbackCount}');
    b.writeln('Average rating,${data.averageRating.toStringAsFixed(2)}');
    b.writeln('Positive,${data.positive}');
    b.writeln('Neutral,${data.neutral}');
    b.writeln('Negative,${data.negative}');
    b.writeln();

    b.writeln('EVENTS');
    b.writeln('Title,Date,Venue,Category,Status,Attendance,Report');
    for (final e in data.events) {
      b.writeln([
        _esc(e.title),
        _esc(e.dateLabel),
        _esc(e.venue),
        _esc(e.category),
        _esc(e.status.label),
        '${e.attendance}',
        _esc(e.report),
      ].join(','));
    }
    b.writeln();

    b.writeln('EVENT REQUESTS');
    b.writeln('Title,Requested by,Proposed date,Venue,Status,Staff note');
    for (final r in data.requests) {
      b.writeln([
        _esc(r.title),
        _esc(r.requestedByName),
        _esc(r.dateLabel),
        _esc(r.venue),
        _esc(r.status.label),
        _esc(r.staffNote),
      ].join(','));
    }
    b.writeln();

    b.writeln('FEEDBACK');
    b.writeln('Category,Place,Rating,Sentiment,Comment');
    for (final c in data.comments) {
      b.writeln([
        _esc(c.category),
        _esc(c.subject),
        '${c.rating}',
        _esc(c.sentiment),
        _esc(c.message),
      ].join(','));
    }

    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/CCAT_Operations_Report.csv');
    await file.writeAsString(b.toString());
    return file;
  }
}

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------
class StaffReportPage extends StatefulWidget {
  const StaffReportPage({super.key});

  @override
  State<StaffReportPage> createState() => _StaffReportPageState();
}

class _StaffReportPageState extends State<StaffReportPage> {
  ReportData? _data;

  /// Building a PDF or CSV.
  bool _busy = false;

  /// Filing the report upward. Kept apart from [_busy] so the two buttons do
  /// not describe each other's work — the PDF button said "Preparing…" while
  /// the submit dialog was open, which was simply untrue.
  bool _sending = false;

  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final d = await ReportData.gather();
      if (mounted) setState(() => _data = d);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not load the data for this report.');
      }
    }
  }

  Future<void> _share({required bool pdf}) async {
    final data = _data;
    if (data == null) return;
    setState(() => _busy = true);
    try {
      final file = pdf
          ? await ReportBuilder.buildPdf(data)
          : await ReportBuilder.buildCsv(data);
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path)],
          subject: 'CCAT Operations Report',
          text: 'CCAT Operations Report generated from the Be@Mandaluyong '
              'mobile application.',
        ),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not create the report.')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Sends the report to the administrator, who reads it on the website.
  ///
  /// This is the whole point of the screen: an officer compiles what happened
  /// and files it upward. The share sheet remains for sending the full PDF
  /// alongside, but the summary lands in the administrator's inbox directly.
  Future<void> _sendToAdmin() async {
    final data = _data;
    if (data == null) return;

    final user = FirebaseAuth.instance.currentUser;
    final summary = ReportBuilder.summaryText(data);
    final now = DateTime.now();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Send to the administrator?'),
        content: Text(
          'This files a summary of the report to the City Cultural Affairs '
          'and Tourism administrator, who reads it on the CCAT website.\n\n'
          'The full PDF can still be shared separately.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Send'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _sending = true);
    try {
      // The "Staff Report" category is only honoured for a request carrying a
      // staff token — without one the backend quietly files it as a general
      // inquiry, which is the right call on its part (the endpoint is public,
      // so a name and email in the body are claims, not proof) but would leave
      // the officer thinking they had filed a report that the office will
      // never see in the right place. So it is checked here first.
      if (await TcimsApi.token == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            duration: Duration(seconds: 6),
            content: Text(
              'Not signed in to the office system, so this could not be filed '
              'as a staff report. Sign out and back in, then try again.',
            ),
          ),
        );
        return;
      }

      // No honeypot field is sent — including it would have the endpoint file
      // this silently as a bot submission while still answering "success".
      final res = await TcimsApi.postWithStatus('/api/inquiries.php', {
        'name': user?.displayName?.trim().isNotEmpty == true
            ? user!.displayName!.trim()
            : 'CCAT Staff',
        'email': user?.email ?? '',
        'subject': 'Staff Operations Report — '
            '${now.day}/${now.month}/${now.year}',
        // Gives the report its own chip on the administrator's page, instead
        // of sitting among tourists' questions.
        'category': 'Staff Report',
        'message': summary,
      });
      if (!mounted) return;

      if (res.status == 200 || res.status == 201) {
        // The endpoint returns its receipt as `ref_no`, e.g. INQ-2026-60002.
        final ref = (res.body is Map)
            ? (res.body['ref_no'] ?? '').toString().trim()
            : '';
        await showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            icon: const Icon(Icons.mark_email_read_outlined,
                color: AppTheme.brandGold, size: 40),
            title: const Text('Report filed'),
            content: Text(
              ref.isEmpty
                  ? 'The administrator has received your report.'
                  : 'The administrator has received your report.\n\n'
                      'Reference: $ref',
            ),
            actions: [
              FilledButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Done'),
              ),
            ],
          ),
        );
      } else {
        // Told apart on purpose: a rate limit is not a broken report, and an
        // officer who is simply too quick should be told to wait, not to
        // rewrite anything.
        final message = switch (res.status) {
          429 => 'Too many reports sent from this connection in the last '
              'hour. Please try again later.',
          400 || 422 =>
            'The administrator\'s inbox rejected this report. It may be too '
                'short or too long to file.',
          0 => 'Could not reach the office. Check your connection and try '
              'again.',
          _ => 'The report could not be filed (error ${res.status}).',
        };
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message), duration: const Duration(seconds: 5)),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final d = _data;

    return Scaffold(
      appBar: AppBar(title: const Text('Operations Report')),
      body: _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.xl),
                child: Text(_error!, textAlign: TextAlign.center),
              ),
            )
          : d == null
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                  padding: const EdgeInsets.all(AppSpacing.l),
                  children: [
                    Reveal(
                      delayMs: 0,
                      child: Text('Report preview', style: text.titleLarge),
                    ),
                    const SizedBox(height: 4),
                    Reveal(
                      delayMs: 40,
                      child: Text(
                        'Generate a printable report of the office\'s events, '
                        'community requests and visitor feedback, then send it '
                        'to the administrator.',
                        style: text.bodyMedium
                            ?.copyWith(color: colors.onSurfaceVariant),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    Reveal(
                      delayMs: 80,
                      child: Card(
                        child: Column(
                          children: [
                            _row('Events on record', '${d.events.length}'),
                            const Divider(height: 1),
                            _row('Community requests', '${d.requests.length}'),
                            _row('Announcements published',
                                '${d.announcements.length}'),
                            _row(
                                'Trail participants',
                                d.trailAvailable
                                    ? '${d.trailWalkers}'
                                    : 'unavailable'),
                            _row(
                                'Trail completions',
                                d.trailAvailable
                                    ? '${d.trailCompleted}'
                                    : 'unavailable'),
                            const Divider(height: 1),
                            _row('Feedback received', '${d.feedbackCount}'),
                            const Divider(height: 1),
                            _row('Average rating',
                                '${d.averageRating.toStringAsFixed(2)} / 5'),
                            const Divider(height: 1),
                            _row('Positive / Neutral / Negative',
                                '${d.positive} / ${d.neutral} / ${d.negative}'),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    // Filing it upward is the primary action, so it leads.
                    Reveal(
                      delayMs: 100,
                      child: FilledButton.icon(
                        onPressed: (_busy || _sending) ? null : _sendToAdmin,
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                              vertical: AppSpacing.m),
                          backgroundColor: AppTheme.brandGold,
                          foregroundColor: const Color(0xFF12305F),
                        ),
                        icon: _sending
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Color(0xFF12305F)))
                            : const Icon(Icons.send_rounded),
                        label: Text(
                            _sending ? 'Filing…' : 'Submit to administrator'),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.m),
                    Reveal(
                      delayMs: 120,
                      child: OutlinedButton.icon(
                        onPressed: _busy ? null : () => _share(pdf: true),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                              vertical: AppSpacing.m),
                        ),
                        icon: _busy
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.picture_as_pdf_outlined),
                        label: Text(_busy
                            ? 'Preparing…'
                            : 'Generate PDF and share'),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.m),
                    Reveal(
                      delayMs: 150,
                      child: OutlinedButton.icon(
                        onPressed: _busy ? null : () => _share(pdf: false),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                              vertical: AppSpacing.m),
                        ),
                        icon: const Icon(Icons.table_chart_outlined),
                        label: const Text('Generate CSV (spreadsheet)'),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.l),
                    Card(
                      color: colors.surfaceContainerHighest,
                      child: Padding(
                        padding: const EdgeInsets.all(AppSpacing.l),
                        child: Row(
                          children: [
                            Icon(Icons.info_outline, color: colors.outline),
                            const SizedBox(width: AppSpacing.m),
                            Expanded(
                              child: Text(
                                'The share sheet lets you email the file to '
                                'the administrator, save it to Drive, or send '
                                'it to a printer.',
                                style: text.bodySmall,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }

  Widget _row(String k, String v) => ListTile(
        dense: true,
        title: Text(k),
        trailing: Text(v,
            style: const TextStyle(fontWeight: FontWeight.w700)),
      );
}
