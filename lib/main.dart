import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'firebase_options.dart';
import 'report_concern_page.dart';
import 'auth_pages.dart';
import 'theme.dart';
import 'heritage.dart';
import 'city_content.dart';
import 'news_page.dart';
import 'attractions.dart';
import 'profile_page.dart';
import 'notifications.dart';
import 'ar_view.dart';
import 'theme_controller.dart';
import 'trail_map.dart';
import 'onboarding.dart';
import 'search.dart';
import 'dining.dart';
import 'weather.dart';
import 'local_notifs.dart';
import 'avatars.dart'; // built-in avatar option

void main() async {
  // Required before any async work in main().
  WidgetsFlutterBinding.ensureInitialized();
  // Connect to Firebase using the generated config.
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  // Restore saved Heritage Church Trail progress.
  await TrailProgress.load();
  // Restore the saved light/dark theme choice.
  await ThemeController.instance.load();
  // Set up the daily 7 AM reminder notification (asks permission once).
  await LocalNotifs.setup();

  // Show the intro only on first launch.
  final seenOnboarding = await Onboarding.seen();

  // "Remember me": decide whether to skip login on this launch.
  final prefs = await SharedPreferences.getInstance();
  final remember = prefs.getBool('remember_me') ?? false;
  final user = FirebaseAuth.instance.currentUser;
  if (user != null && !remember) {
    // Not remembered — force a fresh login next time.
    await FirebaseAuth.instance.signOut();
  }
  final isDemo = user?.email?.toLowerCase() == kDemoEmail;
  final autoLogin = remember &&
      user != null &&
      (user.emailVerified ||
          isDemo ||
          user.phoneNumber != null ||
          user.providerData.any((p) => p.providerId == 'google.com'));

  runApp(BeMandaluyongApp(
    showOnboarding: !seenOnboarding,
    startLoggedIn: autoLogin,
  ));
}

/// Root of the app. Sets up the theme and the home screen.
class BeMandaluyongApp extends StatelessWidget {
  const BeMandaluyongApp({
    super.key,
    this.showOnboarding = false,
    this.startLoggedIn = false,
  });

  final bool showOnboarding;
  final bool startLoggedIn;

  @override
  Widget build(BuildContext context) {
    // Rebuilds the app when the user changes the theme in Profile > Settings.
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: ThemeController.instance.mode,
      builder: (context, mode, _) => MaterialApp(
        title: 'Be@Mandaluyong',
        debugShowCheckedModeBanner: false, // hides the "DEBUG" ribbon
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode: mode, // Light / Dark / Follow system
        home: showOnboarding
            ? const OnboardingPage()
            : (startLoggedIn ? const HomeShell() : const RoleSelectPage()),
      ),
    );
  }
}

/// Holds the bottom navigation bar and swaps the body between tabs.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _selectedIndex = 0;
  Uint8List? _avatarBytes; // current user's profile photo for the app bar
  String? _presetId; // built-in avatar id, if the user chose one
  int _unread = 0; // unread notification count for the bell badge

  // One widget per bottom-nav tab.
  static const List<Widget> _pages = <Widget>[
    HomePage(),
    HeritageChurchesView(),
    ProfilePage(),
  ];

  @override
  void initState() {
    super.initState();
    // Demo account: keep the whole trail unlocked (also covers app restarts
    // where the demo session is still signed in). Real accounts reload their
    // actual saved progress, clearing any leftover demo unlock.
    if (FirebaseAuth.instance.currentUser?.email?.toLowerCase() == kDemoEmail) {
      TrailProgress.unlockAll();
    } else {
      TrailProgress.load().then((_) {
        if (mounted) setState(() {});
      });
    }
    _loadAvatar();
    _loadUnread();
  }

  Future<void> _loadAvatar() async {
    final bytes = await ProfileAvatarStore.load();
    final preset = await ProfileAvatarStore.loadPreset();
    if (mounted) {
      setState(() {
        _avatarBytes = bytes;
        _presetId = preset;
      });
    }
  }

  Future<void> _loadUnread() async {
    final count = await NotificationService.unreadCount();
    if (mounted) setState(() => _unread = count);
  }

  void _onTab(int index) {
    setState(() => _selectedIndex = index);
    _loadAvatar(); // refresh the photo in case it changed on the Profile tab
    _loadUnread(); // trail progress can add new notifications
  }

  Future<void> _openNotifications() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const NotificationsPage()),
    );
    _loadUnread();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final name = FirebaseAuth.instance.currentUser?.displayName?.trim();
    final initial =
        (name != null && name.isNotEmpty) ? name[0].toUpperCase() : 'R';

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        centerTitle: true,
        leadingWidth: 60,
        leading: Center(
          child: GestureDetector(
            onTap: () => _onTab(2), // jump to the Profile tab
            child: Container(
              margin: const EdgeInsets.only(left: 12),
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: colors.primary.withValues(alpha: 0.25),
                  width: 2,
                ),
              ),
              child: (_avatarBytes == null && presetAvatarById(_presetId) != null)
                  ? PresetAvatarCircle(
                      avatar: presetAvatarById(_presetId)!, radius: 18)
                  : CircleAvatar(
                      radius: 18,
                      backgroundColor: colors.primaryContainer,
                      backgroundImage: _avatarBytes != null
                          ? MemoryImage(_avatarBytes!)
                          : null,
                      child: _avatarBytes == null
                          ? Text(
                              initial,
                              style: TextStyle(
                                color: colors.onPrimaryContainer,
                                fontWeight: FontWeight.bold,
                              ),
                            )
                          : null,
                    ),
            ),
          ),
        ),
        title: const Text('Be@Mandaluyong'),
        actions: [
          IconButton(
            tooltip: 'Search',
            icon: const Icon(Icons.search),
            onPressed: () =>
                showSearch(context: context, delegate: AppSearchDelegate()),
          ),
          IconButton(
            tooltip: 'Notifications',
            icon: Badge(
              isLabelVisible: _unread > 0,
              label: Text('$_unread'),
              child: const Icon(Icons.notifications_outlined),
            ),
            onPressed: _openNotifications,
          ),
        ],
      ),
      body: _pages[_selectedIndex],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: _onTab,
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Home'),
          NavigationDestination(icon: Icon(Icons.explore_outlined), selectedIcon: Icon(Icons.explore), label: 'Explore'),
          NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: 'Profile'),
        ],
      ),
    );
  }
}

