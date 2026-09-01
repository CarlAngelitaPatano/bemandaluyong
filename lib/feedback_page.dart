import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'theme.dart';
import 'motion.dart';
import 'user_role.dart';
import 'content_filter.dart'; // profanity / threat / spam screening
import 'tcims_api.dart'; // shared TCIMS backend (MySQL) — feedback + sentiment
import 'heritage.dart'; // kChurches
import 'attractions.dart'; // kAttractions
import 'dining.dart'; // kEateries

// ===========================================================================
// Visitor feedback.
//
// The mobile app COLLECTS feedback; the CCAT web dashboard CLASSIFIES it
// (positive / neutral / negative) with NLP and displays it alongside tourism
// statistics. Both share one Firestore database in the Firebase project
// `be-mandaluyong-4sight`, which is what makes this a genuinely centralised,
// cross-platform system.
//
// ---------------------------------------------------------------------------
// SHARED SCHEMA — must match what Emmanuel's website reads.
// If the website uses different names, change them HERE only.
// ---------------------------------------------------------------------------
class FeedbackSchema {
  FeedbackSchema._();

  /// Firestore collection the website reads from.
  static const String collection = 'feedback';

  // Field names
  static const String fMessage = 'message'; // the text the NLP analyses
  static const String fRating = 'rating'; // 1–5 stars
  static const String fCategory = 'category'; // what it's about
  static const String fSubject = 'subject'; // the specific place, if named
  static const String fName = 'name'; // display name (may be 'Anonymous')
  static const String fEmail = 'email'; // account email, if signed in
  static const String fUserId = 'userId'; // Firebase uid
  static const String fUserType = 'userType'; // Tourist | Mandaleño
  static const String fSource = 'source'; // 'mobile' vs website's 'web'
  static const String fSentiment = 'sentiment'; // positive|neutral|negative
  static const String fSentimentScore = 'sentimentScore'; // numeric polarity
  static const String fCreatedAt = 'createdAt'; // server timestamp
}

/// What the feedback is about — mirrors CCAT's areas of responsibility.
const List<String> kFeedbackCategories = [
  'Heritage sites & churches',
  'Tourist attractions',
  'Events & festivals',
  'City services',
  'Local businesses & food',
  'The mobile app',
  'Other',
];

/// The specific places a user can name for a given category, so CCAT can see
/// exactly which church, landmark or establishment the comment refers to.
List<String> subjectsForCategory(String category) {
  switch (category) {
    case 'Heritage sites & churches':
      return kChurches.map((c) => c.name).toList();
    case 'Tourist attractions':
      return kAttractions.map((a) => a.title).toList();
    case 'Local businesses & food':
      return kEateries.map((e) => e.name).toList();
    default:
      return const [];
  }
}

/// Label for the specific-place dropdown.
String subjectLabelFor(String category) {
  switch (category) {
    case 'Heritage sites & churches':
      return 'Which church or heritage site?';
    case 'Tourist attractions':
      return 'Which attraction?';
    case 'Local businesses & food':
      return 'Which establishment?';
    default:
      return 'Which place?';
  }
}

class FeedbackPage extends StatefulWidget {
  const FeedbackPage({super.key});

  @override
  State<FeedbackPage> createState() => _FeedbackPageState();
}

class _FeedbackPageState extends State<FeedbackPage> {
  final _formKey = GlobalKey<FormState>();
  final _message = TextEditingController();
  int _rating = 0;
  String _category = kFeedbackCategories.first;
  String? _subject; // the specific church / attraction / establishment
  bool _anonymous = false;
  bool _sending = false;

