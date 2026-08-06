import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'theme.dart';
import 'motion.dart';
import 'local_notifs.dart';

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

class Announcement {
  final String id;
  final String title;
  final String body;
  final String category;
  final String author;
  final bool pinned;
  final DateTime? publishedAt;

  const Announcement({
    required this.id,
    required this.title,
    required this.body,
    required this.category,
    required this.author,
    required this.pinned,
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

  static const String _seenKey = 'seen_announcement_ids';

  /// Live stream of announcements, newest first.
  static Stream<List<Announcement>> stream() => FirebaseFirestore.instance
      .collection(kAnnouncementCollection)
      .orderBy('publishedAt', descending: true)
      .limit(50)
      .snapshots()
      .map((s) => s.docs.map(Announcement.fromDoc).toList());

  /// Ids already shown to this user, so nothing notifies twice.
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

  /// How many announcements this user hasn't opened yet.
  static Future<int> unreadCount() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection(kAnnouncementCollection)
          .orderBy('publishedAt', descending: true)
          .limit(50)
          .get();
      final seen = await _seen();
      return snap.docs.where((d) => !seen.contains(d.id)).length;
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

      final seen = await _seen();
      final fresh = snap.docs.where((d) => !seen.contains(d.id)).toList();

      // First run: don't spam the user with a backlog — just remember them.
      if (seen.isEmpty) {
        await _markSeen(snap.docs.map((d) => d.id));
        return;
      }

      for (final d in fresh.take(3)) {
        final a = Announcement.fromDoc(d);
        await LocalNotifs.showNow(
          title: a.category.toLowerCase() == 'emergency'
              ? 'City advisory: ${a.title}'
              : a.title,
          body: a.body.length > 120
              ? '${a.body.substring(0, 117)}…'
              : a.body,
        );
      }
      await _markSeen(fresh.map((d) => d.id));
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
        stream: AnnouncementService.stream(),
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
                  style: text.bodySmall?.copyWith(color: colors.outline),
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
                              ?.copyWith(color: colors.outline),
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
                                        ?.copyWith(color: colors.outline)),
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
                                    ?.copyWith(color: colors.outline)),
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
