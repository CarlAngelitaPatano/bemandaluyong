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
import 'user_role.dart'; // Tourist / Mandaleño
import 'user_profile.dart'; // date of birth / trail age requirement
import 'emergency.dart'; // emergency hotlines
import 'announcements.dart'; // official city announcements
import 'itinerary.dart'; // suggested itineraries
import 'feedback_page.dart'; // visitor feedback → CCAT sentiment analysis
import 'analytics_dashboard.dart'; // sentiment analytics dashboard
import 'accreditation.dart'; // policy management / accreditation
import 'admin_panel.dart'; // CCAT admin console
import 'staff_panel.dart'; // CCAT staff console
import 'events_manager.dart'; // staff event management
import 'event_requests.dart'; // resident event proposals
import 'sentiment_eval.dart'; // NLP accuracy report
import 'package:cloud_firestore/cloud_firestore.dart';

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

  // Visitors browse the city; CCAT staff manage it. Different tabs entirely.
  static const List<Widget> _visitorPages = <Widget>[
    HomePage(),
    HeritageChurchesView(),
    ServicesGridPage(),
    ProfilePage(),
  ];

  // Full administrators
  static const List<Widget> _adminPages = <Widget>[
    HomePage(), // renders the admin dashboard
    AdminPanelView(),
    AnalyticsDashboardPage(embedded: true),
    ProfilePage(),
  ];

  // Staff tier — events, announcements and feedback
  static const List<Widget> _staffPages = <Widget>[
    HomePage(), // renders the staff dashboard
    EventsManagerPage(embedded: true),
    AnalyticsDashboardPage(embedded: true),
    ProfilePage(),
  ];

  List<Widget> get _pages => switch (StaffAccess.role) {
        CcatRole.admin => _adminPages,
        CcatRole.staff => _staffPages,
        CcatRole.none => _visitorPages,
      };

  @override
  void initState() {
    super.initState();
    // Demo account: keep the whole trail unlocked (also covers app restarts
    // where the demo session is still signed in). Real accounts reload their
    // actual saved progress, clearing any leftover demo unlock.
    if (FirebaseAuth.instance.currentUser?.email?.toLowerCase() == kDemoEmail) {
      TrailProgress.unlockAll(); // also syncs to the shared account
    } else {
      // Load local progress, then merge with the shared account (website).
      TrailProgress.load()
          .then((_) => TrailProgress.syncWithCloud())
          .then((_) {
        if (mounted) setState(() {});
      });
    }
    // Load Tourist / Mandaleño so the dashboard shows the right content.
    UserRoleStore.load().then((role) {
      if (mounted) setState(() {});
      // Official city announcements are a residents' channel, so only
      // Mandaleños (and staff) are notified about new ones.
      if (role == UserRole.mandaleno || StaffAccess.isStaff) {
        AnnouncementService.checkForNew();
      }
    });
    _loadAvatar();
    _loadUnread();
    // Date of birth — drives the Heritage Trail age requirement.
    UserProfileStore.load();
    // Is this account CCAT staff? Changes the whole home screen.
    StaffAccess.check().then((_) {
      if (mounted) setState(() {});
    });
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
            onTap: () => _onTab(3), // jump to the Profile tab
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
        title: Text(switch (StaffAccess.role) {
          CcatRole.admin => 'CCAT Administration',
          CcatRole.staff => 'CCAT Staff',
          CcatRole.none => 'Be@Mandaluyong',
        }),
        actions: [
          // Visitor search isn't useful to staff — they get the accuracy
          // report instead.
          if (StaffAccess.isStaff)
            IconButton(
              tooltip: 'Sentiment model accuracy',
              icon: const Icon(Icons.science_outlined),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SentimentEvalPage()),
              ),
            )
          else
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
        destinations: [
          const NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home),
              label: 'Home'),
          if (StaffAccess.isAdmin) ...[
            const NavigationDestination(
                icon: Icon(Icons.dashboard_outlined),
                selectedIcon: Icon(Icons.dashboard),
                label: 'Manage'),
            const NavigationDestination(
                icon: Icon(Icons.insights_outlined),
                selectedIcon: Icon(Icons.insights),
                label: 'Analytics'),
          ] else if (StaffAccess.isStaffOnly) ...[
            const NavigationDestination(
                icon: Icon(Icons.event_note_outlined),
                selectedIcon: Icon(Icons.event_note),
                label: 'Events'),
            const NavigationDestination(
                icon: Icon(Icons.insights_outlined),
                selectedIcon: Icon(Icons.insights),
                label: 'Feedback'),
          ] else ...[
            const NavigationDestination(
                icon: Icon(Icons.explore_outlined),
                selectedIcon: Icon(Icons.explore),
                label: 'Explore'),
            const NavigationDestination(
                icon: Icon(Icons.grid_view_outlined),
                selectedIcon: Icon(Icons.grid_view_rounded),
                label: 'Services'),
          ],
          const NavigationDestination(
              icon: Icon(Icons.person_outline),
              selectedIcon: Icon(Icons.person),
              label: 'Profile'),
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
    final text = Theme.of(context).textTheme;
    final displayName = FirebaseAuth.instance.currentUser?.displayName;
    final firstName = (displayName != null && displayName.trim().isNotEmpty)
        ? displayName.trim().split(' ').first
        : null;
    final hour = DateTime.now().hour;
    final greeting = hour < 12
        ? 'Good morning'
        : (hour < 18 ? 'Good afternoon' : 'Good evening');

    // CCAT accounts get work-focused dashboards instead of the visitor one.
    if (StaffAccess.isAdmin) return const _AdminHomeView();
    if (StaffAccess.isStaffOnly) return const StaffHomeView();

    // Tourist or Mandaleño — decides the greeting and the "For you" card.
    // (All feature tiles live in the Services tab.)
    final role = UserRoleStore.current;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.l),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ---- Welcome banner: deep navy with a gold signature ----
          Container(
            padding: const EdgeInsets.all(AppSpacing.xl),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF12305F), Color(0xFF1E4B8F)],
              ),
              borderRadius: BorderRadius.circular(AppRadius.xl),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF12305F).withValues(alpha: 0.22),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        // Mandaleños are greeted as locals; tourists by name.
                        role == UserRole.mandaleno
                            ? '$greeting, Mandaleño'
                            : (firstName == null
                                ? greeting
                                : '$greeting, $firstName'),
                        style: text.bodyMedium?.copyWith(
                          color: Colors.white.withValues(alpha: 0.75),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    const WeatherChip(),
                  ],
                ),
                const SizedBox(height: AppSpacing.s),
                // Brand name in the heritage serif.
                Text(
                  'Be@Mandaluyong',
                  style: AppTheme.brandTextStyle(
                    fontSize: 30,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: AppSpacing.m),
                // Gold signature rule — the seal's accent, used once.
                Container(
                  width: 44,
                  height: 3,
                  decoration: BoxDecoration(
                    color: AppTheme.brandGold,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
                const SizedBox(height: AppSpacing.m),
                // A line that changes with the time of day and the role.
                Text(
                  _headline(role, hour),
                  style: text.bodyMedium?.copyWith(
                    color: Colors.white.withValues(alpha: 0.9),
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.l),

          // Slim emergency link — present, but not shouting.
          _Reveal(
            delayMs: 30,
            child: InkWell(
              borderRadius: BorderRadius.circular(AppRadius.md),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const EmergencyPage()),
              ),
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.m, vertical: AppSpacing.s),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  border: Border.all(
                      color: const Color(0xFFD32F2F).withValues(alpha: 0.35)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.emergency_outlined,
                        size: 18, color: Color(0xFFD32F2F)),
                    const SizedBox(width: AppSpacing.s),
                    Expanded(
                      child: Text(
                        'Emergency hotlines',
                        style: text.bodyMedium?.copyWith(
                          color: const Color(0xFFD32F2F),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const Icon(Icons.chevron_right,
                        size: 18, color: Color(0xFFD32F2F)),
                  ],
                ),
              ),
            ),
          ),
          // ---- 1. The app's flagship: trail progress ----
          const SizedBox(height: AppSpacing.xl),
          const _Reveal(delayMs: 60, child: _TrailProgressCard()),

          // ---- 2. For you: two contextual cards under one label ----
          const SizedBox(height: AppSpacing.xxl),
          _Reveal(
              delayMs: 140,
              child: Text('For you', style: _sectionStyle(context))),
          const SizedBox(height: AppSpacing.m),
          const _Reveal(delayMs: 180, child: _FeaturedTodayCard()),
          const SizedBox(height: AppSpacing.m),
          _Reveal(
            delayMs: 220,
            child: role == UserRole.tourist
                ? const _ItinerarySpotlightCard()
                : const _MayorSpotlightCard(),
          ),

          // (All the feature tiles now live in the "Services" tab, keeping
          // this dashboard calm and scannable.)
          const SizedBox(height: AppSpacing.xl),
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
      color: Colors.transparent,
      margin: EdgeInsets.zero,
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
              // One calm accent for every feature — no rainbow.
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: colors.primary.withValues(alpha: 0.08),
                  shape: BoxShape.circle,
                ),
                child: Icon(feature.icon, size: 24, color: colors.primary),
              ),
              const SizedBox(height: AppSpacing.s),
              Text(
                feature.label,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
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
      title = 'Trail complete';
      subtitle = 'You\'ve visited all $total churches. Claim your certificate.';
      button = 'View your certificate';
      icon = Icons.emoji_events;
    } else if (visited > 0) {
      title = 'Keep going';
      subtitle =
          'You\'ve visited $visited of $total churches — $remaining more to '
          'earn your certificate.';
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
                // Gold = progress/achievement in the two-colour system.
                color: AppTheme.brandGold,
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

// ===========================================================================
// Services tab — every feature in one clean, grouped grid. Section order
// follows the user's role (Mandaleños see city services first).
// ===========================================================================
class ServicesGridPage extends StatelessWidget {
  const ServicesGridPage({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    final explore = <_Feature>[
      _Feature('Itineraries', Icons.route_rounded,
          color: const Color(0xFF6D4C41), page: (_) => const ItineraryPage()),
      _Feature('Map', Icons.map_rounded,
          color: const Color(0xFF1E88E5), page: (_) => const TrailMapPage()),
      _Feature('Attractions', Icons.photo_camera_rounded,
          color: const Color(0xFFF4511E),
          page: (_) => const AttractionsPage()),
      _Feature('Homegrown', Icons.storefront_rounded,
          color: const Color(0xFF8E24AA), page: (_) => const DiningPage()),
      _Feature('3D / AR', Icons.view_in_ar_rounded,
          color: const Color(0xFF00897B), page: (_) => const ArIntroPage()),
    ];
    final role = UserRoleStore.current;

    final cityServices = <_Feature>[
      // Official city announcements are aimed at residents, so they are
      // shown to Mandaleños (and staff) rather than visiting tourists.
      if (role == UserRole.mandaleno)
        _Feature('Announcements', Icons.campaign_rounded,
            color: const Color(0xFF00838F),
            page: (_) => const AnnouncementsPage()),
      _Feature('News', Icons.newspaper_rounded,
          color: const Color(0xFF3949AB), page: (_) => const NewsPage()),
      _Feature('Events', Icons.event_rounded,
          color: const Color(0xFFE53935), page: (_) => const EventsPage()),
      _Feature('Services', Icons.widgets_rounded,
          color: const Color(0xFF43A047), page: (_) => const ServicesPage()),
      _Feature('Contact', Icons.support_agent_rounded,
          color: const Color(0xFFFB8C00),
          page: (_) => const ReportConcernPage()),
      _Feature('Feedback', Icons.rate_review_rounded,
          color: const Color(0xFF00838F), page: (_) => const FeedbackPage()),
      // Business accreditation is for local establishment owners, so it is
      // offered to Mandaleños only. (Analytics is a CCAT staff tool and is
      // not shown to visitors at all.)
      if (role == UserRole.mandaleno) ...[
        _Feature('Accreditation', Icons.verified_outlined,
            color: const Color(0xFF00695C),
            page: (_) => const AccreditationPage()),
        _Feature('Request Event', Icons.add_circle_outline,
            color: const Color(0xFF5E35B1),
            page: (_) => const EventRequestPage()),
      ],
    ];

    final first = role == UserRole.mandaleno ? cityServices : explore;
    final second = role == UserRole.mandaleno ? explore : cityServices;
    final firstTitle = role.primarySectionTitle;
    final secondTitle = role.secondarySectionTitle;

    Widget grid(List<_Feature> items, int delay) => _Reveal(
          delayMs: delay,
          child: GridView.count(
            crossAxisCount: 3,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: AppSpacing.s,
            crossAxisSpacing: AppSpacing.s,
            childAspectRatio: 0.95,
            children: items.map((f) => _FeatureCard(feature: f)).toList(),
          ),
        );

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.l),
      children: [
        _Reveal(
          delayMs: 0,
          child: Text('All features',
              style: text.headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w700)),
        ),
        const SizedBox(height: 2),
        _Reveal(
          delayMs: 40,
          child: Text(
            'Everything Be@Mandaluyong can do, in one place.',
            style: text.bodyMedium?.copyWith(color: colors.outline),
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
        _Reveal(delayMs: 80, child: Text(firstTitle, style: _sectionStyle(context))),
        const SizedBox(height: AppSpacing.m),
        grid(first, 120),
        const SizedBox(height: AppSpacing.xxl),
        _Reveal(
            delayMs: 200, child: Text(secondTitle, style: _sectionStyle(context))),
        const SizedBox(height: AppSpacing.m),
        grid(second, 240),
        const SizedBox(height: AppSpacing.xl),
        // Emergency is always reachable from here too.
        _Reveal(
          delayMs: 300,
          child: OutlinedButton.icon(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const EmergencyPage()),
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFFD32F2F),
              side: BorderSide(
                  color: const Color(0xFFD32F2F).withValues(alpha: 0.5)),
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.m),
            ),
            icon: const Icon(Icons.emergency_outlined),
            label: const Text('Emergency hotlines'),
          ),
        ),
      ],
    );
  }
}

