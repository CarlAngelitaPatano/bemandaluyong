import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart'; // whose "seen" list this is
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'theme.dart';
import 'motion.dart';
import 'local_notifs.dart';
import 'user_role.dart'; // who an announcement is addressed to
import 'staff_access.dart'; // staff review everything, not just their own

// ===========================================================================
// Official City Announcements
//
// CCAT / the Office of the City Mayor publish announcements into the shared
// Firestore database. The app watches that collection in real time, so a new
// announcement appears immediately — and fires a phone notification the
// first time the app sees it.
//
// This is the app's own announcement channel (unlike the Facebook page,
// which the app can only display, not monitor).
//
// ---------------------------------------------------------------------------
// SHARED SCHEMA — collection `announcements`
//   title      string    headline
//   body       string    full text
//   category   string    'General' | 'Advisory' | 'Event' | 'Emergency'
//   author     string    e.g. 'Office of the City Mayor'
//   imageUrl   string    optional
//   pinned     bool      keep at the top
//   publishedAt timestamp
// ===========================================================================

const String kAnnouncementCollection = 'announcements';

/// Office of the City Mayor — official links.
const String kMayorName = 'Carmelita "Menchie" Aguilar-Abalos';
const String kMayorTitle = 'City Mayor of Mandaluyong';
const String kMayorFbPage = 'https://www.facebook.com/MenchieAbalosOfficial';
const String kCityHallSite = 'https://mandaluyong.gov.ph/';

/// Who an announcement is meant for.
///
/// Set by the staff member publishing it, because they know the audience and
/// the app cannot guess. A road closure concerns residents; a festival concerns
/// visitors; a typhoon advisory concerns everyone standing in the city.
enum Audience { everyone, visitors, residents }

Audience audienceFromId(String? id) => switch (id?.toLowerCase()) {
      'visitors' || 'tourist' || 'tourists' => Audience.visitors,
      'residents' || 'mandaleno' || 'mandaleño' => Audience.residents,
      _ => Audience.everyone,
    };

extension AudienceInfo on Audience {
  String get id => switch (this) {
        Audience.everyone => 'everyone',
        Audience.visitors => 'visitors',
        Audience.residents => 'residents',
      };

  String get label => switch (this) {
        Audience.everyone => 'Everyone',
        Audience.visitors => 'Visitors only',
        Audience.residents => 'Mandaleños only',
      };

  IconData get icon => switch (this) {
        Audience.everyone => Icons.groups_outlined,
        Audience.visitors => Icons.luggage_outlined,
        Audience.residents => Icons.home_outlined,
      };

  /// Whether somebody with [role] should receive this.
  bool reaches(UserRole role) => switch (this) {
        Audience.everyone => true,
        Audience.visitors => role == UserRole.tourist,
        Audience.residents => role == UserRole.mandaleno,
      };
}

class Announcement {
  final String id;
  final String title;
  final String body;
  final String category;
  final String author;
  final bool pinned;
  final DateTime? publishedAt;

  /// Who this was addressed to when it was published.
  final Audience audience;

  const Announcement({
    required this.id,
    required this.title,
    required this.body,
    required this.category,
    required this.author,
    required this.pinned,
    this.audience = Audience.everyone,
    this.publishedAt,
  });

  factory Announcement.fromDoc(
      QueryDocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data();
    final ts = m['publishedAt'];
    return Announcement(
      id: d.id,
      title: (m['title'] ?? 'Announcement').toString(),
      body: (m['body'] ?? '').toString(),
      category: (m['category'] ?? 'General').toString(),
      author: (m['author'] ?? 'City Government of Mandaluyong').toString(),
      pinned: m['pinned'] == true,
      // Announcements published before audiences existed carry no field, and
      // are treated as addressed to everyone — which is what they were.
      audience: audienceFromId(m['audience']?.toString()),
      publishedAt: ts is Timestamp ? ts.toDate() : null,
    );
  }

  Color get color => switch (category.toLowerCase()) {
        'emergency' => const Color(0xFFD32F2F),
        'advisory' => const Color(0xFFEF6C00),
        'event' => AppTheme.brandGold,
        _ => AppTheme.brandBlue,
      };

  IconData get icon => switch (category.toLowerCase()) {
        'emergency' => Icons.emergency_rounded,
        'advisory' => Icons.warning_amber_rounded,
        'event' => Icons.event_rounded,
        _ => Icons.campaign_rounded,
      };
}

// ---------------------------------------------------------------------------
// Watcher — notifies the phone when a new announcement is published.
// ---------------------------------------------------------------------------
class AnnouncementService {
  AnnouncementService._();

