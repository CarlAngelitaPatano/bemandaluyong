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

// ===========================================================================
// Staff operations report.
//
// Compiles the office's activity — events held, community requests, and
// visitor feedback with its sentiment analysis — into a printable PDF or a
// CSV for spreadsheets. Staff can then share it with the administrator
// straight from the app (email, Drive, chat).
// ===========================================================================

class ReportData {
  final List<CityEvent> events;
  final List<EventRequest> requests;
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
    required this.feedbackCount,
    required this.averageRating,
    required this.positive,
    required this.neutral,
    required this.negative,
    required this.byCategory,
    required this.comments,
  });

  static Future<ReportData> gather() async {
    final db = FirebaseFirestore.instance;
    final results = await Future.wait([
      db.collection(kEventsCollection).get(),
      db.collection(kEventRequestCollection).get(),
      db.collection('feedback').get(),
    ]);

    final events = results[0].docs.map(CityEvent.fromDoc).toList()
      ..sort((a, b) => (a.startsAt ?? DateTime(2000))
          .compareTo(b.startsAt ?? DateTime(2000)));
    final requests = results[1].docs.map(EventRequest.fromDoc).toList();

    int pos = 0, neu = 0, neg = 0, rated = 0;
    double ratingSum = 0;
    final byCategory = <String, int>{};
    final comments =
        <({String category, String subject, int rating, String sentiment, String message})>[];

    for (final d in results[2].docs) {
      final m = d.data();
      final s = (m['sentiment'] ?? 'neutral').toString();
      if (s == 'positive') {
        pos++;
      } else if (s == 'negative') {
        neg++;
      } else {
        neu++;
      }
      final r = (m['rating'] as num?)?.toInt() ?? 0;
      if (r > 0) {
        ratingSum += r;
        rated++;
      }
      final cat = (m['category'] ?? 'Other').toString();
      byCategory[cat] = (byCategory[cat] ?? 0) + 1;
      comments.add((
        category: cat,
        subject: (m['subject'] ?? '').toString(),
        rating: r,
        sentiment: s,
        message: (m['message'] ?? '').toString(),
      ));
    }

    return ReportData(
      events: events,
      requests: requests,
      feedbackCount: results[2].docs.length,
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

          // ---- Event reports ----
          if (data.events.any((e) => e.report.isNotEmpty)) ...[
            heading('5. Event reports'),
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
          heading('6. Community event requests'),
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
  bool _busy = false;
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
                            ?.copyWith(color: colors.outline),
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
                    Reveal(
                      delayMs: 120,
                      child: FilledButton.icon(
                        onPressed: _busy ? null : () => _share(pdf: true),
                        style: FilledButton.styleFrom(
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
                            : 'Generate PDF and send'),
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
