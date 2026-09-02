import 'package:flutter/material.dart';

import 'theme.dart';
import 'motion.dart';
import 'sentiment.dart';

// ===========================================================================
// Sentiment Analyser — Model Evaluation
//
// Measures how accurate the app's NLP classifier is against a hand-labelled
// test set (the "gold standard"). This is the standard way sentiment models
// are validated, and it gives the study a concrete, defensible accuracy
// figure instead of an unmeasured claim.
//
// Metrics reported:
//   • Accuracy  — overall proportion of correct classifications
//   • Precision — of the items predicted as class X, how many were right
//   • Recall    — of the actual class-X items, how many were found
//   • F1-score  — harmonic mean of precision and recall
//   • Confusion matrix — predicted vs. actual, per class
// ===========================================================================

/// One hand-labelled test case.
class LabeledSample {
  final String text;
  final Sentiment expected;
  const LabeledSample(this.text, this.expected);
}

/// Hand-labelled test set: realistic visitor comments in English, Filipino
/// and Taglish, balanced across the three classes.
const List<LabeledSample> kTestSet = [
  // ---------------- POSITIVE ----------------
  LabeledSample(
      'The church was very beautiful and the staff were friendly.',
      Sentiment.positive),
  LabeledSample('Excellent heritage trail, I really enjoyed the experience.',
      Sentiment.positive),
  LabeledSample('Very clean and well organized. Highly recommend.',
      Sentiment.positive),
  LabeledSample('Maganda ang simbahan at malinis ang paligid.',
      Sentiment.positive),
  LabeledSample('Sobrang ganda ng lugar, sulit ang punta.',
      Sentiment.positive),
  LabeledSample('The staff were helpful and the place felt safe.',
      Sentiment.positive),
  LabeledSample('Amazing experience, the guides were informative.',
      Sentiment.positive),
  LabeledSample('Salamat sa mabilis at maayos na serbisyo.',
      Sentiment.positive),
  LabeledSample('Great app, easy to use and very convenient.',
      Sentiment.positive),
  LabeledSample('Loved the historic churches, well preserved.',
      Sentiment.positive),
  LabeledSample('Ang galing ng programa, masaya kami.', Sentiment.positive),
  LabeledSample('Affordable and worth the visit. Thank you!',
      Sentiment.positive),
  LabeledSample('The festival was wonderful and well attended.',
      Sentiment.positive),
  LabeledSample('Peaceful and comfortable place to visit.',
      Sentiment.positive),
  LabeledSample('Napakabait ng mga staff, mabilis ang proseso.',
      Sentiment.positive),

  // ---------------- NEGATIVE ----------------
  LabeledSample('The area was dirty and the staff were rude.',
      Sentiment.negative),
  LabeledSample('Terrible experience, very disappointing service.',
      Sentiment.negative),
  LabeledSample('Too crowded and the queue was extremely slow.',
      Sentiment.negative),
  LabeledSample('Madumi ang palikuran at mabagal ang serbisyo.',
      Sentiment.negative),
  LabeledSample('Hindi maganda, sobrang dumi ng lugar.', Sentiment.negative),
  LabeledSample('The signage was confusing and hard to follow.',
      Sentiment.negative),
  LabeledSample('Poor maintenance, many facilities are broken.',
      Sentiment.negative),
  LabeledSample('Delikado ang daan at walang ilaw sa gabi.',
      Sentiment.negative),
  LabeledSample('Worst service I have experienced, very unorganized.',
      Sentiment.negative),
  LabeledSample('Masyadong mahal at kulang ang pasilidad.',
      Sentiment.negative),
  LabeledSample('The place was neglected and smelly.', Sentiment.negative),
  LabeledSample('Baha agad kapag umuulan, delikado.', Sentiment.negative),
  LabeledSample('Not good at all, the tour was a waste of time.',
      Sentiment.negative),
  LabeledSample('Pangit ang kalsada at maraming basura.',
      Sentiment.negative),
  LabeledSample('Unsafe and poorly lit, I would not return.',
      Sentiment.negative),

  // ---------------- NEUTRAL ----------------
  LabeledSample('I visited the church last Sunday afternoon.',
      Sentiment.neutral),
  LabeledSample('The event starts at nine in the morning.',
      Sentiment.neutral),
  LabeledSample('There are nine heritage churches on the trail.',
      Sentiment.neutral),
  LabeledSample('Pumunta ako sa city hall kahapon.', Sentiment.neutral),
  LabeledSample('I would like to ask about the schedule of the festival.',
      Sentiment.neutral),
  LabeledSample('The office is located near the main road.',
      Sentiment.neutral),
  LabeledSample('May tanong ako tungkol sa requirements.',
      Sentiment.neutral),
  LabeledSample('I downloaded the app yesterday.', Sentiment.neutral),
  LabeledSample('The tour takes about two hours to complete.',
      Sentiment.neutral),
  LabeledSample('Ilan po ang bayad para sa entrance?', Sentiment.neutral),
  LabeledSample('Please send the details to my email address.',
      Sentiment.neutral),
  LabeledSample('The building was constructed in 1863.', Sentiment.neutral),
  LabeledSample('Nagpunta kami ng pamilya ko noong Sabado.',
      Sentiment.neutral),
  LabeledSample('I am asking for the list of accredited establishments.',
      Sentiment.neutral),
  LabeledSample('The map shows the location of each stop.',
      Sentiment.neutral),
];