/// The Home tab: a welcome banner plus a grid of feature cards.
class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final displayName = FirebaseAuth.instance.currentUser?.displayName;
    final firstName = (displayName != null && displayName.trim().isNotEmpty)
        ? displayName.trim().split(' ').first
        : null;
    final hour = DateTime.now().hour;
    final greeting = hour < 12
        ? 'Good morning'
        : (hour < 18 ? 'Good afternoon' : 'Good evening');

    // Home feature cards, grouped into two sections. Each feature has its own
    // color identity (gradient) for a modern, professional look.
    final explore = <_Feature>[
      _Feature('Map', Icons.map_rounded,
          color: const Color(0xFF1E88E5), // blue
          page: (_) => const TrailMapPage()),
      _Feature('Attractions', Icons.photo_camera_rounded,
          color: const Color(0xFFF4511E), // deep orange
          page: (_) => const AttractionsPage()),
      _Feature('Homegrown', Icons.storefront_rounded,
          color: const Color(0xFF8E24AA), // purple
          page: (_) => const DiningPage()),
      _Feature('3D / AR', Icons.view_in_ar_rounded,
          color: const Color(0xFF00897B), // teal
          page: (_) => const ArIntroPage()),
    ];
    final cityServices = <_Feature>[
      _Feature('News', Icons.newspaper_rounded,
          color: const Color(0xFF3949AB), // indigo
          page: (_) => const NewsPage()),
      _Feature('Events', Icons.event_rounded,
          color: const Color(0xFFE53935), // red
          page: (_) => const EventsPage()),
      _Feature('Services', Icons.widgets_rounded,
          color: const Color(0xFF43A047), // green
          page: (_) => const ServicesPage()),
      _Feature('Contact', Icons.support_agent_rounded,
          color: const Color(0xFFFB8C00), // amber-orange
          page: (_) => const ReportConcernPage()),
    ];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.l),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Welcome banner
          Container(
            padding: const EdgeInsets.all(AppSpacing.xxl),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [colors.primary, colors.primaryContainer],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(AppRadius.xl),
              // Soft glow lifts the banner off the background.
              boxShadow: [
                BoxShadow(
                  color: colors.primary.withValues(alpha: 0.35),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        firstName == null ? greeting : '$greeting, $firstName',
                        style: text.titleMedium?.copyWith(
                          color: colors.onPrimary.withValues(alpha: 0.95),
                        ),
                      ),
                    ),
                    const WeatherChip(),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'Be@Mandaluyong',
                  style: text.headlineSmall?.copyWith(color: colors.onPrimary),
                ),
                const SizedBox(height: 6),
                Text(
                  'Explore the heritage, culture, and services of '
                  'Mandaluyong City.',
                  style: text.bodyMedium?.copyWith(
                    color: colors.onPrimary.withValues(alpha: 0.9),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          const _Reveal(delayMs: 60, child: _TrailProgressCard()),
          const SizedBox(height: AppSpacing.xxl),
          _Reveal(
              delayMs: 160,
              child: Text('Featured today', style: text.titleMedium)),
          const SizedBox(height: AppSpacing.m),
          const _Reveal(delayMs: 200, child: _FeaturedTodayCard()),
          const SizedBox(height: AppSpacing.xxl),
          _Reveal(
              delayMs: 280,
              child: Text('Explore Mandaluyong', style: text.titleMedium)),
          const SizedBox(height: AppSpacing.m),
          _Reveal(
            delayMs: 320,
            child: GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: AppSpacing.m,
              crossAxisSpacing: AppSpacing.m,
              childAspectRatio: 1.3,
              children: explore.map((f) => _FeatureCard(feature: f)).toList(),
            ),
          ),
          const SizedBox(height: AppSpacing.xxl),
          _Reveal(
              delayMs: 400,
              child: Text('City & services', style: text.titleMedium)),
          const SizedBox(height: AppSpacing.m),
          _Reveal(
            delayMs: 440,
            child: GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: AppSpacing.m,
              crossAxisSpacing: AppSpacing.m,
              childAspectRatio: 1.3,
              children:
                  cityServices.map((f) => _FeatureCard(feature: f)).toList(),
            ),
          ),

          // ---- Heritage Churches section ----
          const SizedBox(height: AppSpacing.xxl),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Heritage Churches', style: text.titleMedium),
              TextButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => Scaffold(
                      appBar: AppBar(title: const Text('Heritage Churches')),
                      body: const HeritageChurchesView(),
                    ),
                  ),
                ),
                child: const Text('See all'),
              ),
            ],
          ),
          const SizedBox(height: 4),
          // Horizontal scroller of featured churches
          SizedBox(
            height: 190,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: kChurches.length,
              separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.m),
              itemBuilder: (_, i) => FeaturedChurchCard(church: kChurches[i]),
            ),
          ),
          const SizedBox(height: AppSpacing.l),
          // Trail button
          FilledButton.icon(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const HeritageTrailPage()),
            ),
            icon: const Icon(Icons.map_outlined),
            label: const Text('View the Heritage Church Trail'),
          ),
        ],
      ),
    );
  }
}

