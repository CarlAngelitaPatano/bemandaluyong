import 'package:flutter/material.dart';

import 'accreditation.dart';
import 'announcements.dart'; // AnnouncementsPage + unread count for the badge
import 'ar_view.dart';
import 'attractions.dart';
import 'city_content.dart';
import 'dining.dart';
import 'emergency.dart';
import 'event_requests.dart';
import 'feedback_page.dart';
import 'heritage.dart';
import 'itinerary.dart';
import 'news_page.dart';
import 'report_concern_page.dart';
import 'trail_map.dart';
import 'user_role.dart';

// ===========================================================================
// The app's feature catalogue — ONE definition, read by two surfaces:
//
//   • the Services tab (a scrollable, grouped grid), and
//   • the floating quick menu (quick_menu.dart), reachable from any tab.
//
// Keeping the lists here means a feature added or removed for a role changes
// in exactly one place, and the two surfaces can never drift apart.
//
// Which features appear depends on the signed-in role: Announcements,
// Accreditation and Request Event are for residents (Mandaleños), because
// they concern city business rather than a visitor's trip.
// ===========================================================================

/// One tappable feature: what it is called, how it is drawn, and where it goes.
class AppFeature {
  final String label;
  final IconData icon;

  /// Optional count shown on the tile — unread announcements, events listed,
  /// and so on. A future rather than a plain number so a badge that needs the
  /// network can resolve late without holding up the menu; counts already on
  /// the device are handed over as an already-completed future and appear
  /// immediately. Zero and null both mean "draw nothing".
  final Future<int>? badge;

  /// The feature's colour identity. The Services grid currently draws every
  /// tile in the brand blue for calmness; the quick menu uses this colour so
  /// shortcuts stay distinguishable at a glance in a dense grid.
  final Color color;

  /// Screen to open when tapped. Null means "no destination yet".
  final WidgetBuilder? page;

  const AppFeature(
    this.label,
    this.icon, {
    this.color = const Color(0xFF0038A8),
    this.page,
    this.badge,
  });
}

/// The Heritage Church Trail — the app's flagship feature.
///
/// Kept separate so the Services menu can promote it to a full-width card
/// with progress on it, while anywhere that just wants a grid of everything
/// can still include it as an ordinary tile.
AppFeature heritageTrailFeature() => AppFeature(
      'Heritage Trail',
      Icons.church_rounded,
      color: const Color(0xFF0038A8),
      page: (_) => const HeritageChurchesPage(),
    );

/// Discovery features — places to go and things to see.
/// [includeTrail] is false where the trail is already featured on its own,
/// so it does not appear twice on the same screen.
List<AppFeature> exploreFeatures({bool includeTrail = true}) => <AppFeature>[
      if (includeTrail) heritageTrailFeature(),
      AppFeature('Itineraries', Icons.route_rounded,
          color: const Color(0xFF6D4C41), page: (_) => const ItineraryPage()),
      AppFeature('Map', Icons.map_rounded,
          color: const Color(0xFF1E88E5), page: (_) => const TrailMapPage()),
      AppFeature('Attractions', Icons.photo_camera_rounded,
          color: const Color(0xFFF4511E), page: (_) => const AttractionsPage()),
      AppFeature('Homegrown', Icons.storefront_rounded,
          color: const Color(0xFF8E24AA), page: (_) => const DiningPage()),
      AppFeature('3D / AR', Icons.view_in_ar_rounded,
          color: const Color(0xFF00897B), page: (_) => const ArIntroPage()),
    ];

/// City-hall features — news, events, and the ways to reach CCAT.
/// [role] decides which resident-only items are included.
List<AppFeature> cityServiceFeatures(UserRole role) => <AppFeature>[
      // Official city announcements are aimed at residents, so they are shown
      // to Mandaleños (and staff) rather than visiting tourists.
      if (role == UserRole.mandaleno)
        AppFeature('Announcements', Icons.campaign_rounded,
            color: const Color(0xFF00838F),
            page: (_) => const AnnouncementsPage(),
            // The only badge that needs the network; it resolves late and the
            // tile simply gains a number when it does.
            badge: AnnouncementService.unreadCount()),
      AppFeature('News', Icons.newspaper_rounded,
          color: const Color(0xFF3949AB), page: (_) => const NewsPage()),
      AppFeature('Events', Icons.event_rounded,
          color: const Color(0xFFE53935),
          page: (_) => const EventsPage(),
          badge: Future<int>.value(kEvents.length)),
      AppFeature('Services', Icons.widgets_rounded,
          color: const Color(0xFF43A047), page: (_) => const ServicesPage()),
      AppFeature('Contact', Icons.support_agent_rounded,
          color: const Color(0xFFFB8C00),
          page: (_) => const ReportConcernPage()),
      AppFeature('Feedback', Icons.rate_review_rounded,
          color: const Color(0xFF00838F), page: (_) => const FeedbackPage()),
      // Business accreditation is for local establishment owners, so it is
      // offered to Mandaleños only. (Analytics is a CCAT staff tool and is not
      // shown to visitors at all.)
      if (role == UserRole.mandaleno) ...[
        AppFeature('Accreditation', Icons.verified_outlined,
            color: const Color(0xFF00695C),
            page: (_) => const AccreditationPage()),
        AppFeature('Request Event', Icons.add_circle_outline,
            color: const Color(0xFF5E35B1),
            page: (_) => const EventRequestPage()),
      ],
    ];

// Staff have no entry here. CCAT tools are reached from the staff console
// (staff_panel.dart), which is the whole home screen for those accounts —
// there is no Services button on a staff session to put them behind.

/// Always reachable, and deliberately kept out of the ordinary grids so it
/// reads as urgent rather than as one option among many.
AppFeature emergencyFeature() => AppFeature(
      'Emergency',
      Icons.emergency_outlined,
      color: const Color(0xFFD32F2F),
      page: (_) => const EmergencyPage(),
    );
