import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import 'heritage.dart'; // kChurches, Church, TrailProgress, ChurchDetailPage
import 'city_content.dart'; // CityItem, CityDetailPage
import 'attractions.dart'; // kAttractions
import 'directions.dart'; // walking routes + hand-off to Google Maps
import 'theme.dart';

// Distinct color for tourist-attraction pins (churches use the brand colors).
// Attractions use the seal's gold so the map stays on the app's
// navy + gold system (churches are navy).
const Color _attractionColor = AppTheme.brandGold;

// ===========================================================================
// Mandaluyong Map — heritage churches AND major tourist attractions as pins on
// an OpenStreetMap, with the user's live location. Free, no API key required.
// ===========================================================================
class TrailMapPage extends StatefulWidget {
  const TrailMapPage({
    super.key,
    this.destination,
    this.destinationName,
  });

  /// Open with a walking route already drawn to this point.
  ///
  /// Used when someone picks a place from "Nearest to you": they asked to be
  /// taken there, so the map arrives with the route on it rather than showing
  /// every pin in the city and leaving them to find the one they chose.
  final LatLng? destination;
  final String? destinationName;

  @override
  State<TrailMapPage> createState() => _TrailMapPageState();
}

class _TrailMapPageState extends State<TrailMapPage> {
  final MapController _map = MapController();
  // Centered on Mandaluyong so churches (west) and attractions (east) both show.
  static const LatLng _center = LatLng(14.586, 121.043);

  LatLng? _me; // user's current position
  bool _locating = false;

  // The route currently drawn on the map, if any, and where it leads.
  WalkingRoute? _route;
  String? _routeTo;
  bool _routing = false;

  @override
  void initState() {
    super.initState();
    final dest = widget.destination;
    if (dest != null) {
      // After the first frame: the route needs the map controller, and fitting
      // the camera before the map has been laid out does nothing.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _drawRouteToDestination(dest, widget.destinationName ?? 'Destination');
      });
    }
  }

  /// Gets the current position, asking for permission if needed. Returns null
  /// and explains why when it cannot — the caller just stops.
  Future<LatLng?> _ensureLocation() async {
    try {
      final on = await Geolocator.isLocationServiceEnabled();
      if (!on) throw 'Turn on Location (GPS) to see where you are.';
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        throw 'Location permission is needed to show your position.';
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      );
      if (!mounted) return null;
      final me = LatLng(pos.latitude, pos.longitude);
      setState(() => _me = me);
      return me;
    } catch (e) {
      if (!mounted) return null;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
      return null;
    }
  }

  Future<void> _locate() async {
    setState(() => _locating = true);
    final me = await _ensureLocation();
    if (me != null && mounted) _map.move(me, 16);
    if (mounted) setState(() => _locating = false);
  }

  /// Draws a walking route from the person to [to] and frames both ends.
  Future<void> _drawRouteToDestination(LatLng to, String name) async {
    setState(() => _routing = true);
    try {
      final me = await _ensureLocation();
      if (me == null || !mounted) return;

      final route = await Directions.walkingRoute(me, to);
      if (!mounted) return;
      setState(() {
        _route = route;
        _routeTo = name;
      });

      // Frame the whole walk, with room for the banner and the legend.
      _map.fitCamera(
        CameraFit.bounds(
          bounds: LatLngBounds.fromPoints(route.points),
          padding: const EdgeInsets.fromLTRB(50, 110, 50, 120),
        ),
      );
    } finally {
      if (mounted) setState(() => _routing = false);
    }
  }

  void _clearRoute() => setState(() {
        _route = null;
        _routeTo = null;
      });

  void _openChurch(Church c) {
    final dest = LatLng(c.lat, c.lng);
    showModalBottomSheet(
      context: context,
      builder: (_) => _ChurchSheet(
        church: c,
        me: _me,
        onRoute: () {
          Navigator.pop(context);
          _drawRouteToDestination(dest, c.name);
        },
        onNavigate: () => Directions.openInMaps(dest),
      ),
    );
  }

  void _openAttraction(CityItem a) {
    final dest = LatLng(a.lat!, a.lng!);
    showModalBottomSheet(
      context: context,
      builder: (_) => _AttractionSheet(
        item: a,
        me: _me,
        onRoute: () {
          Navigator.pop(context);
          _drawRouteToDestination(dest, a.title);
        },
        onNavigate: () => Directions.openInMaps(dest),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final attractions = kAttractions.where((a) => a.lat != null).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Mandaluyong Map')),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _map,
            options: MapOptions(
              initialCenter: _center,
              initialZoom: 12.8,
              minZoom: 11,
              maxZoom: 18,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.example.be_mandaluyong',
              ),
              // The walking route, under the pins so it never hides a stop.
              if (_route != null)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: _route!.points,
                      strokeWidth: 6,
                      // Gold for a real street route; a paler, thinner line
                      // when it is only the straight-line fallback, so the two
                      // are never mistaken for each other.
                      color: _route!.isEstimate
                          ? AppTheme.brandGold.withValues(alpha: 0.55)
                          : AppTheme.brandGold,
                      borderStrokeWidth: 2,
                      borderColor: Colors.white.withValues(alpha: 0.85),
                    ),
                  ],
                ),
              // Tourist attractions
              MarkerLayer(
                markers: [
                  for (final a in attractions)
                    Marker(
                      point: LatLng(a.lat!, a.lng!),
                      width: 40,
                      height: 46,
                      alignment: Alignment.bottomCenter,
                      child: GestureDetector(
                        onTap: () => _openAttraction(a),
                        child: _AttractionPin(icon: a.icon),
                      ),
                    ),
                ],
              ),
              // Heritage churches (drawn on top)
              MarkerLayer(
                markers: [
                  for (int i = 0; i < kChurches.length; i++)
                    Marker(
                      point: LatLng(kChurches[i].lat, kChurches[i].lng),
                      width: 44,
                      height: 50,
                      alignment: Alignment.bottomCenter,
                      child: GestureDetector(
                        onTap: () => _openChurch(kChurches[i]),
                        child: _Pin(
                          index: i + 1,
                          verified: TrailProgress.isVisited(kChurches[i]),
                        ),
                      ),
                    ),
                  if (_me != null)
                    Marker(
                      point: _me!,
                      width: 26,
                      height: 26,
                      child: const _MeDot(),
                    ),
                ],
              ),
              RichAttributionWidget(
                attributions: [
                  TextSourceAttribution('© OpenStreetMap contributors'),
                ],
              ),
            ],
          ),
          const Positioned(top: 10, left: 10, child: _Legend()),
          if (_route != null)
            Positioned(
              left: AppSpacing.m,
              right: AppSpacing.m,
              bottom: AppSpacing.m,
              child: _RouteBanner(
                route: _route!,
                destination: _routeTo ?? '',
                onClear: _clearRoute,
              ),
            ),
          if (_routing)
            const Positioned.fill(
              child: ColoredBox(
                color: Color(0x33000000),
                child: Center(child: CircularProgressIndicator()),
              ),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _locating ? null : _locate,
        tooltip: 'My location',
        child: _locating
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.my_location),
      ),
    );
  }
}