/// Simple data holder for a feature card.
class _Feature {
  final String label;
  final IconData icon;
  final Color color; // the feature's color identity
  final WidgetBuilder? page; // optional screen to open when tapped
  const _Feature(this.label, this.icon,
      {this.color = const Color(0xFF0038A8), this.page});
}

class _FeatureCard extends StatefulWidget {
  const _FeatureCard({required this.feature});
  final _Feature feature;

  @override
  State<_FeatureCard> createState() => _FeatureCardState();
}

class _FeatureCardState extends State<_FeatureCard> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final feature = widget.feature;
    return AnimatedScale(
      scale: _pressed ? 0.94 : 1,
      duration: const Duration(milliseconds: 120),
      curve: Curves.easeOut,
      child: Card(
      elevation: 0,
      color: colors.surfaceContainerHighest,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md)),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.md),
        onHighlightChanged: (v) => setState(() => _pressed = v),
        onTap: () {
          if (feature.page != null) {
            // Open the card's own screen (with an automatic back button).
            Navigator.push(
              context,
              MaterialPageRoute(builder: feature.page!),
            );
          } else {
            // No page yet: just show a quick message.
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('${feature.label} tapped')),
            );
          }
        },
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.l),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Squircle with a soft gradient + glow in the feature's color.
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      feature.color.withValues(alpha: 0.85),
                      feature.color,
                    ],
                  ),
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: [
                    BoxShadow(
                      color: feature.color.withValues(alpha: 0.4),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Icon(feature.icon, size: 28, color: Colors.white),
              ),
              const SizedBox(height: AppSpacing.m),
              Text(
                feature.label,
                style: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      ),
      ),
    );
  }
}

/// A reusable empty page for the other tabs.
class PlaceholderPage extends StatelessWidget {
  const PlaceholderPage({super.key, required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 64, color: colors.primary),
          const SizedBox(height: AppSpacing.l),
          Text('$label page', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: AppSpacing.s),
          Text('Coming soon', style: TextStyle(color: colors.outline)),
        ],
      ),
    );
  }
}

/// Motivational trail-progress card on the home screen. Shows how far the user
/// is on the Heritage Church Trail and nudges them to keep going.
class _TrailProgressCard extends StatefulWidget {
  const _TrailProgressCard();

  @override
  State<_TrailProgressCard> createState() => _TrailProgressCardState();
}

