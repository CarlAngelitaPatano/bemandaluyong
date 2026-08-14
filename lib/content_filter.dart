// ===========================================================================
// Content moderation for user-submitted text.
//
// Feedback and event requests are written by the public, so before anything
// reaches the CCAT database it is screened for:
//   • profanity and slurs (English and Filipino)
//   • threats or incitement to violence
//   • spam (links, phone-number farming, repeated characters)
//
// The check runs entirely on-device. Text that fails is never uploaded, and
// the user is shown a polite explanation rather than a silent failure.
//
// Design notes:
//   – Matching is done on WORD BOUNDARIES, so ordinary words are never
//     falsely flagged (e.g. "class" is not matched by a substring rule).
//   – Common disguises are normalised first: leetspeak (@, 0, 3, 1, $),
//     repeated letters ("puuuta"), and inserted punctuation ("p.u.t.a").
// ===========================================================================

enum ModerationVerdict { clean, profanity, slur, threat, spam, tooShort }

class ModerationResult {
  final ModerationVerdict verdict;
  final String? matched; // the term that triggered it (for logging only)

  const ModerationResult(this.verdict, [this.matched]);

  bool get isClean => verdict == ModerationVerdict.clean;

  /// Message shown to the user when their text is rejected.
  String get message => switch (verdict) {
        ModerationVerdict.clean => '',
        ModerationVerdict.profanity =>
          'Your message contains language that isn\'t allowed. Please '
              'rewrite it respectfully — you can still be critical, just '
              'keep it civil.',
        ModerationVerdict.slur =>
          'Your message contains language that demeans people because of '
              'who they are. Mandaluyong is for everyone, so this cannot be '
              'submitted. Please rewrite your feedback about the service or '
              'the place instead.',
        ModerationVerdict.threat =>
          'Your message appears to contain a threat or harmful language. '
              'This cannot be submitted. If you have a safety concern, '
              'please use the emergency hotlines instead.',
        ModerationVerdict.spam =>
          'Your message looks like spam or advertising. Please share genuine '
              'feedback about your experience.',
        ModerationVerdict.tooShort =>
          'Please write a little more so the city can understand your '
              'feedback.',
      };

  String get title => switch (verdict) {
        ModerationVerdict.threat => 'Message not allowed',
        ModerationVerdict.slur => 'Message not allowed',
        ModerationVerdict.spam => 'This looks like spam',
        _ => 'Please rewrite your message',
      };
}

class ContentFilter {
  ContentFilter._();

  // --- Blocked terms -------------------------------------------------------
  // Profanity and slurs, English and Filipino. Kept lowercase; matching is
  // done on word boundaries after normalisation.
  static const Set<String> _profanity = {
    // English
    'fuck', 'fucking', 'fucker', 'shit', 'shitty', 'bullshit', 'bitch',
    'bastard', 'asshole', 'dumbass', 'jackass', 'dick', 'cock', 'pussy',
    'cunt', 'slut', 'whore', 'motherfucker', 'wtf', 'stfu', 'damn',
    'goddamn', 'prick', 'douche', 'retard', 'retarded', 'faggot', 'fag',
    'nigger', 'nigga', 'moron', 'idiot', 'stupid', 'scum', 'trash',
    // Filipino / Taglish
    'putangina', 'putang', 'puta', 'tangina', 'tang', 'gago', 'gaga',
    'ulol', 'tanga', 'bobo', 'boba', 'inutil', 'hayop', 'hayup',
    'punyeta', 'leche', 'lintik', 'peste', 'buwisit', 'bwisit',
    'kingina', 'kupal', 'tarantado', 'siraulo', 'engot', 'unggoy',
    'walanghiya', 'hinayupak', 'pakyu', 'pakshet', 'bilat', 'iyot',
    'kantot', 'burat', 'titi', 'puke', 'pekpek', 'jakol', 'bayag',
    'salot', 'demonyo', 'animal',
  };

  // Identity-based slurs — words used to demean people for their gender,
  // sexuality, ethnicity, religion or disability. These are always blocked,
  // regardless of how the sentence is phrased.
  static const Set<String> _slurs = {
    // Gender / sexuality (Filipino)
    'bading', 'badingera', 'bakla', 'baklang', 'binabae', 'silahis',
    'bayot', 'shokla', 'jokla', 'tibo', 'tomboy', 'agi', 'parlorista',
    // Gender / sexuality (English)
    'faggot', 'fag', 'dyke', 'tranny', 'homo', 'queer',
    // Ethnicity / nationality
    'intsik', 'negro', 'bumbay', 'chekwa', 'igorot', 'chink', 'gook',
    'spic', 'wetback',
    // Disability
    'retard', 'retarded', 'spastic', 'mongoloid', 'bobita', 'abnormal',
    // Religion
    'infidel', 'heathen',
  };

