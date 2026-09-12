import 'dart:convert';

import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

// ===========================================================================
// Getting there.
//
// Two ways to reach a stop, because they fail in different situations:
//
//   • an IN-APP walking route drawn on the trail map, so the person can see
//     the path without leaving Be@Mandaluyong, and
//   • a hand-off to Google Maps for real turn-by-turn navigation.
//
// The in-app route comes from OSRM's public demo server, which — like the
// weather and map tiles this app already uses — needs no API key. It is a
// courtesy service with no uptime guarantee, so every call here returns null
// rather than throwing, and the map falls back to a straight line between the
// two points. A missing route never blocks anyone from walking to a church.
// ===========================================================================

/// A walkable path between two points.
class WalkingRoute {
  const WalkingRoute({
    required this.points,
    required this.meters,
    required this.seconds,
    required this.isEstimate,
  });

  /// The path to draw, in order.
  final List<LatLng> points;

  /// Distance along the path, in metres.
  final double meters;

  /// Expected walking time, in seconds.
  final double seconds;

  /// True when this is a straight line rather than a real street route —
  /// the routing service was unreachable. The map says so rather than
  /// presenting a line through buildings as if it were directions.
  final bool isEstimate;
}

class Directions {
  Directions._();

  /// OSRM's public demo server. Free and keyless, like the OpenStreetMap
  /// tiles the map already draws.
  static const String _osrm = 'https://router.project-osrm.org';

  /// Average walking speed in metres per minute (roughly 4.8 km/h), used only
  /// for the straight-line fallback.
  static const double _metresPerMinute = 80;

  /// Straight-line distance in metres — instant, no network, good enough for
  /// the "1.2 km away" line in a sheet before any route is requested.
  static double crowFlies(LatLng from, LatLng to) =>
      Geolocator.distanceBetween(
          from.latitude, from.longitude, to.latitude, to.longitude);

  /// Fetches a walking route. Returns a straight-line [WalkingRoute] with
  /// [WalkingRoute.isEstimate] set when the service cannot be reached, and
  /// never throws.
  static Future<WalkingRoute> walkingRoute(LatLng from, LatLng to) async {
    try {
      // OSRM takes longitude first — a genuinely easy mistake to make, and it
      // silently returns a route on the other side of the planet.
      final path = '${from.longitude},${from.latitude}'
          ';${to.longitude},${to.latitude}';
      final uri = Uri.parse(
          '$_osrm/route/v1/foot/$path?overview=full&geometries=geojson');

      final res = await http.get(uri, headers: {
        // Identifying the app is expected of anyone using the demo server.
        'User-Agent': 'BeAtMandaluyong/1.0 (heritage trail app)',
      }).timeout(const Duration(seconds: 12));

      if (res.statusCode != 200) return _straightLine(from, to);

      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final routes = data['routes'] as List?;
      if (routes == null || routes.isEmpty) return _straightLine(from, to);

      final route = routes.first as Map<String, dynamic>;
      final coords =
          (route['geometry']?['coordinates'] as List?) ?? const <dynamic>[];
      if (coords.isEmpty) return _straightLine(from, to);

      return WalkingRoute(
        // GeoJSON is [longitude, latitude]; LatLng is the other way round.
        points: [
          for (final c in coords)
            LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble()),
        ],
        meters: (route['distance'] as num?)?.toDouble() ?? 0,
        seconds: (route['duration'] as num?)?.toDouble() ?? 0,
        isEstimate: false,
      );
    } catch (_) {
      // Offline, server down, or too slow — a straight line still tells the
      // person which way to head.
      return _straightLine(from, to);
    }
  }

  static WalkingRoute _straightLine(LatLng from, LatLng to) {
    final m = crowFlies(from, to);
    return WalkingRoute(
      points: [from, to],
      meters: m,
      seconds: (m / _metresPerMinute) * 60,
      isEstimate: true,
    );
  }

  /// Hands off to Google Maps (or whatever handles the link) for turn-by-turn
  /// navigation. [from] is optional — without it Maps uses the phone's own
  /// current location, which is usually what you want.
  ///
  /// Returns false if nothing on the device could open the link.
  static Future<bool> openInMaps(
    LatLng to, {
    LatLng? from,
    String mode = 'walking',
  }) async {
    final origin =
        from == null ? '' : '&origin=${from.latitude},${from.longitude}';
    final uri = Uri.parse(
      'https://www.google.com/maps/dir/?api=1'
      '&destination=${to.latitude},${to.longitude}'
      '$origin&travelmode=$mode',
    );
    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      return false;
    }
  }

  // -------------------------------------------------------------------------
  // Formatting
  // -------------------------------------------------------------------------

  /// "850 m" / "1.2 km"
  static String distanceLabel(double meters) => meters < 1000
      ? '${meters.round()} m'
      : '${(meters / 1000).toStringAsFixed(1)} km';

  /// "about 15 min" / "about 1 hr 5 min"
  static String durationLabel(double seconds) {
    final mins = (seconds / 60).round();
    if (mins < 1) return 'less than a minute';
    if (mins < 60) return 'about $mins min';
    final hours = mins ~/ 60;
    final rest = mins % 60;
    return rest == 0 ? 'about $hours hr' : 'about $hours hr $rest min';
  }
}