/// A warm headline that changes with the time of day and who's reading it.
/// Keeps the dashboard feeling alive without leaning on emoji.
String _headline(UserRole role, int hour) {
  final morning = hour < 12;
  final afternoon = hour >= 12 && hour < 18;

  if (role == UserRole.mandaleno) {
    if (morning) {
      return 'Your city is awake — services, news, and events for today.';
    }
    if (afternoon) {
      return 'City services, news, and events, all in one place.';
    }
    return 'Catch up on today\'s news and updates from the city.';
  }
  if (morning) {
    return 'A perfect morning to explore the heritage and culture of '
        'Mandaluyong City.';
  }
  if (afternoon) {
    return 'The city is waiting — heritage, food, and places to discover.';
  }
  return 'Explore the heritage, culture, and services of Mandaluyong City.';
}

// ===========================================================================
// Admin home — the dashboard CCAT staff see instead of the visitor screen.
// Work first: what needs attention, then quick actions. No trail progress,
// featured churches or itineraries — those are visitor features.
// ===========================================================================
class _AdminHomeView extends StatefulWidget {
  const _AdminHomeView();

  @override
  State<_AdminHomeView> createState() => _AdminHomeViewState();
}

class _AdminHomeViewState extends State<_AdminHomeView> {
  int? _pending;
  int? _feedback;
  int? _users;