  @override
  void dispose() {
    _message.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_rating == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please give a star rating first.')),
      );
      return;
    }

    // ---- Content moderation: screen before anything is uploaded ----
    final moderation = ContentFilter.check(_message.text);
    if (!moderation.isClean) {
      await showDialog(
        context: context,
        builder: (context) => AlertDialog(
          icon: Icon(
            moderation.verdict == ModerationVerdict.threat
                ? Icons.gpp_maybe_outlined
                : Icons.edit_note_outlined,
            color: AppTheme.cityRed,
            size: 40,
          ),
          title: Text(moderation.title),
          content: Text(moderation.message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Edit my message'),
            ),
          ],
        ),
      );
      return; // nothing is saved
    }

    setState(() => _sending = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      // The specific church/attraction if one was chosen, otherwise the
      // category — api/feedback.php requires a non-empty "place".
      final place = (_subject != null && _subject!.isNotEmpty)
          ? _subject!
          : _category;
      final reviewerName = _anonymous
          ? 'Anonymous'
          : (user?.displayName ?? user?.email ?? UserRoleStore.current.label);

      // The RAW comment is sent — the SERVER classifies it, using the same
      // lexicon the website uses, so the app and the web can never disagree
      // about a review's sentiment. No sentiment value is sent from here.
      final result = await TcimsApi.post('/api/feedback.php', {
        'place': place,
        'rating': _rating,
        'comment': _message.text.trim(),
        'reviewer': reviewerName,
      });

      if (result == null || result['success'] != true) {
        if (!mounted) return;
        final serverError = (result is Map) ? result['error'] as String? : null;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(serverError ??
                'Could not send your feedback. Check your internet '
                    'connection and try again.'),
          ),
        );
        return;
      }

      // The server returns "Positive" / "Neutral" / "Negative" — this is the
      // official classification, shown as-is.
      final officialSentiment = (result['sentiment'] as String?) ?? 'Neutral';

      if (!mounted) return;
      await showDialog(
        context: context,
        builder: (context) => AlertDialog(
          icon: const Icon(Icons.check_circle_outline,
              color: AppTheme.brandGold, size: 44),
          title: const Text('Thank you!'),
          content: Text(
            'Your feedback has been sent to the City Cultural Affairs and '
            'Tourism office (classified as $officialSentiment). It helps '
            'them improve the city\'s services and heritage programs.',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Done'),
            ),
          ],
        ),
      );
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'Could not send your feedback. Check your internet connection '
              'and try again.'),
        ),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  String get _ratingWord => switch (_rating) {
        1 => 'Poor',
        2 => 'Fair',
        3 => 'Good',
        4 => 'Very good',
        5 => 'Excellent',
        _ => 'Tap a star to rate',
      };

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Share your feedback')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.l),
          children: [
            Reveal(
              delayMs: 0,
              child: Text('How was your experience?', style: text.titleLarge),
            ),
            const SizedBox(height: 4),
            Reveal(
              delayMs: 40,
              child: Text(
                'Your feedback goes straight to the City Cultural Affairs and '
                'Tourism office.',
                style: text.bodyMedium?.copyWith(color: colors.outline),
              ),
            ),
            const SizedBox(height: AppSpacing.xl),

            // ---- Star rating ----
            Reveal(
              delayMs: 80,
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      for (int i = 1; i <= 5; i++)
                        IconButton(
                          onPressed: () => setState(() => _rating = i),
                          iconSize: 40,
                          icon: Icon(
                            i <= _rating ? Icons.star_rounded : Icons.star_outline_rounded,
                            color: i <= _rating
                                ? AppTheme.brandGold
                                : colors.outlineVariant,
                          ),
                        ),
                    ],
                  ),
                  Text(
                    _ratingWord,
                    style: text.titleSmall?.copyWith(
                      color: _rating == 0 ? colors.outline : colors.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.xl),

            // ---- Category ----
            Reveal(
              delayMs: 120,
              child: DropdownButtonFormField<String>(
                initialValue: _category,
                decoration: const InputDecoration(
                  labelText: 'What is your feedback about?',
                  prefixIcon: Icon(Icons.category_outlined),
                  border: OutlineInputBorder(),
                ),
                items: [
                  for (final c in kFeedbackCategories)
                    DropdownMenuItem(value: c, child: Text(c)),
                ],
                onChanged: (v) => setState(() {
                  _category = v ?? _category;
                  _subject = null; // the place list changes with the category
                }),
              ),
            ),

            // ---- Specific place (only for categories that have one) ----
            if (subjectsForCategory(_category).isNotEmpty) ...[
              const SizedBox(height: AppSpacing.l),
              Reveal(
                delayMs: 140,
                child: DropdownButtonFormField<String>(
                  initialValue: _subject,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: subjectLabelFor(_category),
                    prefixIcon: const Icon(Icons.place_outlined),
                    border: const OutlineInputBorder(),
                    helperText: 'Optional — helps CCAT act on your feedback',
                  ),
                  items: [
                    const DropdownMenuItem<String>(
                      value: null,
                      child: Text('Not specific / general'),
                    ),
                    for (final s in subjectsForCategory(_category))
                      DropdownMenuItem(
                        value: s,
                        child: Text(s, overflow: TextOverflow.ellipsis),
                      ),
                  ],
                  onChanged: (v) => setState(() => _subject = v),
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.l),

            // ---- The comment (this is what the NLP analyses) ----
            Reveal(
              delayMs: 160,
              child: TextFormField(
                controller: _message,
                maxLines: 6,
                maxLength: 600,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Tell us more',
                  hintText:
                      'What did you enjoy? What could the city improve?',
                  alignLabelWithHint: true,
                  border: OutlineInputBorder(),
                ),
                validator: (v) {
                  final s = v?.trim() ?? '';
                  if (s.isEmpty) return 'Please write your feedback';
                  if (s.length < 10) {
                    return 'Please write a little more (at least 10 characters)';
                  }
                  return null;
                },
              ),
            ),

            // ---- Anonymous option ----
            Reveal(
              delayMs: 200,
              child: CheckboxListTile(
                value: _anonymous,
                onChanged: (v) => setState(() => _anonymous = v ?? false),
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
                title: const Text('Send anonymously'),
                subtitle: const Text('Your name and email won\'t be included'),
              ),
            ),
            const SizedBox(height: AppSpacing.l),

            Reveal(
              delayMs: 240,
              child: FilledButton.icon(
                onPressed: _sending ? null : _submit,
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.m),
                ),
                icon: _sending
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.send_rounded),
                label: Text(_sending ? 'Sending…' : 'Send feedback'),
              ),
            ),
            const SizedBox(height: AppSpacing.l),

            Card(
              color: colors.surfaceContainerHighest,
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.l),
                child: Row(
                  children: [
                    Icon(Icons.insights_outlined, color: colors.outline),
                    const SizedBox(width: AppSpacing.m),
                    Expanded(
                      child: Text(
                        'Feedback sent here is analysed by the CCAT dashboard, '
                        'which automatically groups comments as positive, '
                        'neutral or negative to guide city decisions.',
                        style: text.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