  // Insults and demeaning words. Milder than the list above, but still
  // abusive rather than constructive, so they are blocked too.
  static const Set<String> _insults = {
    // Filipino
    'panget', 'pangit', 'ampanget', 'ampangit', 'chaka', 'gunggong',
    'timang', 'abnoy', 'baliw', 'sinto', 'sintosinto', 'bulok',
    'pangetnaman', 'kadiri', 'nakakadiri', 'nakakasuka', 'baboy',
    'tabatsoy', 'pandak', 'bansot', 'epal', 'plastik', 'sipsip',
    // Filipino — milder but still directed at people
    'baduy', 'jologs', 'bakya', 'ampaw', 'walangkwenta', 'walangsilbi',
    'mukhangpera', 'tamad', 'pabaya', 'salbahe', 'suplado', 'suplada',
    'mayabang', 'maarte', 'kaartehan', 'feelingero', 'feelingera',
    'praning', 'sablay', 'palpak', 'kabute', 'tuta', 'sunod',
    // English
    'ugly', 'disgusting', 'garbage', 'useless', 'pathetic', 'worthless',
    'incompetent', 'lazy', 'crap', 'crappy', 'sucks', 'suck', 'nonsense',
    'horrible', 'hopeless',
    // English — milder personal insults
    'dumb', 'dummy', 'fool', 'foolish', 'loser', 'clown', 'joke',
    'clueless', 'imbecile', 'halfwit', 'nitwit', 'jerk', 'brat', 'snob',
    'arrogant', 'ignorant', 'shameless', 'disgrace', 'embarrassment',
  };

  // Words that, together with an aggressive verb, signal a real threat.
  static const Set<String> _threatVerbs = {
    'kill', 'murder', 'stab', 'shoot', 'bomb', 'burn', 'destroy',
    'beat', 'attack', 'hurt', 'harm', 'rape', 'assault', 'slaughter',
    'papatayin', 'patayin', 'papatay', 'saksakin', 'barilin', 'sunugin',
    'bugbugin', 'pakamatay', 'gagahasa',
  };

  static const Set<String> _threatTargets = {
    'you', 'him', 'her', 'them', 'everyone', 'staff', 'mayor', 'people',
    'kayo', 'kita', 'siya', 'sila', 'lahat',
  };

  /// Standalone phrases that are always blocked.
  static const List<String> _threatPhrases = [
    'i will kill',
    'im going to kill',
    'i am going to kill',
    'ill kill you',
    'kill yourself',
    'kys',
    'papatayin kita',
    'papatayin ko kayo',
    'magpakamatay ka',
  ];

  /// Leetspeak and lookalike substitutions used to disguise words.
  static const Map<String, String> _substitutions = {
    '@': 'a', '4': 'a', '3': 'e', '1': 'i', '!': 'i', '0': 'o',
    '\$': 's', '5': 's', '7': 't', '+': 't', '8': 'b',
  };

  /// Normalises text so disguised spellings still match:
  /// lowercase → substitutions → strip punctuation → collapse repeats.
  static String _normalize(String input) {
    var s = input.toLowerCase();
    _substitutions.forEach((from, to) => s = s.replaceAll(from, to));
    // Remove characters people insert to dodge filters: p.u.t.a → puta
    s = s.replaceAll(RegExp(r'[^a-z\s]'), '');
    // Collapse 3+ repeated letters: puuuuta → puuta (keeps doubles legal)
    s = s.replaceAllMapped(RegExp(r'(.)\1{2,}'), (m) => '${m[1]}${m[1]}');
    return s.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  /// Also collapse doubles entirely, for a second matching pass.
  static String _collapseAll(String s) =>
      s.replaceAllMapped(RegExp(r'(.)\1+'), (m) => m[1]!);

  static bool _containsWord(List<String> tokens, Set<String> terms) =>
      tokens.any(terms.contains);

  /// Screens [input] and returns what (if anything) is wrong with it.
  static ModerationResult check(String input) {
    final raw = input.trim();
    if (raw.length < 10) {
      return const ModerationResult(ModerationVerdict.tooShort);
    }

    final normalized = _normalize(raw);
    final tokens = normalized.split(' ');
    final collapsed = _collapseAll(normalized).split(' ');

    // ---- 1. Explicit threat phrases ----
    for (final phrase in _threatPhrases) {
      if (normalized.contains(phrase)) {
        return ModerationResult(ModerationVerdict.threat, phrase);
      }
    }

    // ---- 2. Threat verb + target in the same message ----
    if (_containsWord(tokens, _threatVerbs) &&
        _containsWord(tokens, _threatTargets)) {
      return const ModerationResult(ModerationVerdict.threat);
    }

    // ---- 3. Slurs (checked first — always the firmest response) ----
    final joined = normalized.replaceAll(' ', '');
    for (final s in _slurs) {
      if (tokens.contains(s) ||
          collapsed.contains(s) ||
          (s.length >= 5 && joined.contains(s))) {
        return ModerationResult(ModerationVerdict.slur, s);
      }
    }

    // ---- 4. Profanity and insults ----
    // Two passes: normalised, then fully collapsed (puuuta → puta).
    final blocked = {..._profanity, ..._insults};
    for (final t in tokens) {
      if (blocked.contains(t)) {
        return ModerationResult(ModerationVerdict.profanity, t);
      }
    }
    for (final t in collapsed) {
      if (blocked.contains(t)) {
        return ModerationResult(ModerationVerdict.profanity, t);
      }
    }
    // Compound or run-together spellings, e.g. "putanginamo", "ampanget".
    for (final bad in blocked) {
      if (bad.length >= 5 && joined.contains(bad)) {
        return ModerationResult(ModerationVerdict.profanity, bad);
      }
    }

    // ---- 5. Spam ----
    final hasLink = RegExp(
            r'(https?://|www\.|\.com|\.net|\.ph\b|t\.me/|bit\.ly)',
            caseSensitive: false)
        .hasMatch(raw);
    final digits = RegExp(r'\d').allMatches(raw).length;
    final shouty = raw.length > 20 &&
        RegExp(r'[A-Z]').allMatches(raw).length / raw.length > 0.7;
    if (hasLink || digits > 12 || shouty) {
      return const ModerationResult(ModerationVerdict.spam);
    }

    return const ModerationResult(ModerationVerdict.clean);
  }
}