  @override
  void initState() {
    super.initState();
    _loadCounts();
  }

  Future<void> _loadCounts() async {
    try {
      final db = FirebaseFirestore.instance;
      final results = await Future.wait([
        db.collection(kAccreditationCollection).get(),
        db.collection('feedback').get(),
        db.collection('users').get(),
      ]);
      if (!mounted) return;
      setState(() {
        _pending = results[0]
            .docs
            .where((d) => (d.data()['status'] ?? 'pending') == 'pending')
            .length;
        _feedback = results[1].docs.length;
        _users = results[2].docs.length;
      });
    } catch (_) {
      // Rules or connectivity — the tiles simply show a dash.
    }
  }

  void _open(Widget page) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => page))
        .then((_) => _loadCounts());
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final name = FirebaseAuth.instance.currentUser?.displayName;
    final hour = DateTime.now().hour;
    final greeting = hour < 12
        ? 'Good morning'
        : (hour < 18 ? 'Good afternoon' : 'Good evening');

    return RefreshIndicator(
      onRefresh: _loadCounts,
      child: ListView(
        padding: const EdgeInsets.all(AppSpacing.l),
        children: [
          // ---- Administrator header ----
          _Reveal(
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
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF12305F).withValues(alpha: 0.22),
                    blurRadius: 14,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 46,
                        height: 46,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                          border: Border.all(
                              color: AppTheme.brandGold.withValues(alpha: 0.7),
                              width: 1.5),
                        ),
                        child: const Icon(Icons.account_balance_rounded,
                            color: Colors.white, size: 22),
                      ),
                      const SizedBox(width: AppSpacing.m),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'CCAT ADMINISTRATOR',
                              style: text.labelSmall?.copyWith(
                                color: AppTheme.brandGold,
                                letterSpacing: 1.2,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              (name == null || name.trim().isEmpty)
                                  ? 'Administrator'
                                  : name.trim(),
                              style: text.titleLarge?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.l),
                  Container(
                    width: 44,
                    height: 3,
                    decoration: BoxDecoration(
                      color: AppTheme.brandGold,
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.m),
                  Row(
                    children: [
                      Icon(Icons.event_note_outlined,
                          size: 15,
                          color: Colors.white.withValues(alpha: 0.75)),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          '$greeting · ${_today()}',
                          style: text.bodySmall?.copyWith(
                              color: Colors.white.withValues(alpha: 0.85)),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(Icons.task_alt,
                          size: 15,
                          color: Colors.white.withValues(alpha: 0.75)),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          _pending == null
                              ? 'Loading pending work…'
                              : (_pending == 0
                                  ? 'No applications waiting — all caught up'
                                  : '$_pending application'
                                      '${_pending == 1 ? '' : 's'} awaiting '
                                      'your decision'),
                          style: text.bodySmall?.copyWith(
                              color: Colors.white.withValues(alpha: 0.85)),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.l),

          // ---- Action-required banner ----
          if ((_pending ?? 0) > 0)
            _Reveal(
              delayMs: 40,
              child: Container(
                margin: const EdgeInsets.only(bottom: AppSpacing.l),
                padding: const EdgeInsets.all(AppSpacing.m),
                decoration: BoxDecoration(
                  color: const Color(0xFFEF6C00).withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  border: Border.all(
                      color: const Color(0xFFEF6C00).withValues(alpha: 0.4)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.priority_high_rounded,
                        color: Color(0xFFEF6C00), size: 20),
                    const SizedBox(width: AppSpacing.s),
                    Expanded(
                      child: Text(
                        '$_pending application${_pending == 1 ? '' : 's'} '
                        'awaiting review',
                        style: text.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFFEF6C00)),
                      ),
                    ),
                    TextButton(
                      onPressed: () => _open(const AdminPanelPage()),
                      child: const Text('Review'),
                    ),
                  ],
                ),
              ),
            ),

          // ---- Key metrics ----
          _Reveal(
            delayMs: 60,
            child: Text('KEY METRICS', style: _adminLabel(context)),
          ),
          const SizedBox(height: AppSpacing.m),
          _Reveal(
            delayMs: 90,
            child: Row(
              children: [
                _AdminStat(
                  label: 'Registered users',
                  value: _users?.toString() ?? '—',
                  icon: Icons.people_outline,
                  onTap: () => _open(const AdminPanelPage()),
                ),
                const SizedBox(width: AppSpacing.m),
                _AdminStat(
                  label: 'Feedback received',
                  value: _feedback?.toString() ?? '—',
                  icon: Icons.forum_outlined,
                  onTap: () => _open(const AnalyticsDashboardPage()),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.m),
          _Reveal(
            delayMs: 120,
            child: Row(
              children: [
                _AdminStat(
                  label: 'Pending review',
                  value: _pending?.toString() ?? '—',
                  icon: Icons.pending_actions_outlined,
                  highlight: (_pending ?? 0) > 0,
                  onTap: () => _open(const AdminPanelPage()),
                ),
                const SizedBox(width: AppSpacing.m),
                _AdminStat(
                  label: 'NLP model report',
                  value: 'View',
                  icon: Icons.science_outlined,
                  onTap: () => _open(const SentimentEvalPage()),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xxl),

          // ---- Modules ----
          _Reveal(
            delayMs: 160,
            child: Text('SYSTEM MODULES', style: _adminLabel(context)),
          ),
          const SizedBox(height: AppSpacing.m),
          _Reveal(
            delayMs: 190,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppRadius.lg),
                border: Border.all(color: colors.outlineVariant),
              ),
              child: Column(
                children: [
                  _ModuleRow(
                    icon: Icons.dashboard_outlined,
                    title: 'Administration',
                    subtitle: 'Applications · announcements · user records',
                    onTap: () => _open(const AdminPanelPage()),
                  ),
                  Divider(height: 1, color: colors.outlineVariant),
                  _ModuleRow(
                    icon: Icons.insights_outlined,
                    title: 'Sentiment analytics',
                    subtitle: 'Visitor feedback classified by NLP',
                    onTap: () => _open(const AnalyticsDashboardPage()),
                  ),
                  Divider(height: 1, color: colors.outlineVariant),
                  _ModuleRow(
                    icon: Icons.science_outlined,
                    title: 'Model accuracy report',
                    subtitle: 'How the sentiment classifier performs',
                    onTap: () => _open(const SentimentEvalPage()),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.xl),

          // ---- Footer ----
          Center(
            child: Text(
              'Be@Mandaluyong · Administration Console',
              style: text.labelSmall?.copyWith(color: colors.outline),
            ),
          ),
        ],
      ),
    );
  }
}

/// Small uppercase section label used across the admin console.
TextStyle? _adminLabel(BuildContext context) =>
    Theme.of(context).textTheme.labelSmall?.copyWith(
          fontWeight: FontWeight.w800,
          letterSpacing: 1.0,
          color: Theme.of(context).colorScheme.outline,
        );

/// Today's date, e.g. "6 August 2026".
String _today() {
  const months = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December'
  ];
  final d = DateTime.now();
  return '${d.day} ${months[d.month - 1]} ${d.year}';
}

/// A metric card in the admin console — flat, bordered, data-first.
class _AdminStat extends StatelessWidget {
  const _AdminStat({
    required this.label,
    required this.value,
    required this.icon,
    this.highlight = false,
    this.onTap,
  });

  final String label;
  final String value;
  final IconData icon;
  final bool highlight;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final accent = highlight ? const Color(0xFFEF6C00) : colors.primary;

    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.md),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.l),
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(
              color: highlight
                  ? accent.withValues(alpha: 0.55)
                  : colors.outlineVariant,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, color: accent, size: 18),
                  const Spacer(),
                  Icon(Icons.north_east_rounded,
                      size: 13, color: colors.outlineVariant),
                ],
              ),
              const SizedBox(height: AppSpacing.m),
              Text(value,
                  style: text.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      height: 1.0,
                      color: highlight ? accent : colors.onSurface)),
              const SizedBox(height: 4),
              Text(label.toUpperCase(),
                  style: text.labelSmall?.copyWith(
                    color: colors.outline,
                    letterSpacing: 0.5,
                    fontWeight: FontWeight.w600,
                  )),
            ],
          ),
        ),
      ),
    );
  }
}