/// Metrics for a single class.
class ClassMetrics {
  final Sentiment sentiment;
  final int truePositives;
  final int falsePositives;
  final int falseNegatives;

  const ClassMetrics({
    required this.sentiment,
    required this.truePositives,
    required this.falsePositives,
    required this.falseNegatives,
  });

  double get precision => (truePositives + falsePositives) == 0
      ? 0
      : truePositives / (truePositives + falsePositives);

  double get recall => (truePositives + falseNegatives) == 0
      ? 0
      : truePositives / (truePositives + falseNegatives);

  double get f1 => (precision + recall) == 0
      ? 0
      : 2 * precision * recall / (precision + recall);
}

class EvaluationResult {
  final int total;
  final int correct;
  final List<ClassMetrics> perClass;
  final Map<Sentiment, Map<Sentiment, int>> confusion; // actual → predicted
  final List<({String text, Sentiment expected, Sentiment got})> misses;

  const EvaluationResult({
    required this.total,
    required this.correct,
    required this.perClass,
    required this.confusion,
    required this.misses,
  });

  double get accuracy => total == 0 ? 0 : correct / total;

  /// Unweighted mean F1 across the three classes.
  double get macroF1 => perClass.isEmpty
      ? 0
      : perClass.map((m) => m.f1).reduce((a, b) => a + b) / perClass.length;
}

class SentimentEvaluator {
  SentimentEvaluator._();

