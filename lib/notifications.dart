import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'theme.dart';
import 'heritage.dart'; // TrailProgress, kChurches, HeritageTrailPage
import 'city_content.dart'; // EventsPage
import 'news_page.dart'; // NewsPage
import 'motion.dart'; // Reveal animation
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart'; // whose read list this is
import 'staff_access.dart'; // StaffAccess
import 'event_requests.dart'; // kEventRequestCollection, review page
import 'analytics_dashboard.dart'; // feedback analytics
import 'announcements.dart'; // city announcements in the bell
import 'events_manager.dart'; // newly approved city events
import 'user_role.dart'; // who an announcement is addressed to

// ===========================================================================
// In-app notifications.
// The list is generated from the app's own state (trail progress, plus
// pointers to News and Events). Read/unread is stored on-device, and the
// bell in the app bar shows an unread badge.
// ===========================================================================

/// Where a notification takes the user when tapped.
enum NotifAction {
  none,
  trail,
  events,
  news,
  feedback,
  eventRequests,
  announcements,
}

class AppNotification {
  final String id;
  final String title;
  final String body;
  final IconData icon;
  final NotifAction action;

  const AppNotification({
    required this.id,
    required this.title,
    required this.body,
    required this.icon,
    this.action = NotifAction.none,
  });
}

class NotificationService {
  NotificationService._();