class _TrailProgressCardState extends State<_TrailProgressCard> {
  Future<void> _openTrail() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const HeritageTrailPage()),
    );
    if (mounted) setState(() {}); // refresh progress after returning
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final success = AppTheme.successFor(Theme.of(context).brightness);

    final visited = TrailProgress.visited.length;
    final total = kChurches.length;
    final complete = TrailProgress.isComplete;
    final remaining = total - visited;
    final progress = total == 0 ? 0.0 : visited / total;

    final String title;
    final String subtitle;
    final String button;
    final IconData icon;
    if (complete) {
      title = 'Trail complete! 🎉';
      subtitle = 'You\'ve visited all $total churches. Claim your certificate!';
      button = 'View your certificate';
      icon = Icons.emoji_events;
    } else if (visited > 0) {
      title = 'Keep going!';
      subtitle =
          'You\'ve visited $visited of $total churches — $remaining more to '
          'earn your certificate. 🏆';
      button = 'Continue the trail';
      icon = Icons.church_outlined;
    } else {
      title = 'Start the Heritage Trail';
      subtitle = 'Visit Mandaluyong\'s historic churches, verify each stop, '
          'and earn a certificate of completion.';
      button = 'Start the trail';
      icon = Icons.church_outlined;
    }

    return Container(
      padding: const EdgeInsets.all(AppSpacing.l),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: colors.tertiary.withValues(alpha: 0.55)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(AppSpacing.m),
                decoration: BoxDecoration(
                  color: colors.tertiaryContainer,
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: colors.onTertiaryContainer),
              ),
              const SizedBox(width: AppSpacing.l),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: text.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text(subtitle,
                        style:
                            text.bodySmall?.copyWith(color: colors.outline)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.m),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.sm),
            // Fills up smoothly whenever the card appears.
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: progress),
              duration: const Duration(milliseconds: 900),
              curve: Curves.easeOutCubic,
              builder: (context, v, _) => LinearProgressIndicator(
                value: v,
                minHeight: 10,
                backgroundColor: colors.surfaceContainerHighest,
                color: complete ? success : colors.primary,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text('$visited of $total churches visited',
              style: text.bodySmall?.copyWith(color: colors.outline)),
          const SizedBox(height: AppSpacing.m),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _openTrail,
              icon: Icon(complete ? Icons.workspace_premium : Icons.map_outlined),
              label: Text(button),
            ),
          ),
        ],
      ),
    );
  }
}

/// Fades + slides its child in after [delayMs] — used to cascade the home
/// sections so the dashboard feels alive when it opens.
class _Reveal extends StatefulWidget {
  const _Reveal({required this.delayMs, required this.child});
  final int delayMs;
  final Widget child;

  @override
  State<_Reveal> createState() => _RevealState();
}

class _RevealState extends State<_Reveal> {
  bool _shown = false;

  @override
  void initState() {
    super.initState();
    Future.delayed(Duration(milliseconds: widget.delayMs), () {
      if (mounted) setState(() => _shown = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: _shown ? 1 : 0,
      duration: const Duration(milliseconds: 450),
      curve: Curves.easeOut,
      child: AnimatedSlide(
        offset: _shown ? Offset.zero : const Offset(0, 0.07),
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeOutCubic,
        child: widget.child,
      ),
    );
  }
}

/// A daily-changing "church of the day" spotlight to keep the home fresh.
class _FeaturedTodayCard extends StatelessWidget {
  const _FeaturedTodayCard();

  Widget _fallback(ColorScheme colors) => Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [colors.primary, colors.primaryContainer],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child:
            const Center(child: Icon(Icons.church, color: Colors.white, size: 56)),
      );

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    // Pick a church based on the day of the year (stable within a day).
    final now = DateTime.now();
    final dayOfYear = now.difference(DateTime(now.year, 1, 1)).inDays;
    final church = kChurches[dayOfYear % kChurches.length];

    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => ChurchDetailPage(church: church)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: SizedBox(
          height: 170,
          width: double.infinity,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Cinematic slow zoom-out on load (Ken Burns effect).
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 1.12, end: 1.0),
                duration: const Duration(milliseconds: 1500),
                curve: Curves.easeOutCubic,
                builder: (context, s, child) =>
                    Transform.scale(scale: s, child: child),
                child: church.image != null
                    ? Image.asset(
                        church.image!,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => _fallback(colors),
                      )
                    : _fallback(colors),
              ),
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Colors.black87],
                  ),
                ),
              ),
              Positioned(
                left: AppSpacing.l,
                right: AppSpacing.l,
                bottom: AppSpacing.l,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.m, vertical: 4),
                      decoration: BoxDecoration(
                        color: colors.tertiaryContainer,
                        borderRadius: BorderRadius.circular(AppRadius.pill),
                      ),
                      child: Text('Featured today',
                          style: text.labelMedium
                              ?.copyWith(color: colors.onTertiaryContainer)),
                    ),
                    const SizedBox(height: 8),
                    Text(church.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: text.titleMedium?.copyWith(
                            color: Colors.white, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text(church.era,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: text.bodySmall?.copyWith(
                            color: Colors.white.withValues(alpha: 0.9))),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
