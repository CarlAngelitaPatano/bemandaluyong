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
import 'theme.dart'; // the city's two-colour system
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

  /// The feature's colour, drawn from the city seal's two-colour system.
  ///
  /// Navy is the default and covers nearly everything — it is the workhorse
  /// the theme describes for navigation, actions and feature icons. Gold marks
  /// heritage and achievement. Red is spent only on emergencies, so that when
  /// red appears anywhere in this app it means one thing.
  ///
  /// This deliberately is NOT a palette of eight. A grid where every tile
  /// carries its own hue looks busy rather than considered, and it costs red
  /// its meaning.
  final Color color;

  /// Screen to open when tapped. Null means "no destination yet".
  final WidgetBuilder? page;

  const AppFeature(
    this.label,
    this.icon, {
    this.color = AppTheme.brandBlue,
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
      Icons.church_outlined,
      // Gold: heritage and achievement, per the seal's palette.
      color: AppTheme.brandGold,
      page: (_) => const HeritageChurchesPage(),
    );

/// Discovery features — places to go and things to see.
/// [includeTrail] is false where the trail is already featured on its own,
/// so it does not appear twice on the same screen.
///
/// Every icon is outlined and navy. Uniformity is the point: the eye should
/// land on the LABEL, which is what distinguishes one shortcut from another,
/// rather than being pulled around a grid by eight competing colours.
List<AppFeature> exploreFeatures({bool includeTrail = true}) => <AppFeature>[
      if (includeTrail) heritageTrailFeature(),
      AppFeature('Itineraries', Icons.route_outlined,
          page: (_) => const ItineraryPage()),
      AppFeature('Map', Icons.map_outlined, page: (_) => const TrailMapPage()),
      AppFeature('Attractions', Icons.photo_camera_outlined,
          page: (_) => const AttractionsPage()),
      AppFeature('Homegrown', Icons.storefront_outlined,
          page: (_) => const DiningPage()),
      AppFeature('3D / AR', Icons.view_in_ar_outlined,
          page: (_) => const ArIntroPage()),
    ];

/// City-hall features — news, events, and the ways to reach CCAT.
/// [role] decides which resident-only items are included.
List<AppFeature> cityServiceFeatures(UserRole role) => <AppFeature>[
      // Official city announcements are aimed at residents, so they are shown
      // to Mandaleños (and staff) rather than visiting tourists.
      // Shown to everyone now. An announcement carries its own audience, set
      // by the officer who published it, and the list only ever shows what was
      // addressed to the person reading — so hiding the whole feature from
      // visitors would only mean a notice written for them had nowhere to be
      // read.
      AppFeature('Announcements', Icons.campaign_outlined,
          page: (_) => const AnnouncementsPage(),
          // The only badge that needs the network; it resolves late and the
          // tile simply gains a number when it does.
          badge: AnnouncementService.unreadCount()),
      AppFeature('News', Icons.newspaper_outlined,
          page: (_) => const NewsPage()),
      // No badge. It used to carry kEvents.length, which put "43" on the tile
      // — the whole year's calendar, shown in the same pill shape an unread
      // count uses. It read as forty-three things waiting to be looked at.
      // A number on a tile has to mean "new" or "yours"; a total does not.
      AppFeature('Events', Icons.event_outlined,
          page: (_) => const EventsPage()),
      AppFeature('Services', Icons.widgets_outlined,
          page: (_) => const ServicesPage()),
      AppFeature('Contact', Icons.support_agent_outlined,
          page: (_) => const ReportConcernPage()),
      AppFeature('Feedback', Icons.rate_review_outlined,
          page: (_) => const FeedbackPage()),
      // Business accreditation is for local establishment owners, so it is
      // offered to Mandaleños only. (Analytics is a CCAT staff tool and is not
      // shown to visitors at all.)
      if (role == UserRole.mandaleno) ...[
        AppFeature('Accreditation', Icons.verified_outlined,
            page: (_) => const AccreditationPage()),
        AppFeature('Request Event', Icons.add_circle_outline,
            page: (_) => const EventRequestPage()),
      ],
    ];

// Staff have no entry here. CCAT tools are reached from the staff console
// (staff_panel.dart), which is the whole home screen for those accounts —
// there is no Services button on a staff session to put them behind.

/// Always reachable, and deliberately kept out of the ordinary grids so it
/// reads as urgent rather than as one option among many.
///
/// The only red in this menu. That is what makes it work: red is spent here
/// and nowhere else, so a person who sees it knows without reading.
AppFeature emergencyFeature() => AppFeature(
      'Emergency',
      Icons.emergency_outlined,
      color: AppTheme.cityRed,
      page: (_) => const EmergencyPage(),
    );
