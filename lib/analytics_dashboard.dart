import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'theme.dart';
import 'motion.dart';
import 'sentiment.dart';
import 'feedback_page.dart'; // FeedbackSchema
import 'sentiment_eval.dart'; // model accuracy report

// ===========================================================================
// Sentiment Analytics Dashboard
//
// Reads the visitor feedback stored in the shared Firestore database and
// displays the sentiment analysis results alongside tourism statistics:
//   • overall positive / neutral / negative breakdown
//   • average visitor rating
//   • sentiment per feedback category
//   • the most recent comments with their classification
//
// This is the CCAT-facing view of Objective 2.
// ===========================================================================

class AnalyticsDashboardPage extends StatefulWidget {
  const AnalyticsDashboardPage({super.key, this.embedded = false});

  /// When true the page renders without its own Scaffold/AppBar, so it can be
  /// used directly as a bottom-navigation tab.
  final bool embedded;

  @override
  State<AnalyticsDashboardPage> createState() => _AnalyticsDashboardPageState();
}

class _AnalyticsDashboardPageState extends State<AnalyticsDashboardPage> {
  late Future<List<_Entry>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<_Entry>> _load() async {
    final snap = await FirebaseFirestore.instance
        .collection(FeedbackSchema.collection)
        .orderBy(FeedbackSchema.fCreatedAt, descending: true)
        .limit(300)
        .get();

    return snap.docs.map((d) {
      final m = d.data();
      final text = (m[FeedbackSchema.fMessage] ?? '').toString();
      // Use the stored label if present; otherwise classify on the fly, so
      // feedback submitted by the website is also analysed here.
      final stored = m[FeedbackSchema.fSentiment]?.toString();
      final sentiment = (stored == null || stored.isEmpty)
          ? SentimentAnalyzer.analyze(text).sentiment
          : sentimentFromId(stored);
      final ts = m[FeedbackSchema.fCreatedAt];
      return _Entry(
        message: text,
        rating: (m[FeedbackSchema.fRating] as num?)?.toInt() ?? 0,
        category: (m[FeedbackSchema.fCategory] ?? 'Other').toString(),
        subject: (m[FeedbackSchema.fSubject] ?? '').toString(),
        name: (m[FeedbackSchema.fName] ?? 'Anonymous').toString(),
        source: (m[FeedbackSchema.fSource] ?? '').toString(),
        sentiment: sentiment,
        createdAt: ts is Timestamp ? ts.toDate() : null,
      );
    }).toList();
  }

