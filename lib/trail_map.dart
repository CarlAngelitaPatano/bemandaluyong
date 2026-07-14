import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import 'heritage.dart'; // kChurches, Church, TrailProgress, ChurchDetailPage
import 'city_content.dart'; // CityItem, CityDetailPage
import 'attractions.dart'; // kAttractions
import 'theme.dart';

// Distinct color for tourist-attraction pins (churches use the brand colors).
const Color _attractionColor = Color(0xFFEF6C00); // deep orange

// ===========================================================================
// Mandaluyong Map — heritage churches AND major tourist attractions as pins on
// an OpenStreetMap, with the user's live location. Free, no API key required.
// ===========================================================================
class TrailMapPage extends StatefulWidget {
  const TrailMapPage({super.key});

  @override
  State<TrailMapPage> createState() => _TrailMapPageState();
}

class _TrailMapPageState extends State<TrailMapPage> {
  final MapController _map = MapController();
  // Centered on Mandaluyong so churches (west) and attractions (east) both show.
  static const LatLng _center = LatLng(14.586, 121.043);

  LatLng? _me; // user's current position
  bool _locating = false;

  Future<void> _locate() async {
    setState(() => _locating = true);
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
      if (!mounted) return;
      final me = LatLng(pos.latitude, pos.longitude);
      setState(() => _me = me);
      _map.move(me, 16);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  void _openChurch(Church c) {
    showModalBottomSheet(
      context: context,
      builder: (_) => _ChurchSheet(church: c),
    );
  }

  void _openAttraction(CityItem a) {
    showModalBottomSheet(
      context: context,
      builder: (_) => _AttractionSheet(item: a),
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
        color: Colors.blue,
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
class _ChurchSheet extends StatelessWidget {
  const _ChurchSheet({required this.church});
  final Church church;

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
                      style: text.bodyMedium?.copyWith(color: colors.outline)),
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
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
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
  const _AttractionSheet({required this.item});
  final CityItem item;

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
                      style: text.bodyMedium?.copyWith(color: colors.outline)),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(Icons.sell_outlined, size: 16, color: colors.outline),
                const SizedBox(width: 6),
                Text(item.tag,
                    style: text.bodyMedium?.copyWith(color: colors.outline)),
              ],
            ),
            const SizedBox(height: AppSpacing.l),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
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