  /// Scoped to the signed-in account.
  ///
  /// One key for the whole phone meant that reading a notification as one
  /// account marked it read for the next person to sign in — the same fault
  /// that hid announcements when they were published from a staff session and
  /// checked from another account on the same handset.
  static String _readKeyFor() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    return uid == null ? 'read_notifications' : 'read_notifications_$uid';
  }

  /// Builds the current notification list from app state.
  /// IDs are stable, except the trail one encodes progress so each new
  /// milestone appears as a fresh (unread) notification.
  static List<AppNotification> build() {
    final visited = TrailProgress.visited.length;
    final total = kChurches.length;

    final list = <AppNotification>[];

    // (The daily weather notification was removed — live weather is already
    // shown on the home dashboard.)

    if (total > 0 && visited >= total) {
      list.add(const AppNotification(
        id: 'trail_done',
        title: 'Heritage Trail complete',
        body: 'You\'ve verified every church. Tap to claim your certificate.',
        icon: Icons.emoji_events_outlined,
        action: NotifAction.trail,
      ));
    } else if (visited > 0) {
      list.add(AppNotification(
        id: 'trail_$visited',
        title: 'Trail progress: $visited of $total churches',
        body: 'Great work! Keep going to finish the Heritage Church Trail.',
        icon: Icons.church_outlined,
        action: NotifAction.trail,
      ));
    }
    // (No "start the trail" prompt — progress notifications appear only once
    // the user has actually verified a church.)

    list.add(const AppNotification(
      id: 'news_intro',
      title: 'Latest Mandaluyong news',
      body: 'Catch up on the newest headlines about the city.',
      icon: Icons.article_outlined,
      action: NotifAction.news,
    ));
    list.add(const AppNotification(
      id: 'events_intro',
      title: 'City events & festivals',
      body: 'Browse the 2026 calendar of activities and see what\'s coming up.',
      icon: Icons.event_outlined,
      action: NotifAction.events,
    ));
    // (Newly approved events are added by buildFor, which can read them.)

    return list;
  }

  /// The staff notification feed: visitor feedback (with its rating, from
  /// both Tourists and Mandaleños) and event requests from residents.
  static Future<List<AppNotification>> buildForStaff() async {
    final list = <AppNotification>[];
    final db = FirebaseFirestore.instance;

    try {
      // ---- Event requests awaiting review ----
      final reqs = await db
          .collection(kEventRequestCollection)
          .where('status', isEqualTo: 'pending')
          .get();
      for (final d in reqs.docs) {
        final m = d.data();
        list.add(AppNotification(
          id: 'req_${d.id}',
          title: 'Event request: ${m['title'] ?? 'Untitled'}',
          body: '${m['requestedByName'] ?? 'A resident'} proposed this '
              'activity. Tap to review it.',
          icon: Icons.inbox_outlined,
          action: NotifAction.eventRequests,
        ));
      }

      // ---- Recent visitor feedback with ratings ----
      final fb = await db
          .collection('feedback')
          .orderBy('createdAt', descending: true)
          .limit(25)
          .get();
      for (final d in fb.docs) {
        final m = d.data();
        final rating = (m['rating'] as num?)?.toInt() ?? 0;
        final userType = (m['userType'] ?? '').toString();
        final sentiment = (m['sentiment'] ?? '').toString();
        final subject = (m['subject'] ?? '').toString();
        list.add(AppNotification(
          id: 'fb_${d.id}',
          title: 'Rating $rating of 5 · '
              '${userType.isEmpty ? 'Visitor' : userType}'
              '${sentiment.isEmpty ? '' : ' · $sentiment'}',
          body: [
            if (subject.isNotEmpty) subject,
            (m['message'] ?? '').toString(),
          ].where((s) => s.isNotEmpty).join(' — '),
          icon: sentiment == 'negative'
              ? Icons.sentiment_dissatisfied_outlined
              : (sentiment == 'positive'
                  ? Icons.sentiment_satisfied_alt_outlined
                  : Icons.rate_review_outlined),
          action: NotifAction.feedback,
        ));
      }
    } catch (_) {
      // Offline or permissions — show an empty feed rather than an error.
    }
    return list;
  }

  /// City announcements addressed to the signed-in person, newest first.
  ///
  /// These arrive as a phone notification when the app opens, but that is a
  /// moment that passes — someone who misses it, or reads it hours later, has
  /// nowhere to look. The bell is that place, for visitors and residents
  /// alike; which of them actually sees a given notice is decided by the
  /// audience the officer chose when publishing it.
  static Future<List<AppNotification>> _announcements() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection(kAnnouncementCollection)
          .orderBy('publishedAt', descending: true)
          .limit(20)
          .get();

      final role = UserRoleStore.current;
      return snap.docs
          .map(Announcement.fromDoc)
          .where((a) => a.audience.reaches(role))
          .take(5)
          .map((a) => AppNotification(
                // Stable, and tied to the document — so marking one read does
                // not mark the next one read too.
                id: 'ann_${a.id}',
                title: a.category.toLowerCase() == 'emergency'
                    ? 'City advisory: ${a.title}'
                    : a.title,
                body: a.body.length > 140
                    ? '${a.body.substring(0, 137)}…'
                    : a.body,
                icon: Icons.campaign_outlined,
                action: NotifAction.announcements,
              ))
          .toList();
    } catch (_) {
      // Offline or rules — the rest of the feed still works.
      return const [];
    }
  }

  /// City events approved since this person last looked.
  ///
  /// Reads whatever [EventsService.checkForNewlyApproved] found — that call
  /// also raises the phone notification, so the bell and the notification are
  /// always about the same events rather than drifting apart.
  static Future<List<AppNotification>> _newEvents() async {
    final fresh = await EventsService.checkForNewlyApproved();
    return fresh
        .take(3)
        .map((e) => AppNotification(
              id: 'event_${e.id}',
              title: 'New city event: ${e.title}',
              body: e.venue.isEmpty
                  ? e.dateLabel
                  : '${e.dateLabel} · ${e.venue}',
              icon: Icons.event_available_outlined,
              action: NotifAction.events,
            ))
        .toList();
  }

  /// The right feed for whoever is signed in, minus anything cleared away.
  static Future<List<AppNotification>> buildFor() async {
    final items = StaffAccess.isStaff
        ? await buildForStaff()
        // Announcements lead — a notice from the city outranks anything the
        // app generated about itself — then newly approved events, then the
        // standing entries.
        : [
            ...await _announcements(),
            ...await _newEvents(),
            ...build(),
          ];

    final gone = await dismissedIds();
    return items.where((n) => !gone.contains(n.id)).toList();
  }

  /// Notifications this person has cleared away.
  ///
  /// The feed is derived from current state rather than stored, so a deleted
  /// notification would otherwise be rebuilt on the next open. Remembering the
  /// ids is what makes "delete" mean anything. Scoped per account, like
  /// everything else about a person.
  static String _dismissedKeyFor() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    return uid == null
        ? 'dismissed_notifications'
        : 'dismissed_notifications_$uid';
  }

  static Future<Set<String>> dismissedIds() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList(_dismissedKeyFor()) ?? const <String>[])
        .toSet();
  }

  /// Removes one notification from the feed for good.
  static Future<void> dismiss(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final key = _dismissedKeyFor();
    final ids = (prefs.getStringList(key) ?? <String>[]).toSet()..add(id);
    await prefs.setStringList(key, ids.toList());
  }

  /// Puts one back, for an undo.
  static Future<void> restore(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final key = _dismissedKeyFor();
    final ids = (prefs.getStringList(key) ?? <String>[]).toSet()..remove(id);
    await prefs.setStringList(key, ids.toList());
  }

  /// Clears the whole feed.
  static Future<void> dismissAll(Iterable<String> ids) async {
    final prefs = await SharedPreferences.getInstance();
    final key = _dismissedKeyFor();
    final all = (prefs.getStringList(key) ?? <String>[]).toSet()..addAll(ids);
    await prefs.setStringList(key, all.toList());
  }

  static Future<Set<String>> readIds() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList(_readKeyFor()) ?? const <String>[]).toSet();
  }

  static Future<int> unreadCount() async {
    final read = await readIds();
    final items = await buildFor();
    return items.where((n) => !read.contains(n.id)).length;
  }

  static Future<void> markRead(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final ids = (prefs.getStringList(_readKeyFor()) ?? <String>[]).toSet()..add(id);
    await prefs.setStringList(_readKeyFor(), ids.toList());
  }

  static Future<void> markAllRead() async {
    final prefs = await SharedPreferences.getInstance();
    final items = await buildFor();
    final ids = (prefs.getStringList(_readKeyFor()) ?? <String>[]).toSet()
      ..addAll(items.map((n) => n.id));
    await prefs.setStringList(_readKeyFor(), ids.toList());
  }
}