/// A numbered map pin (green check when the stop is verified).
class _Pin extends StatelessWidget {
  const _Pin({required this.index, required this.verified});
  final int index;
  final bool verified;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final color = verified
        ? AppTheme.successFor(Theme.of(context).brightness)
        : colors.primary;
    return Stack(
      alignment: Alignment.topCenter,
      children: [
        Icon(Icons.location_on, size: 46, color: color),
        Positioned(
          top: 5,
          child: CircleAvatar(
            radius: 9,
            backgroundColor: Colors.white,
            child: verified
                ? Icon(Icons.check, size: 12, color: color)
                : Text(
                    '$index',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: color,
                    ),
                  ),
          ),
        ),
      ],
    );
  }
}

/// Blue dot for the user's current location.
class _MeDot extends StatelessWidget {
  const _MeDot();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.brandBlue,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 3),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 4,
          ),
        ],
      ),
    );
  }
}

/// Bottom sheet shown when a church pin is tapped.
/// The banner shown while a route is on the map: where it leads, how far, how
/// long, and a way to clear it.
class _RouteBanner extends StatelessWidget {
  const _RouteBanner({
    required this.route,
    required this.destination,
    required this.onClear,
  });

  final WalkingRoute route;
  final String destination;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Material(
      elevation: 4,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      color: colors.surface,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
            AppSpacing.l, AppSpacing.m, AppSpacing.s, AppSpacing.m),
        child: Row(
          children: [
            Icon(Icons.directions_walk_rounded, color: AppTheme.brandGold),
            const SizedBox(width: AppSpacing.m),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    destination,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style:
                        text.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  Text(
                    '${Directions.distanceLabel(route.meters)} · '
                    '${Directions.durationLabel(route.seconds)} walk',
                    style:
                        text.bodySmall?.copyWith(color: colors.onSurfaceVariant),
                  ),
                  // Said plainly rather than passing a line through buildings
                  // off as a route.
                  if (route.isEstimate)
                    Text(
                      'Straight-line estimate — routing unavailable',
                      style: text.labelSmall
                          ?.copyWith(color: colors.onSurfaceVariant),
                    ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Clear route',
              onPressed: onClear,
              icon: const Icon(Icons.close_rounded),
            ),
          ],
        ),
      ),
    );
  }
}

/// The distance line and the two "get me there" buttons, shared by the church
/// and attraction sheets so both behave identically.
class _DirectionsActions extends StatelessWidget {
  const _DirectionsActions({
    required this.me,
    required this.destination,
    required this.onRoute,
    required this.onNavigate,
  });

