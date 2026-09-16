import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import 'attractions.dart'; // kAttractions
import 'dining.dart'; // kEateries
import 'directions.dart'; // distance formatting
import 'heritage.dart'; // kChurches
import 'motion.dart';
import 'theme.dart';
import 'trail_map.dart'; // opens with the route already drawn

// ===========================================================================
// What is near you, right now.
//
// The curated itineraries answer "what should I do today". This answers a
// different question — "what is around me at this moment" — which is what a
// visitor actually asks while standing on a street in Mandaluyong.
//
// The two are kept apart on purpose. An itinerary has an intended order:
// morning church, lunch, afternoon walk. Re-sorting one by distance would put
// dinner before breakfast because the restaurant happened to be closer, and
// quietly destroy the thinking that went into it.
//
// Every coordinate here already existed — in kChurches, kAttractions and
// kEateries. Nothing new is stored; they are simply measured against where
// the person is standing.
// ===========================================================================

/// A place with a known position, and how far away it is.
class NearbyPlace {
  const NearbyPlace({
    required this.name,
    required this.kind,
    required this.icon,
    required this.metres,
    required this.at,
  });

  final String name;

  /// "Heritage church", "Attraction", "Homegrown" — what sort of place it is.
  final String kind;
  final IconData icon;
  final double metres;

  /// Where it is. Someone who asked what is nearest wants to be taken there,
  /// so this carries a position rather than a page to read.
  final LatLng at;
}

class Nearby {
  Nearby._();

  /// Finds the closest places to [from], nearest first.
  ///
  /// Straight-line distance, deliberately: a walking route for every candidate
  /// would mean a dozen requests to a courtesy server to answer a question
  /// that only needs "which of these is closest". The route is a tap away once
  /// a place is chosen.
  static List<NearbyPlace> around(Position from, {int limit = 5}) {
    double metresTo(double lat, double lng) => Geolocator.distanceBetween(
        from.latitude, from.longitude, lat, lng);

    final places = <NearbyPlace>[
      for (final c in kChurches)
        NearbyPlace(
          name: c.name,
          kind: 'Heritage church',
          icon: Icons.church_outlined,
          metres: metresTo(c.lat, c.lng),
          at: LatLng(c.lat, c.lng),
        ),
      for (final a in kAttractions)
        if (a.lat != null && a.lng != null)
          NearbyPlace(
            name: a.title,
            kind: 'Attraction',
            icon: Icons.photo_camera_outlined,
            metres: metresTo(a.lat!, a.lng!),
            at: LatLng(a.lat!, a.lng!),
          ),
      for (final e in kEateries)
        NearbyPlace(
          name: e.name,
          kind: 'Homegrown',
          icon: Icons.storefront_outlined,
          metres: metresTo(e.lat, e.lng),
          at: LatLng(e.lat, e.lng),
        ),
    ]..sort((a, b) => a.metres.compareTo(b.metres));

    return places.take(limit).toList();
  }
}

// ---------------------------------------------------------------------------
// The card
// ---------------------------------------------------------------------------

/// Shows what is closest, once the person asks for it.
///
/// Location is NOT requested when the page opens. A screen that demands GPS
/// the moment it is shown is both slow and presumptuous — most people opening
/// Itineraries are reading, not walking. The button states plainly what will
/// happen, and nothing is measured until it is pressed.
class NearbyNowCard extends StatefulWidget {
  const NearbyNowCard({super.key});

  @override
  State<NearbyNowCard> createState() => _NearbyNowCardState();
}

class _NearbyNowCardState extends State<NearbyNowCard> {
  List<NearbyPlace>? _places;
  bool _busy = false;
  String? _error;

  Future<void> _find() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        throw 'Turn on Location (GPS) to see what is near you.';
      }
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        throw 'Location permission is needed to find places near you.';
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings:
            const LocationSettings(accuracy: LocationAccuracy.high),
      );
      if (!mounted) return;
      setState(() => _places = Nearby.around(pos));
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final places = _places;

    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        side: BorderSide(color: AppTheme.brandGold.withValues(alpha: 0.45)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.l),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.near_me_outlined, color: colors.primary, size: 20),
                const SizedBox(width: AppSpacing.s),
                Expanded(
                  child: Text('Nearest to you',
                      style: text.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700)),
                ),
                if (places != null)
                  IconButton(
                    tooltip: 'Check again',
                    onPressed: _busy ? null : _find,
                    icon: const Icon(Icons.refresh, size: 20),
                  ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              places == null
                  ? 'See which heritage churches, attractions and local '
                      'places are closest to where you are standing.'
                  : 'Tap any place to walk there.',
              style: text.bodySmall?.copyWith(color: colors.onSurfaceVariant),
            ),

            if (_error != null) ...[
              const SizedBox(height: AppSpacing.m),
              Text(_error!,
                  style: text.bodySmall
                      ?.copyWith(color: AppTheme.cityRed)),
            ],

            if (places == null) ...[
              const SizedBox(height: AppSpacing.m),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _busy ? null : _find,
                  icon: _busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.my_location),
                  label: Text(_busy ? 'Finding you…' : 'Find places near me'),
                ),
              ),
            ] else ...[
              const SizedBox(height: AppSpacing.m),
              for (int i = 0; i < places.length; i++)
                Reveal(
                  delayMs: i * 60,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    // Straight to the route. Someone who asked what is nearest
                    // wants to get there — an article about the place is not
                    // what they were reaching for.
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => TrailMapPage(
                          destination: places[i].at,
                          destinationName: places[i].name,
                        ),
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Row(
                        children: [
                          Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: colors.primary.withValues(alpha: 0.10),
                            ),
                            child: Icon(places[i].icon,
                                size: 19, color: colors.primary),
                          ),
                          const SizedBox(width: AppSpacing.m),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  places[i].name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: text.bodyMedium
                                      ?.copyWith(fontWeight: FontWeight.w600),
                                ),
                                Text(
                                  places[i].kind,
                                  style: text.labelSmall
                                      ?.copyWith(color: colors.onSurfaceVariant),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: AppSpacing.s),
                          Text(
                            Directions.distanceLabel(places[i].metres),
                            style: text.labelLarge?.copyWith(
                              fontWeight: FontWeight.w800,
                              color: AppTheme.brandGold,
                            ),
                          ),
                          const SizedBox(width: 2),
                          Icon(Icons.directions_walk_rounded,
                              size: 20, color: colors.primary),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