  /// Scoped to the signed-in account.
  ///
  /// This was one key for the whole phone. Publishing an announcement as staff
  /// marked it seen — for everyone — so signing back in as a resident on the
  /// same handset produced no notification and no unread badge. The
  /// announcement had arrived; the phone had simply already ticked it off on
  /// somebody else's behalf. Exactly how it looks when testing on one device.
  static String _seenKeyFor() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    return uid == null
        ? 'seen_announcement_ids'
        : 'seen_announcement_ids_$uid';
  }

  /// Live stream of the announcements addressed to this person, newest first.
  static Stream<List<Announcement>> stream() => FirebaseFirestore.instance
      .collection(kAnnouncementCollection)
      .orderBy('publishedAt', descending: true)
      .limit(50)
      .snapshots()
      .map((s) => _forMe(s.docs));

  /// Every announcement, whoever it was for. Staff see all of them, because
  /// they are looking at what the office has sent rather than reading their
  /// own notices.
  static Stream<List<Announcement>> streamAll() => FirebaseFirestore.instance
      .collection(kAnnouncementCollection)
      .orderBy('publishedAt', descending: true)
      .limit(50)
      .snapshots()
      .map((s) => s.docs.map(Announcement.fromDoc).toList());

  /// Ids already shown to this user, so nothing notifies twice.
  static Future<Set<String>> _seen() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList(_seenKeyFor()) ?? const <String>[]).toSet();
  }

  static Future<void> _markSeen(Iterable<String> ids) async {
    final prefs = await SharedPreferences.getInstance();
    final key = _seenKeyFor();
    final all = (prefs.getStringList(key) ?? <String>[]).toSet()..addAll(ids);
    await prefs.setStringList(key, all.toList());
  }

  /// Announcements addressed to the signed-in person, newest first.
  ///
  /// Filtered here rather than in the query: Firestore would need a composite
  /// index to combine an audience filter with the ordering, and at this volume
  /// reading fifty and discarding a few is not worth the extra configuration.
  static List<Announcement> _forMe(
      Iterable<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
    final role = UserRoleStore.current;
    return docs
        .map(Announcement.fromDoc)
        .where((a) => a.audience.reaches(role))
        .toList();
  }

  /// How many announcements meant for this user they haven't opened yet.
  static Future<int> unreadCount() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection(kAnnouncementCollection)
          .orderBy('publishedAt', descending: true)
          .limit(50)
          .get();
      final seen = await _seen();
      return _forMe(snap.docs).where((a) => !seen.contains(a.id)).length;
    } catch (_) {
      return 0;
    }
  }

  /// Checks for announcements published since the last check and raises a
  /// phone notification for each new one. Call at app start.
  static Future<void> checkForNew() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection(kAnnouncementCollection)
          .orderBy('publishedAt', descending: true)
          .limit(10)
          .get();
      if (snap.docs.isEmpty) return;

      // Only what was addressed to this person.
      final mine = _forMe(snap.docs);
      if (mine.isEmpty) return;

      final seen = await _seen();
      var fresh = mine.where((a) => !seen.contains(a.id)).toList();

      // First run for this account: don't announce a year's backlog. But
      // anything published in the last day is genuinely news to them — and
      // suppressing it outright was why a freshly signed-in resident heard
      // nothing about an announcement sent minutes earlier.
      if (seen.isEmpty) {
        final cutoff = DateTime.now().subtract(const Duration(days: 1));
        final backlog = <String>[];
        final recent = <Announcement>[];
        for (final a in mine) {
          if (a.publishedAt != null && a.publishedAt!.isAfter(cutoff)) {
            recent.add(a);
          } else {
            backlog.add(a.id);
          }
        }
        if (backlog.isNotEmpty) await _markSeen(backlog);
        if (recent.isEmpty) return;
        fresh = recent;
      }

      for (final a in fresh.take(3)) {
        await LocalNotifs.showNow(
          title: a.category.toLowerCase() == 'emergency'
              ? 'City advisory: ${a.title}'
              : a.title,
          body: a.body.length > 120
              ? '${a.body.substring(0, 117)}…'
              : a.body,
        );
      }
      await _markSeen(fresh.map((a) => a.id));
    } catch (_) {
      // Offline or rules issue — announcements simply don't notify.
    }
  }

  static Future<void> markAllSeen(List<Announcement> items) =>
      _markSeen(items.map((a) => a.id));
}

// ---------------------------------------------------------------------------
// Page: Office of the City Mayor + live announcements
// ---------------------------------------------------------------------------
class AnnouncementsPage extends StatefulWidget {
  const AnnouncementsPage({super.key});

  @override
  State<AnnouncementsPage> createState() => _AnnouncementsPageState();
}