  final LatLng? me;
  final LatLng destination;
  final VoidCallback onRoute;
  final Future<bool> Function() onNavigate;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Only shown once we know where the person is; otherwise the button
        // below asks for location first.
        if (me != null) ...[
          Row(
            children: [
              Icon(Icons.straighten_rounded, size: 16, color: colors.primary),
              const SizedBox(width: 6),
              Text(
                '${Directions.distanceLabel(Directions.crowFlies(me!, destination))} away',
                style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.m),
        ],
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: onRoute,
                icon: const Icon(Icons.directions_walk_rounded),
                label: const Text('Show route'),
              ),
            ),
            const SizedBox(width: AppSpacing.s),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () async {
                  final ok = await onNavigate();
                  if (!ok && context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('No maps app found on this phone.'),
                      ),
                    );
                  }
                },
                icon: const Icon(Icons.navigation_outlined),
                label: const Text('Navigate'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _ChurchSheet extends StatelessWidget {
  const _ChurchSheet({
    required this.church,
    required this.me,
    required this.onRoute,
    required this.onNavigate,
  });

  final Church church;
  final LatLng? me;
  final VoidCallback onRoute;
  final Future<bool> Function() onNavigate;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final success = AppTheme.successFor(Theme.of(context).brightness);
    final verified = TrailProgress.isVisited(church);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(church.name, style: text.titleMedium),
            const SizedBox(height: AppSpacing.s),
            Row(
              children: [
                Icon(Icons.history, size: 16, color: colors.outline),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(church.era,
                      style: text.bodyMedium?.copyWith(color: colors.onSurfaceVariant)),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(Icons.location_on_outlined, size: 16, color: colors.primary),
                const SizedBox(width: 6),
                Expanded(child: Text(church.location, style: text.bodyMedium)),
              ],
            ),
            if (verified) ...[
              const SizedBox(height: AppSpacing.m),
              Row(
                children: [
                  Icon(Icons.verified, color: success, size: 20),
                  const SizedBox(width: 6),
                  Text('Verified',
                      style: text.bodyMedium
                          ?.copyWith(color: success, fontWeight: FontWeight.w600)),
                ],
              ),
            ],
            const SizedBox(height: AppSpacing.l),
            _DirectionsActions(
              me: me,
              destination: LatLng(church.lat, church.lng),
              onRoute: onRoute,
              onNavigate: onNavigate,
            ),
            const SizedBox(height: AppSpacing.s),
            SizedBox(
              width: double.infinity,
              child: TextButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ChurchDetailPage(church: church),
                    ),
                  );
                },
                icon: const Icon(Icons.info_outline),
                label: const Text('View details'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// An orange map pin for a tourist attraction, badged with its category icon.
class _AttractionPin extends StatelessWidget {
  const _AttractionPin({required this.icon});
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.topCenter,
      children: [
        const Icon(Icons.location_on, size: 42, color: _attractionColor),
        Positioned(
          top: 4,
          child: CircleAvatar(
            radius: 8,
            backgroundColor: Colors.white,
            child: Icon(icon, size: 11, color: _attractionColor),
          ),
        ),
      ],
    );
  }
}

/// Bottom sheet shown when an attraction pin is tapped.
class _AttractionSheet extends StatelessWidget {
  const _AttractionSheet({
    required this.item,
    required this.me,
    required this.onRoute,
    required this.onNavigate,
  });

  final CityItem item;
  final LatLng? me;
  final VoidCallback onRoute;
  final Future<bool> Function() onNavigate;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: _attractionColor.withValues(alpha: 0.15),
                  child: Icon(item.icon, color: _attractionColor),
                ),
                const SizedBox(width: AppSpacing.m),
                Expanded(child: Text(item.title, style: text.titleMedium)),
              ],
            ),
            const SizedBox(height: AppSpacing.m),
            Row(
              children: [
                Icon(Icons.place_outlined, size: 16, color: colors.primary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(item.meta,
                      style: text.bodyMedium?.copyWith(color: colors.onSurfaceVariant)),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(Icons.sell_outlined, size: 16, color: colors.outline),
                const SizedBox(width: 6),
                Text(item.tag,
                    style: text.bodyMedium?.copyWith(color: colors.onSurfaceVariant)),
              ],
            ),
            const SizedBox(height: AppSpacing.l),
            _DirectionsActions(
              me: me,
              destination: LatLng(item.lat!, item.lng!),
              onRoute: onRoute,
              onNavigate: onNavigate,
            ),
            const SizedBox(height: AppSpacing.s),
            SizedBox(
              width: double.infinity,
              child: TextButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => CityDetailPage(item: item)),
                  );
                },
                icon: const Icon(Icons.info_outline),
                label: const Text('View details'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Small legend explaining the two pin colors.
class _Legend extends StatelessWidget {
  const _Legend();

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final style = Theme.of(context).textTheme.labelMedium;

    Widget row(Color c, String label) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.location_on, size: 15, color: c),
              const SizedBox(width: 5),
              Text(label, style: style),
            ],
          ),
        );

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.m, vertical: AppSpacing.s),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            row(primary, 'Churches'),
            row(_attractionColor, 'Attractions'),
          ],
        ),
      ),
    );
  }
}
