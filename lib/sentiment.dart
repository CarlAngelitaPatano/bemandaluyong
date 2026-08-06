// ===========================================================================
// Sentiment Analysis (Natural Language Processing)
//
// Implements a lexicon-based sentiment classifier that reads visitor feedback
// and automatically classifies it as POSITIVE, NEUTRAL or NEGATIVE — the
// approach used by tools such as VADER (Valence Aware Dictionary for
// sEntiment Reasoning).
//
// It runs entirely ON DEVICE, so it works offline, costs nothing, and no
// feedback text is ever sent to a third-party service.
//
// The pipeline is the standard NLP sequence:
//   1. Normalisation   — lowercase, strip punctuation
//   2. Tokenisation    — split the text into words
//   3. Negation handling — "not good" flips the polarity of "good"
//   4. Intensifier handling — "very good" strengthens the score
//   5. Lexicon scoring — each token looked up in a polarity dictionary
//   6. Classification  — the summed score is mapped to a label
//
// The lexicon covers English AND common Filipino/Taglish words, because
// visitors in Mandaluyong frequently write feedback in both.
// ===========================================================================

enum Sentiment { positive, neutral, negative }

extension SentimentInfo on Sentiment {
  /// Stored in Firestore and read by the CCAT dashboard.
  String get id => switch (this) {
        Sentiment.positive => 'positive',
        Sentiment.neutral => 'neutral',
        Sentiment.negative => 'negative',
      };

  String get label => switch (this) {
        Sentiment.positive => 'Positive',
        Sentiment.neutral => 'Neutral',
        Sentiment.negative => 'Negative',
      };
}

Sentiment sentimentFromId(String? id) => switch (id) {
      'positive' => Sentiment.positive,
      'negative' => Sentiment.negative,
      _ => Sentiment.neutral,
    };

/// The outcome of analysing one piece of feedback.
class SentimentResult {
  final Sentiment sentiment;
  final double score; // negative = unhappy, positive = happy
  final int positiveHits;
  final int negativeHits;

  const SentimentResult({
    required this.sentiment,
    required this.score,
    required this.positiveHits,
    required this.negativeHits,
  });
}

class SentimentAnalyzer {
  SentimentAnalyzer._();

  // --- Polarity lexicon ----------------------------------------------------
  // Weights: 2.0 = strongly positive/negative, 1.0 = mildly so.
  static const Map<String, double> _lexicon = {
    // ---------- English positive ----------
    'excellent': 2.0, 'amazing': 2.0, 'outstanding': 2.0, 'perfect': 2.0,
    'wonderful': 2.0, 'fantastic': 2.0, 'love': 2.0, 'loved': 2.0,
    'best': 2.0, 'awesome': 2.0, 'beautiful': 1.8, 'great': 1.8,
    'impressive': 1.8, 'enjoyed': 1.5, 'enjoy': 1.5, 'good': 1.5,
    'nice': 1.3, 'clean': 1.3, 'helpful': 1.5, 'friendly': 1.5,
    'organized': 1.3, 'safe': 1.3, 'convenient': 1.3, 'accessible': 1.3,
    'informative': 1.3, 'recommend': 1.8, 'satisfied': 1.5, 'happy': 1.5,
    'peaceful': 1.3, 'comfortable': 1.3, 'affordable': 1.3, 'fast': 1.0,
    'easy': 1.2, 'smooth': 1.2, 'worth': 1.2, 'well': 1.0, 'like': 1.0,
    'thanks': 1.2, 'thank': 1.2, 'appreciate': 1.5, 'improved': 1.3,
    'historic': 0.8, 'preserved': 1.2, 'welcoming': 1.5,

    // ---------- Filipino / Taglish positive ----------
    'maganda': 1.8, 'maayos': 1.5, 'malinis': 1.5, 'mabait': 1.5,
    'masaya': 1.5, 'magaling': 1.8, 'salamat': 1.2, 'ganda': 1.8,
    'astig': 1.5, 'sulit': 1.5, 'mabilis': 1.2, 'tahimik': 1.2,
    'ligtas': 1.3, 'presyo': 0.0, 'okay': 0.8, 'ok': 0.8, 'galing': 1.8,
    'ayos': 1.3, 'husay': 1.8, 'saya': 1.5,

    // ---------- English negative ----------
    'terrible': -2.0, 'awful': -2.0, 'horrible': -2.0, 'worst': -2.0,
    'hate': -2.0, 'disgusting': -2.0, 'unacceptable': -2.0,
    'bad': -1.5, 'poor': -1.5, 'dirty': -1.8, 'rude': -1.8,
    'slow': -1.3, 'expensive': -1.2, 'crowded': -1.0, 'noisy': -1.0,
    'confusing': -1.3, 'difficult': -1.3, 'hard': -1.0, 'broken': -1.5,
    'disappointed': -1.8, 'disappointing': -1.8, 'unsafe': -1.8,
    'dangerous': -1.8, 'problem': -1.2, 'problems': -1.2, 'issue': -1.0,
    'issues': -1.0, 'complaint': -1.3, 'delay': -1.2, 'delayed': -1.2,
    'lacking': -1.3, 'lack': -1.3, 'need': -0.5, 'improve': -0.6,
    'unorganized': -1.5, 'inconvenient': -1.3, 'waste': -1.5,
    'neglected': -1.5, 'damaged': -1.5, 'smelly': -1.5, 'flooded': -1.5,

    // ---------- Filipino / Taglish negative ----------
    'pangit': -1.8, 'madumi': -1.8, 'masama': -1.8, 'bastos': -1.8,
    'mabagal': -1.3, 'mahal': -1.2, 'sikip': -1.2, 'maingay': -1.0,
    'sira': -1.5, 'basura': -1.5, 'baha': -1.5, 'delikado': -1.8,
    'hirap': -1.3, 'mahirap': -1.3, 'reklamo': -1.3, 'walang': -1.0,
    'kulang': -1.3, 'panget': -1.8,
  };