  static EvaluationResult run([List<LabeledSample> set = kTestSet]) {
    final confusion = <Sentiment, Map<Sentiment, int>>{
      for (final a in Sentiment.values)
        a: {for (final p in Sentiment.values) p: 0}
    };
    final misses = <({String text, Sentiment expected, Sentiment got})>[];
    int correct = 0;

    for (final s in set) {
      final predicted = SentimentAnalyzer.analyze(s.text).sentiment;
      confusion[s.expected]![predicted] =
          confusion[s.expected]![predicted]! + 1;
      if (predicted == s.expected) {
        correct++;
      } else {
        misses.add((text: s.text, expected: s.expected, got: predicted));
      }
    }

    final perClass = <ClassMetrics>[];
    for (final c in Sentiment.values) {
      final tp = confusion[c]![c]!;
      int fp = 0, fn = 0;
      for (final other in Sentiment.values) {
        if (other == c) continue;
        fp += confusion[other]![c]!; // predicted c but actually other
        fn += confusion[c]![other]!; // actually c but predicted other
      }
      perClass.add(ClassMetrics(
        sentiment: c,
        truePositives: tp,
        falsePositives: fp,
        falseNegatives: fn,
      ));
    }

    return EvaluationResult(
      total: set.length,
      correct: correct,
      perClass: perClass,
      confusion: confusion,
      misses: misses,
    );
  }
}

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------
class SentimentEvalPage extends StatelessWidget {
  const SentimentEvalPage({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final r = SentimentEvaluator.run();
    final pct = (r.accuracy * 100);

    return Scaffold(
      appBar: AppBar(title: const Text('Sentiment Model Accuracy')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.l),
        children: [
          Reveal(
            delayMs: 0,
            child: Text('Model evaluation', style: text.titleLarge),
          ),
          const SizedBox(height: 4),
          Reveal(
            delayMs: 40,
            child: Text(
              'The classifier was tested against ${r.total} hand-labelled '
              'visitor comments in English, Filipino and Taglish.',
              style: text.bodyMedium?.copyWith(color: colors.onSurfaceVariant),
            ),
          ),
          const SizedBox(height: AppSpacing.xl),

          // ---- Headline accuracy ----
          Reveal(
            delayMs: 80,
            child: Container(
              padding: const EdgeInsets.all(AppSpacing.xl),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF12305F), Color(0xFF1E4B8F)],
                ),
                borderRadius: BorderRadius.circular(AppRadius.xl),
              ),
              child: Column(
                children: [
                  Text('Overall accuracy',
                      style: text.labelMedium?.copyWith(
                          color: Colors.white.withValues(alpha: 0.85))),
                  const SizedBox(height: AppSpacing.s),
                  TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: pct),
                    duration: const Duration(milliseconds: 1200),
                    curve: Curves.easeOutCubic,
                    builder: (context, v, _) => Text(
                      '${v.toStringAsFixed(1)}%',
                      style: AppTheme.brandTextStyle(
                          fontSize: 44, color: AppTheme.brandGold),
                    ),
                  ),
                  Text('${r.correct} of ${r.total} correctly classified',
                      style: text.bodySmall?.copyWith(
                          color: Colors.white.withValues(alpha: 0.8))),
                  const SizedBox(height: AppSpacing.m),
                  Text('Macro F1-score: ${r.macroF1.toStringAsFixed(3)}',
                      style: text.bodySmall?.copyWith(
                          color: Colors.white.withValues(alpha: 0.9))),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.xl),

          // ---- Per-class metrics ----
          Reveal(
            delayMs: 140,
            child: Text('Per-class metrics', style: text.titleMedium),
          ),
          const SizedBox(height: AppSpacing.m),
          Reveal(
            delayMs: 180,
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.m),
                child: Table(
                  columnWidths: const {
                    0: FlexColumnWidth(2.2),
                    1: FlexColumnWidth(1.4),
                    2: FlexColumnWidth(1.2),
                    3: FlexColumnWidth(1),
                  },
                  children: [
                    TableRow(
                      children: [
                        _cell('Class', bold: true),
                        _cell('Precision', bold: true),
                        _cell('Recall', bold: true),
                        _cell('F1', bold: true),
                      ],
                    ),
                    for (final m in r.perClass)
                      TableRow(
                        children: [
                          _cell(m.sentiment.label),
                          _cell(m.precision.toStringAsFixed(2)),
                          _cell(m.recall.toStringAsFixed(2)),
                          _cell(m.f1.toStringAsFixed(2)),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.xl),

          // ---- Confusion matrix ----
          Reveal(
            delayMs: 240,
            child: Text('Confusion matrix', style: text.titleMedium),
          ),
          const SizedBox(height: 4),
          Reveal(
            delayMs: 260,
            child: Text('Rows = actual label, columns = predicted label.',
                style: text.bodySmall?.copyWith(color: colors.onSurfaceVariant)),
          ),
          const SizedBox(height: AppSpacing.m),
          Reveal(
            delayMs: 300,
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.m),
                child: Table(
                  children: [
                    TableRow(children: [
                      _cell('', bold: true),
                      _cell('Pos', bold: true),
                      _cell('Neu', bold: true),
                      _cell('Neg', bold: true),
                    ]),
                    for (final actual in Sentiment.values)
                      TableRow(children: [
                        _cell(actual.label, bold: true),
                        for (final pred in Sentiment.values)
                          _cell(
                            '${r.confusion[actual]![pred]}',
                            highlight: actual == pred,
                          ),
                      ]),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.xl),

          // ---- Misclassified samples ----
          if (r.misses.isNotEmpty) ...[
            Reveal(
              delayMs: 340,
              child: Text('Misclassified samples (${r.misses.length})',
                  style: text.titleMedium),
            ),
            const SizedBox(height: AppSpacing.s),
            for (final m in r.misses)
              Card(
                margin: const EdgeInsets.only(bottom: AppSpacing.s),
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.m),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('"${m.text}"', style: text.bodySmall),
                      const SizedBox(height: 4),
                      Text(
                        'Expected ${m.expected.label} · Predicted ${m.got.label}',
                        style: text.labelSmall
                            ?.copyWith(color: colors.error),
                      ),
                    ],
                  ),
                ),
              ),
          ],
          const SizedBox(height: AppSpacing.l),

          Card(
            color: colors.surfaceContainerHighest,
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.l),
              child: Row(
                children: [
                  Icon(Icons.science_outlined, color: colors.outline),
                  const SizedBox(width: AppSpacing.m),
                  Expanded(
                    child: Text(
                      'The classifier uses a lexicon-based approach with '
                      'negation and intensifier handling, the same method as '
                      'VADER. It runs on-device, so no feedback is sent to an '
                      'external service.',
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

  Widget _cell(String s, {bool bold = false, bool highlight = false}) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        child: Text(
          s,
          style: TextStyle(
            fontWeight: bold || highlight ? FontWeight.w700 : FontWeight.w400,
            color: highlight ? AppTheme.brandGold : null,
          ),
        ),
      );
}