class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key});

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  List<AppNotification> _items = const [];
  Set<String> _read = const {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final items = await NotificationService.buildFor();
    final read = await NotificationService.readIds();
    if (!mounted) return;
    setState(() {
      _items = items;
      _read = read;
      _loading = false;
    });
  }

  Future<void> _markAllRead() async {
    await NotificationService.markAllRead();
    await _load();
  }

  Future<void> _markRead(AppNotification n) async {
    await NotificationService.markRead(n.id);
    await _load();
  }

  /// Removes one, with a way back.
  ///
  /// Offered as an undo rather than a confirmation dialog: deleting a
  /// notification is not consequential enough to interrupt someone for, but it
  /// is easy to do by accident on a list you are swiping through.
  Future<void> _delete(AppNotification n) async {
    await NotificationService.dismiss(n.id);
    await _load();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Notification removed'),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () async {
            await NotificationService.restore(n.id);
            await _load();
          },
        ),
      ),
    );
  }

  Future<void> _clearAll() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear all notifications?'),
        content: const Text(
          'They will be removed from this list. City announcements can still '
          'be read any time from Announcements.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Clear all'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await NotificationService.dismissAll(_items.map((n) => n.id));
    await _load();
  }

  Future<void> _open(AppNotification n) async {
    await NotificationService.markRead(n.id);
    if (!mounted) return;

    final Widget? page = switch (n.action) {
      NotifAction.trail => const HeritageTrailPage(),
      NotifAction.events => const EventsPage(),
      NotifAction.news => const NewsPage(),
      NotifAction.feedback => const AnalyticsDashboardPage(),
      NotifAction.eventRequests => const EventRequestsReviewPage(),
      NotifAction.announcements => const AnnouncementsPage(),
      NotifAction.none => null,
    };

    if (page != null) {
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => page),
      );
    }
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final unread = _items.where((n) => !_read.contains(n.id)).length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          if (unread > 0)
            TextButton(
              onPressed: _markAllRead,
              child: const Text('Mark all read'),
            ),
          if (_items.isNotEmpty)
            PopupMenuButton<String>(
              tooltip: 'More',
              onSelected: (v) {
                if (v == 'clear') _clearAll();
              },
              itemBuilder: (context) => const [
                PopupMenuItem(
                  value: 'clear',
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.delete_sweep_outlined),
                    title: Text('Clear all'),
                  ),
                ),
              ],
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _items.isEmpty
              ? _empty(context)
              : ListView.separated(
                  padding: const EdgeInsets.all(AppSpacing.l),
                  itemCount: _items.length,
                  separatorBuilder: (_, _) =>
                      const SizedBox(height: AppSpacing.m),
                  itemBuilder: (context, i) {
                    final n = _items[i];
                    final isUnread = !_read.contains(n.id);
                    // Swipe to remove, with the same undo the menu offers.
                    return Dismissible(
                      key: ValueKey(n.id),
                      direction: DismissDirection.endToStart,
                      background: Container(
                        alignment: Alignment.centerRight,
                        padding:
                            const EdgeInsets.only(right: AppSpacing.xl),
                        decoration: BoxDecoration(
                          color: AppTheme.cityRed.withValues(alpha: 0.12),
                          borderRadius:
                              BorderRadius.circular(AppRadius.lg),
                        ),
                        child: const Icon(Icons.delete_outline,
                            color: AppTheme.cityRed),
                      ),
                      onDismissed: (_) => _delete(n),
                      child: Reveal(
                        delayMs: 50 + i * 70,
                        child: _NotificationCard(
                          notification: n,
                          unread: isUnread,
                          onTap: () => _open(n),
                          onMarkRead: isUnread ? () => _markRead(n) : null,
                          onDelete: () => _delete(n),
                        ),
                      ),
                    );
                  },
                ),
    );
  }

  Widget _empty(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.xxl),
      children: [
        const SizedBox(height: AppSpacing.xxl),
        Icon(Icons.notifications_none_rounded, size: 56, color: colors.outline),
        const SizedBox(height: AppSpacing.l),
        Text('Nothing new',
            textAlign: TextAlign.center, style: text.titleMedium),
        const SizedBox(height: AppSpacing.s),
        Text(
          'City announcements and updates will appear here.',
          textAlign: TextAlign.center,
          style: text.bodySmall?.copyWith(color: colors.onSurfaceVariant),
        ),
      ],
    );
  }
}