/// A row in the "System modules" list.
class _ModuleRow extends StatelessWidget {
  const _ModuleRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final accent = colors.primary;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.l, vertical: AppSpacing.m),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              child: Icon(icon, size: 19, color: accent),
            ),
            const SizedBox(width: AppSpacing.m),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: text.bodyLarge
                          ?.copyWith(fontWeight: FontWeight.w600)),
                  Text(subtitle,
                      style: text.bodySmall
                          ?.copyWith(color: colors.outline)),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: colors.outlineVariant),
          ],
        ),
      ),
    );
  }
}

/// Quiet, consistent section label used across the home screen.
TextStyle? _sectionStyle(BuildContext context) =>
    Theme.of(context).textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: 0.2,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        );

/// Minimal weather readout for the home header (plain text, no chrome).
class _HomeWeather extends StatefulWidget {
  const _HomeWeather();

  @override
  State<_HomeWeather> createState() => _HomeWeatherState();
}

class _HomeWeatherState extends State<_HomeWeather> {
  Weather? _weather;

  @override
  void initState() {
    super.initState();
    WeatherService.fetch().then((w) {
      if (mounted) setState(() => _weather = w);
    }).catchError((_) {});
  }

  @override
  Widget build(BuildContext context) {
    final w = _weather;
    if (w == null) return const SizedBox.shrink();
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(w.icon, size: 18, color: colors.outline),
        const SizedBox(width: 6),
        Text(
          '${w.tempC.round()}°',
          style: text.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
            color: colors.onSurface,
          ),
        ),
      ],
    );
  }
}