class _AnnouncementsPageState extends State<AnnouncementsPage> {
  Future<void> _open(String url) async {
    try {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open the link.')),
        );
      }
    }
  }

  String _ago(DateTime? d) {
    if (d == null) return '';
    final diff = DateTime.now().difference(d);
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${d.day}/${d.month}/${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('City Announcements')),
      body: StreamBuilder<List<Announcement>>(
        // Staff see everything the office has sent, whoever it was for —
        // they are reviewing what went out, not reading their own notices.
        // Everyone else sees only what was addressed to them.
        stream: StaffAccess.isStaff
            ? AnnouncementService.streamAll()
            : AnnouncementService.stream(),
        builder: (context, snap) {
          final items = snap.data ?? [];
          if (items.isNotEmpty) {
            AnnouncementService.markAllSeen(items);
          }
          // Pinned announcements first.
          items.sort((a, b) {
            if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
            return 0;
          });

          return ListView(
            padding: const EdgeInsets.all(AppSpacing.l),
            children: [
              // ---- Office of the City Mayor ----
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
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          CircleAvatar(
                            radius: 26,
                            backgroundColor:
                                Colors.white.withValues(alpha: 0.18),
                            child: const Icon(Icons.account_balance_rounded,
                                color: Colors.white),
                          ),
                          const SizedBox(width: AppSpacing.m),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Office of the City Mayor',
                                    style: text.labelMedium?.copyWith(
                                      color: Colors.white
                                          .withValues(alpha: 0.85),
                                    )),
                                const SizedBox(height: 2),
                                Text(kMayorName,
                                    style: text.titleMedium?.copyWith(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w700,
                                    )),
                                Text(kMayorTitle,
                                    style: text.bodySmall?.copyWith(
                                      color: Colors.white
                                          .withValues(alpha: 0.8),
                                    )),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.m),
                      Container(
                        width: 44,
                        height: 3,
                        decoration: BoxDecoration(
                          color: AppTheme.brandGold,
                          borderRadius: BorderRadius.circular(99),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.l),
                      Row(
                        children: [
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: () => _open(kMayorFbPage),
                              style: FilledButton.styleFrom(
                                backgroundColor: const Color(0xFF1877F2),
                                foregroundColor: Colors.white,
                              ),
                              icon: const Icon(Icons.facebook, size: 20),
                              label: const Text('Facebook'),
                            ),
                          ),
                          const SizedBox(width: AppSpacing.m),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () => _open(kCityHallSite),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.white,
                                side: BorderSide(
                                    color: Colors.white
                                        .withValues(alpha: 0.55)),
                              ),
                              icon: const Icon(Icons.language, size: 20),
                              label: const Text('City site'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.xl),

              Reveal(
                delayMs: 80,
                child: Row(
                  children: [
                    const Icon(Icons.campaign_rounded, size: 20),
                    const SizedBox(width: AppSpacing.s),
                    Text('Official announcements',
                        style: text.titleMedium),
                  ],
                ),
              ),
              const SizedBox(height: 4),
              Reveal(
                delayMs: 110,
                child: Text(
                  'Published by the city government. You\'ll get a '
                  'notification whenever a new one is posted.',
                  style: text.bodySmall?.copyWith(color: colors.onSurfaceVariant),
                ),
              ),
              const SizedBox(height: AppSpacing.m),

              if (snap.connectionState == ConnectionState.waiting)
                const Padding(
                  padding: EdgeInsets.all(AppSpacing.xxl),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (snap.hasError)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.l),
                    child: Row(
                      children: [
                        Icon(Icons.cloud_off, color: colors.outline),
                        const SizedBox(width: AppSpacing.m),
                        const Expanded(
                          child: Text(
                              'Could not load announcements. Check your '
                              'internet connection.'),
                        ),
                      ],
                    ),
                  ),
                )
              else if (items.isEmpty)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.xl),
                    child: Column(
                      children: [
                        Icon(Icons.notifications_none_rounded,
                            size: 44, color: colors.outline),
                        const SizedBox(height: AppSpacing.m),
                        Text('No announcements yet',
                            style: text.titleSmall),
                        const SizedBox(height: 4),
                        Text(
                          'New advisories and updates from the city will '
                          'appear here.',
                          textAlign: TextAlign.center,
                          style: text.bodySmall
                              ?.copyWith(color: colors.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                )
              else
                for (int i = 0; i < items.length; i++)
                  Reveal(
                    delayMs: 140 + i * 60,
                    child: Card(
                      margin: const EdgeInsets.only(bottom: AppSpacing.m),
                      child: Padding(
                        padding: const EdgeInsets.all(AppSpacing.l),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: items[i]
                                        .color
                                        .withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(99),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(items[i].icon,
                                          size: 13, color: items[i].color),
                                      const SizedBox(width: 5),
                                      Text(items[i].category,
                                          style: TextStyle(
                                            color: items[i].color,
                                            fontWeight: FontWeight.w700,
                                            fontSize: 12,
                                          )),
                                    ],
                                  ),
                                ),
                                if (items[i].pinned) ...[
                                  const SizedBox(width: 6),
                                  Icon(Icons.push_pin,
                                      size: 14, color: colors.outline),
                                ],
                                const Spacer(),
                                Text(_ago(items[i].publishedAt),
                                    style: text.labelSmall
                                        ?.copyWith(color: colors.onSurfaceVariant)),
                              ],
                            ),
                            const SizedBox(height: AppSpacing.s),
                            Text(items[i].title,
                                style: text.titleSmall
                                    ?.copyWith(fontWeight: FontWeight.w700)),
                            const SizedBox(height: 4),
                            Text(items[i].body, style: text.bodyMedium),
                            const SizedBox(height: AppSpacing.s),
                            Text(items[i].author,
                                style: text.labelSmall
                                    ?.copyWith(color: colors.onSurfaceVariant)),
                          ],
                        ),
                      ),
                    ),
                  ),
            ],
          );
        },
      ),
    );
  }
}