class _NotificationCard extends StatelessWidget {
  const _NotificationCard({
    required this.notification,
    required this.unread,
    required this.onTap,
    this.onMarkRead,
    this.onDelete,
  });

  final AppNotification notification;
  final bool unread;
  final VoidCallback onTap;

  /// Null once it has been read — there is nothing left to mark.
  final VoidCallback? onMarkRead;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Card(
      color: unread
          ? colors.primaryContainer.withValues(alpha: 0.35)
          : colors.surfaceContainerHigh,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.l),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: colors.primaryContainer,
                child: Icon(notification.icon,
                    color: colors.onPrimaryContainer),
              ),
              const SizedBox(width: AppSpacing.l),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      notification.title,
                      style: text.titleSmall?.copyWith(
                        fontWeight: unread ? FontWeight.w800 : FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      notification.body,
                      style: text.bodyMedium?.copyWith(color: colors.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              if (unread) ...[
                const SizedBox(width: AppSpacing.s),
                Container(
                  margin: const EdgeInsets.only(top: 6),
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: colors.primary,
                    shape: BoxShape.circle,
                  ),
                ),
              ],
              // The same two actions the swipe offers, for anyone who does not
              // know to swipe — which on a civic app is most people.
              if (onMarkRead != null || onDelete != null)
                PopupMenuButton<String>(
                  tooltip: 'Options',
                  icon: Icon(Icons.more_vert, size: 20, color: colors.outline),
                  onSelected: (v) {
                    if (v == 'read') onMarkRead?.call();
                    if (v == 'delete') onDelete?.call();
                  },
                  itemBuilder: (context) => [
                    if (onMarkRead != null)
                      const PopupMenuItem(
                        value: 'read',
                        child: ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(Icons.done_all),
                          title: Text('Mark as read'),
                        ),
                      ),
                    if (onDelete != null)
                      const PopupMenuItem(
                        value: 'delete',
                        child: ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(Icons.delete_outline),
                          title: Text('Delete'),
                        ),
                      ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}