/// Spotlight card nudging tourists toward a ready-made day plan.
class _ItinerarySpotlightCard extends StatelessWidget {
  const _ItinerarySpotlightCard();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Card(
      clipBehavior: Clip.antiAlias,
      elevation: 0,
      color: colors.surfaceContainerHighest,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg)),
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const ItineraryPage()),
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.l),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: colors.primary.withValues(alpha: 0.08),
                ),
                child: Icon(Icons.route_rounded,
                    color: colors.primary, size: 26),
              ),
              const SizedBox(width: AppSpacing.l),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'First time in Mandaluyong?',
                      style:
                          text.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Follow a ready-made half-day or full-day plan',
                      style: text.bodySmall?.copyWith(color: colors.outline),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.s),
              Icon(Icons.chevron_right, color: colors.outline),
            ],
          ),
        ),
      ),
    );
  }
}

/// Spotlight card that opens the Mayor's official Facebook updates.
class _MayorSpotlightCard extends StatelessWidget {
  const _MayorSpotlightCard();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Card(
      clipBehavior: Clip.antiAlias,
      elevation: 0,
      color: colors.surfaceContainerHighest,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg)),
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const AnnouncementsPage()),
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.l),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: colors.primary.withValues(alpha: 0.08),
                ),
                child: Icon(Icons.campaign_rounded,
                    color: colors.primary, size: 26),
              ),
              const SizedBox(width: AppSpacing.l),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Office of the City Mayor',
                      style:
                          text.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Official announcements, advisories and city updates',
                      style: text.bodySmall?.copyWith(color: colors.outline),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.s),
              Icon(Icons.chevron_right, color: colors.outline),
            ],
          ),
        ),
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