  /// Words that flip the polarity of the next few words.
  static const Set<String> _negations = {
    'not', 'no', 'never', 'none', 'cannot', 'cant', 'dont', 'doesnt',
    'didnt', 'isnt', 'wasnt', 'wont', 'without', 'hardly', 'barely',
    'hindi', 'wala', 'di', 'ayaw',
  };

  /// Words that strengthen the next word's score.
  static const Map<String, double> _intensifiers = {
    'very': 1.5, 'really': 1.5, 'so': 1.4, 'extremely': 1.8,
    'super': 1.6, 'too': 1.3, 'highly': 1.5, 'absolutely': 1.7,
    'totally': 1.5, 'completely': 1.5, 'sobrang': 1.6, 'napaka': 1.6,
    'talagang': 1.4, 'grabe': 1.5, 'masyado': 1.4,
  };

  /// Runs the full NLP pipeline over [text] and returns the classification.
  static SentimentResult analyze(String text) {
    // 1. Normalisation
    final normalized = text
        .toLowerCase()
        .replaceAll(RegExp(r"[^a-z0-9\sáéíóúñ']"), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    if (normalized.isEmpty) {
      return const SentimentResult(
        sentiment: Sentiment.neutral,
        score: 0,
        positiveHits: 0,
        negativeHits: 0,
      );
    }

    // 2. Tokenisation
    final tokens = normalized.split(' ');

    double total = 0;
    int positives = 0;
    int negatives = 0;

    for (int i = 0; i < tokens.length; i++) {
      final word = tokens[i];
      final base = _lexicon[word];
      if (base == null || base == 0) continue;

      double value = base;

      // 3. Negation — check the 2 words before this one.
      bool negated = false;
      for (int back = 1; back <= 2; back++) {
        final j = i - back;
        if (j >= 0 && _negations.contains(tokens[j])) {
          negated = true;
          break;
        }
      }
      if (negated) value = -value * 0.85; // flipped, slightly dampened

      // 4. Intensifiers — check the word immediately before.
      if (i > 0) {
        final boost = _intensifiers[tokens[i - 1]];
        if (boost != null) value *= boost;
      }

      // 5. Accumulate
      total += value;
      if (value > 0) {
        positives++;
      } else if (value < 0) {
        negatives++;
      }
    }

    // Normalise by length so long comments aren't unfairly extreme.
    final normalizedScore = total / (1 + (tokens.length / 25));

    // 6. Classification
    final Sentiment label;
    if (normalizedScore >= 0.5) {
      label = Sentiment.positive;
    } else if (normalizedScore <= -0.5) {
      label = Sentiment.negative;
    } else {
      label = Sentiment.neutral;
    }

    return SentimentResult(
      sentiment: label,
      score: normalizedScore,
      positiveHits: positives,
      negativeHits: negatives,
    );
  }

  /// Combines the written comment with the star rating. The rating is a
  /// strong explicit signal, so it breaks ties when the text is ambiguous.
  static Sentiment analyzeWithRating(String text, int rating) {
    final result = analyze(text);
    if (result.sentiment != Sentiment.neutral) return result.sentiment;
    if (rating >= 4) return Sentiment.positive;
    if (rating <= 2) return Sentiment.negative;
    return Sentiment.neutral;
  }
}
