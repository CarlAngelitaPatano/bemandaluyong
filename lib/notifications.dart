import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'theme.dart';
import 'heritage.dart'; // TrailProgress, kChurches, HeritageTrailPage
import 'city_content.dart'; // EventsPage
import 'news_page.dart'; // NewsPage
import 'weather.dart'; // WeatherService (weather notification)

// ===========================================================================
// In-app notifications.
// The list is generated from the app's own state (trail progress, plus
// pointers to News and Events). Read/unread is stored on-device, and the
// bell in the app bar shows an unread badge.
// ===========================================================================

/// Where a notification takes the user when tapped.
enum NotifAction { none, trail, events, news }

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

  static const String _readKey = 'read_notifications';

  /// Builds the current notification list from app state.
  /// IDs are stable, except the trail one encodes progress so each new
  /// milestone appears as a fresh (unread) notification.
  static List<AppNotification> build() {
    final visited = TrailProgress.visited.length;
    final total = kChurches.length;

    final list = <AppNotification>[];

    // Today's weather (if fetched) — advice adapts to the conditions.
    final w = WeatherService.last;
    if (w != null) {
      final now = DateTime.now();
      final day = '${now.year}${now.month}${now.day}';
      final rainy = const [51, 53, 55, 61, 63, 65, 66, 67, 80, 81, 82, 95, 96, 99]
          .contains(w.code);
      list.add(AppNotification(
        id: 'weather_$day',
        title: 'Today in Mandaluyong: ${w.tempC.round()}°C · ${w.label}',
        body: rainy
            ? 'Rain expected — bring an umbrella if you\'re walking the '
                'Heritage Trail today. ☔'
            : 'Looks like a good day to explore the city and the Heritage '
                'Trail! 🌤️',
        icon: w.icon,
      ));
    }

    if (total > 0 && visited >= total) {
      list.add(const AppNotification(
        id: 'trail_done',
        title: 'Heritage Trail complete! 🎉',
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
    } else {
      list.add(const AppNotification(
        id: 'trail_start',
        title: 'Start the Heritage Church Trail',
        body: 'Visit Mandaluyong\'s historic churches and earn a certificate.',
        icon: Icons.map_outlined,
        action: NotifAction.trail,
      ));
    }

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
    list.add(const AppNotification(
      id: 'welcome',
      title: 'Welcome to Be@Mandaluyong',
      body: 'Explore the heritage, news, services, and attractions of the city.',
      icon: Icons.celebration_outlined,
    ));

    return list;
  }

  static Future<Set<String>> readIds() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList(_readKey) ?? const <String>[]).toSet();
  }

  static Future<int> unreadCount() async {
    final read = await readIds();
    return build().where((n) => !read.contains(n.id)).length;
  }

  static Future<void> markRead(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final ids = (prefs.getStringList(_readKey) ?? <String>[]).toSet()..add(id);
    await prefs.setStringList(_readKey, ids.toList());
  }

  static Future<void> markAllRead() async {
    final prefs = await SharedPreferences.getInstance();
    final ids = (prefs.getStringList(_readKey) ?? <String>[]).toSet()
      ..addAll(build().map((n) => n.id));
    await prefs.setStringList(_readKey, ids.toList());
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
    await WeatherService.ensureLoaded(); // so the weather notif can appear
    final read = await NotificationService.readIds();
    if (!mounted) return;
    setState(() {
      _items = NotificationService.build();
      _read = read;
      _loading = false;
    });
  }

  Future<void> _markAllRead() async {
    await NotificationService.markAllRead();
    await _load();
  }

  Future<void> _open(AppNotification n) async {
    await NotificationService.markRead(n.id);
    if (!mounted) return;

    final Widget? page = switch (n.action) {
      NotifAction.trail => const HeritageTrailPage(),
      NotifAction.events => const EventsPage(),
      NotifAction.news => const NewsPage(),
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
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView.separated(
              padding: const EdgeInsets.all(AppSpacing.l),
              itemCount: _items.length,
              separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.m),
              itemBuilder: (context, i) {
                final n = _items[i];
                final isUnread = !_read.contains(n.id);
                return _NotificationCard(
                  notification: n,
                  unread: isUnread,
                  onTap: () => _open(n),
                );
              },
            ),
    );
  }
}

class _NotificationCard extends StatelessWidget {
  const _NotificationCard({
    required this.notification,
    required this.unread,
    required this.onTap,
  });

  final AppNotification notification;
  final bool unread;
  final VoidCallback onTap;

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
                      style: text.bodyMedium?.copyWith(color: colors.outline),
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
            ],
          ),
        ),
      ),
    );
  }
}