  Future<void> _refresh() async {
    setState(() => _future = _load());
    await _future.catchError((_) => <_Entry>[]);
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    final body = RefreshIndicator(
      onRefresh: _refresh,
      child: _buildList(context, colors, text),
    );

    if (widget.embedded) return body;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Feedback Analytics'),
        actions: [
          IconButton(
            tooltip: 'Model accuracy',
            icon: const Icon(Icons.science_outlined),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SentimentEvalPage()),
            ),
          ),
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: _refresh,
          ),
        ],
      ),
      body: body,
    );
  }

  Widget _buildList(
      BuildContext context, ColorScheme colors, TextTheme text) {
    return FutureBuilder<List<_Entry>>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snap.hasError) {
              return ListView(
                padding: const EdgeInsets.all(AppSpacing.xl),
                children: [
                  Icon(Icons.cloud_off, size: 48, color: colors.outline),
                  const SizedBox(height: AppSpacing.l),
                  Text(
                    'Could not load the feedback data. Check your internet '
                    'connection and pull down to try again.',
                    textAlign: TextAlign.center,
                    style: text.bodyMedium,
                  ),
                ],
              );
            }

            final all = snap.data ?? [];
            if (all.isEmpty) {
              return ListView(
                padding: const EdgeInsets.all(AppSpacing.xl),
                children: [
                  const SizedBox(height: AppSpacing.xxl),
                  Icon(Icons.insights_outlined, size: 56, color: colors.outline),
                  const SizedBox(height: AppSpacing.l),
                  Text('No feedback yet',
                      textAlign: TextAlign.center, style: text.titleMedium),
                  const SizedBox(height: AppSpacing.s),
                  Text(
                    'Once visitors start sending feedback, their sentiment '
                    'analysis appears here.',
                    textAlign: TextAlign.center,
                    style: text.bodySmall?.copyWith(color: colors.onSurfaceVariant),
                  ),
                ],
              );
            }

            final pos =
                all.where((e) => e.sentiment == Sentiment.positive).length;
            final neu =
                all.where((e) => e.sentiment == Sentiment.neutral).length;
            final neg =
                all.where((e) => e.sentiment == Sentiment.negative).length;
            final rated = all.where((e) => e.rating > 0).toList();
            final avg = rated.isEmpty
                ? 0.0
                : rated.map((e) => e.rating).reduce((a, b) => a + b) /
                    rated.length;

            // Per-category tallies
            final categories = <String, List<_Entry>>{};
            for (final e in all) {
              categories.putIfAbsent(e.category, () => []).add(e);
            }

            return ListView(
              padding: const EdgeInsets.all(AppSpacing.l),
              children: [
                // ---- Summary tiles ----
                Reveal(
                  delayMs: 0,
                  child: Row(
                    children: [
                      _StatTile(
                        label: 'Total feedback',
                        value: '${all.length}',
                        icon: Icons.forum_outlined,
                      ),
                      const SizedBox(width: AppSpacing.m),
                      _StatTile(
                        label: 'Average rating',
                        value: avg.toStringAsFixed(1),
                        icon: Icons.star_rounded,
                        valueColor: AppTheme.brandGold,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),

                // ---- Sentiment breakdown ----
                Reveal(
                  delayMs: 80,
                  child: Text('Sentiment analysis', style: text.titleMedium),
                ),
                const SizedBox(height: AppSpacing.s),
                Reveal(
                  delayMs: 100,
                  child: Text(
                    'Visitor comments classified automatically using natural '
                    'language processing.',
                    style: text.bodySmall?.copyWith(color: colors.onSurfaceVariant),
                  ),
                ),
                const SizedBox(height: AppSpacing.m),
                Reveal(
                  delayMs: 140,
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.l),
                      child: Column(
                        children: [
                          _SentimentBar(
                            label: 'Positive',
                            count: pos,
                            total: all.length,
                            color: _kPositive,
                          ),
                          const SizedBox(height: AppSpacing.m),
                          _SentimentBar(
                            label: 'Neutral',
                            count: neu,
                            total: all.length,
                            color: _kNeutral,
                          ),
                          const SizedBox(height: AppSpacing.m),
                          _SentimentBar(
                            label: 'Negative',
                            count: neg,
                            total: all.length,
                            color: _kNegative,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),

                // ---- Per-category ----
                Reveal(
                  delayMs: 200,
                  child: Text('By category', style: text.titleMedium),
                ),
                const SizedBox(height: AppSpacing.m),
                for (final entry in categories.entries)
                  Reveal(
                    delayMs: 240,
                    child: Card(
                      margin: const EdgeInsets.only(bottom: AppSpacing.s),
                      child: Padding(
                        padding: const EdgeInsets.all(AppSpacing.m),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(entry.key,
                                  style: text.bodyMedium?.copyWith(
                                      fontWeight: FontWeight.w600)),
                            ),
                            _MiniCount(
                              value: entry.value
                                  .where((e) => e.sentiment == Sentiment.positive)
                                  .length,
                              color: _kPositive,
                            ),
                            _MiniCount(
                              value: entry.value
                                  .where((e) => e.sentiment == Sentiment.neutral)
                                  .length,
                              color: _kNeutral,
                            ),
                            _MiniCount(
                              value: entry.value
                                  .where((e) => e.sentiment == Sentiment.negative)
                                  .length,
                              color: _kNegative,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                const SizedBox(height: AppSpacing.xl),

                // ---- Recent comments ----
                Reveal(
                  delayMs: 300,
                  child: Text('Recent feedback', style: text.titleMedium),
                ),
                const SizedBox(height: AppSpacing.m),
                for (final e in all.take(15))
                  Card(
                    margin: const EdgeInsets.only(bottom: AppSpacing.m),
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.l),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              _SentimentChip(sentiment: e.sentiment),
                              const SizedBox(width: AppSpacing.s),
                              if (e.rating > 0)
                                Row(
                                  children: [
                                    const Icon(Icons.star_rounded,
                                        size: 15, color: AppTheme.brandGold),
                                    Text(' ${e.rating}',
                                        style: text.labelMedium),
                                  ],
                                ),
                              const Spacer(),
                              if (e.source.isNotEmpty)
                                Text(e.source,
                                    style: text.labelSmall
                                        ?.copyWith(color: colors.onSurfaceVariant)),
                            ],
                          ),
                          const SizedBox(height: AppSpacing.s),
                          Text(e.message, style: text.bodyMedium),
                          const SizedBox(height: 4),
                          Text(
                            [e.name, e.category]
                                .where((s) => s.isNotEmpty)
                                .join(' · '),
                            style: text.labelSmall
                                ?.copyWith(color: colors.onSurfaceVariant),
                          ),
                          // The exact place named by the visitor, if any.
                          if (e.subject.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Icon(Icons.place_outlined,
                                    size: 13, color: colors.primary),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    e.subject,
                                    style: text.labelSmall?.copyWith(
                                      color: colors.primary,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
              ],
            );
          },
        );
  }
}

// Sentiment colours — kept distinct because they carry meaning (data viz).
const Color _kPositive = Color(0xFF2E7D32);
const Color _kNeutral = Color(0xFF9E9E9E);
const Color _kNegative = Color(0xFFC62828);

class _Entry {
  final String message;
  final int rating;
  final String category;
  final String subject; // specific church / attraction / establishment
  final String name;
  final String source;
  final Sentiment sentiment;
  final DateTime? createdAt;

  const _Entry({
    required this.message,
    required this.rating,
    required this.category,
    required this.subject,
    required this.name,
    required this.source,
    required this.sentiment,
    this.createdAt,
  });
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.label,
    required this.value,
    required this.icon,
    this.valueColor,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.l),
        decoration: BoxDecoration(
          color: colors.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: valueColor ?? colors.primary),
            const SizedBox(height: AppSpacing.s),
            Text(value,
                style: text.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: valueColor,
                )),
            Text(label,
                style: text.bodySmall?.copyWith(color: colors.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }
}

class _SentimentBar extends StatelessWidget {
  const _SentimentBar({
    required this.label,
    required this.count,
    required this.total,
    required this.color,
  });

  final String label;
  final int count;
  final int total;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;
    final pct = total == 0 ? 0.0 : count / total;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: AppSpacing.s),
            Expanded(
                child: Text(label,
                    style: text.bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w600))),
            Text('$count  (${(pct * 100).toStringAsFixed(0)}%)',
                style: text.bodySmall),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(99),
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: pct),
            duration: const Duration(milliseconds: 800),
            curve: Curves.easeOutCubic,
            builder: (context, v, _) => LinearProgressIndicator(
              value: v,
              minHeight: 8,
              backgroundColor: colors.surfaceContainerHighest,
              color: color,
            ),
          ),
        ),
      ],
    );
  }
}

class _MiniCount extends StatelessWidget {
  const _MiniCount({required this.value, required this.color});
  final int value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(left: 6),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        '$value',
        style: TextStyle(
            color: color, fontWeight: FontWeight.w700, fontSize: 12),
      ),
    );
  }
}

class _SentimentChip extends StatelessWidget {
  const _SentimentChip({required this.sentiment});
  final Sentiment sentiment;

  @override
  Widget build(BuildContext context) {
    final color = switch (sentiment) {
      Sentiment.positive => _kPositive,
      Sentiment.neutral => _kNeutral,
      Sentiment.negative => _kNegative,
    };
    final icon = switch (sentiment) {
      Sentiment.positive => Icons.sentiment_satisfied_alt_rounded,
      Sentiment.neutral => Icons.sentiment_neutral_rounded,
      Sentiment.negative => Icons.sentiment_dissatisfied_rounded,
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 5),
          Text(
            sentiment.label,
            style: TextStyle(
                color: color, fontWeight: FontWeight.w700, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
