import 'package:flutter/material.dart';

import 'theme.dart';
import 'motion.dart';
import 'heritage.dart'; // HeritageTrailPage, HeritageChurchesView
import 'attractions.dart'; // AttractionsPage
import 'dining.dart'; // DiningPage
import 'trail_map.dart'; // TrailMapPage

// ===========================================================================
// Suggested Itineraries — ready-made plans for visitors, built from the
// places already in the app (heritage churches, attractions, homegrown
// restaurants and malls). Each stop links to the screen with the details.
// ===========================================================================

/// Where a stop's "View details" button goes.
enum StopTarget { trail, churches, attractions, dining, map }

class ItineraryStop {
  final String time;
  final String title;
  final String detail;
  final IconData icon;
  final StopTarget target;

  const ItineraryStop({
    required this.time,
    required this.title,
    required this.detail,
    required this.icon,
    required this.target,
  });
}

class Itinerary {
  final String title;
  final String subtitle;
  final String duration;
  final String bestFor;
  final IconData icon;
  final Color color;
  final List<ItineraryStop> stops;

  const Itinerary({
    required this.title,
    required this.subtitle,
    required this.duration,
    required this.bestFor,
    required this.icon,
    required this.color,
    required this.stops,
  });
}

const List<Itinerary> kItineraries = [
  // ---------------------------------------------------------------- half day
  Itinerary(
    title: 'Heritage Half-Day',
    subtitle: 'The classic first visit — old churches and local food',
    duration: 'About 4–5 hours',
    bestFor: 'First-time visitors',
    icon: Icons.church_rounded,
    color: Color(0xFF1E88E5),
    stops: [
      ItineraryStop(
        time: '8:00 AM',
        title: 'San Felipe Neri Parish Church',
        detail:
            'Start at the mother church of Mandaluyong, founded in 1863. '
            'Verify your visit in the app to begin the Heritage Trail.',
        icon: Icons.church_outlined,
        target: StopTarget.trail,
      ),
      ItineraryStop(
        time: '9:30 AM',
        title: 'Santuario de San Jose',
        detail:
            'A short ride away in Greenhills East — a peaceful modern shrine '
            'and another Heritage Trail stop.',
        icon: Icons.church_outlined,
        target: StopTarget.trail,
      ),
      ItineraryStop(
        time: '11:00 AM',
        title: 'Tatlong Bayani Statue & Liberation Marker',
        detail:
            'Walk through the city\'s wartime memorials and learn the story '
            'behind Mandaluyong\'s liberation.',
        icon: Icons.location_city_rounded,
        target: StopTarget.attractions,
      ),
      ItineraryStop(
        time: '12:30 PM',
        title: 'Lunch at R&J Bulalohan',
        detail:
            'A Mandaluyong institution — try the bulalo that locals have '
            'lined up for since the 1990s.',
        icon: Icons.restaurant_rounded,
        target: StopTarget.dining,
      ),
    ],
  ),

  // ---------------------------------------------------------------- full day
  Itinerary(
    title: 'Full-Day Explorer',
    subtitle: 'Heritage in the morning, city life in the afternoon',
    duration: 'About 8 hours',
    bestFor: 'A complete Mandaluyong experience',
    icon: Icons.explore_rounded,
    color: Color(0xFF00897B),
    stops: [
      ItineraryStop(
        time: '8:00 AM',
        title: 'Heritage Church Trail (3 stops)',
        detail:
            'San Felipe Neri → Divine Mercy Shrine → San Roque de Barangka. '
            'Verify each visit to earn your certificate.',
        icon: Icons.church_outlined,
        target: StopTarget.trail,
      ),
      ItineraryStop(
        time: '11:00 AM',
        title: 'Villa San Miguel & Nawasa Water Tank',
        detail:
            'The Archbishop\'s residence and the old water tank — two of the '
            'city\'s most photographed landmarks.',
        icon: Icons.photo_camera_rounded,
        target: StopTarget.attractions,
      ),
      ItineraryStop(
        time: '12:30 PM',
        title: 'Lunch at Shangri-La Plaza',
        detail:
            'Mandaluyong\'s upscale mall since 1991, with dozens of dining '
            'options under one roof.',
        icon: Icons.storefront_rounded,
        target: StopTarget.dining,
      ),
      ItineraryStop(
        time: '2:00 PM',
        title: 'SM Megamall',
        detail:
            'One of the largest malls in the Philippines, open since 1991 — '
            'shopping, cinemas, and the Mega Fashion Hall.',
        icon: Icons.shopping_bag_rounded,
        target: StopTarget.dining,
      ),
      ItineraryStop(
        time: '4:30 PM',
        title: 'Wack-Wack & Ortigas skyline',
        detail:
            'End with the historic golf club and the business district that '
            'made Mandaluyong the "Tiger City of the Philippines".',
        icon: Icons.landscape_rounded,
        target: StopTarget.attractions,
      ),
      ItineraryStop(
        time: '6:00 PM',
        title: 'Check your trail progress',
        detail:
            'See how many churches you\'ve verified and how close you are to '
            'the completion certificate.',
        icon: Icons.emoji_events_outlined,
        target: StopTarget.trail,
      ),
    ],
  ),

  // ------------------------------------------------------------------ family
  Itinerary(
    title: 'Family & Food Trip',
    subtitle: 'Easy stops, air-conditioned, kid-friendly',
    duration: 'About 5 hours',
    bestFor: 'Families and rainy days',
    icon: Icons.family_restroom_rounded,
    color: Color(0xFF8E24AA),
    stops: [
      ItineraryStop(
        time: '10:00 AM',
        title: 'The Podium',
        detail: 'Start slow with a relaxed mall morning and coffee.',
        icon: Icons.storefront_rounded,
        target: StopTarget.dining,
      ),
      ItineraryStop(
        time: '12:00 PM',
        title: 'Lunch at R&J Bulalohan',
        detail:
            'Hearty Filipino comfort food that the whole family can share.',
        icon: Icons.restaurant_rounded,
        target: StopTarget.dining,
      ),
      ItineraryStop(
        time: '2:00 PM',
        title: 'Sacred Heart of Jesus Parish',
        detail:
            'A quiet, easy church visit — and one more Heritage Trail stop '
            'for your certificate.',
        icon: Icons.church_outlined,
        target: StopTarget.trail,
      ),
      ItineraryStop(
        time: '3:30 PM',
        title: 'SM Megamall',
        detail:
            'Finish at the big one — cinemas, arcades and dessert before '
            'heading home.',
        icon: Icons.shopping_bag_rounded,
        target: StopTarget.dining,
      ),
    ],
  ),
];

class ItineraryPage extends StatelessWidget {
  const ItineraryPage({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Suggested Itineraries')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.l),
        children: [
          Reveal(
            delayMs: 0,
            child: Text(
              'Not sure where to start?',
              style: text.titleLarge,
            ),
          ),
          const SizedBox(height: 4),
          Reveal(
            delayMs: 40,
            child: Text(
              'Pick a ready-made plan built around Mandaluyong\'s heritage '
              'churches, landmarks and homegrown favourites.',
              style: text.bodyMedium?.copyWith(color: colors.onSurfaceVariant),
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          for (int i = 0; i < kItineraries.length; i++)
            Reveal(
              delayMs: 100 + i * 90,
              child: _ItineraryCard(itinerary: kItineraries[i]),
            ),
          const SizedBox(height: AppSpacing.l),
          Card(
            color: colors.surfaceContainerHighest,
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.l),
              child: Row(
                children: [
                  Icon(Icons.tips_and_updates_outlined, color: colors.outline),
                  const SizedBox(width: AppSpacing.m),
                  Expanded(
                    child: Text(
                      'Tip: open the Map to see how close the stops are to '
                      'each other, and verify each church you visit to earn '
                      'your Heritage Trail certificate.',
                      style: text.bodySmall,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ItineraryCard extends StatelessWidget {
  const _ItineraryCard({required this.itinerary});
  final Itinerary itinerary;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Card(
      clipBehavior: Clip.antiAlias,
      margin: const EdgeInsets.only(bottom: AppSpacing.l),
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Quiet header — one accent, no heavy gradient
          Container(
            padding: const EdgeInsets.all(AppSpacing.l),
            color: colors.primary.withValues(alpha: 0.06),
            child: Row(
              children: [
                Icon(itinerary.icon, color: colors.primary, size: 30),
                const SizedBox(width: AppSpacing.m),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        itinerary.title,
                        style: text.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        itinerary.subtitle,
                        style:
                            text.bodySmall?.copyWith(color: colors.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.l),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: AppSpacing.s,
                  runSpacing: AppSpacing.s,
                  children: [
                    Chip(
                      avatar: const Icon(Icons.schedule, size: 16),
                      label: Text(itinerary.duration),
                      visualDensity: VisualDensity.compact,
                    ),
                    Chip(
                      avatar: const Icon(Icons.star_outline, size: 16),
                      label: Text(itinerary.bestFor),
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.m),

                // Timeline of stops
                for (int i = 0; i < itinerary.stops.length; i++)
                  _StopRow(
                    stop: itinerary.stops[i],
                    color: colors.primary,
                    isLast: i == itinerary.stops.length - 1,
                  ),

                const SizedBox(height: AppSpacing.s),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const TrailMapPage()),
                    ),
                    icon: const Icon(Icons.map_outlined),
                    label: const Text('See these places on the map'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StopRow extends StatelessWidget {
  const _StopRow({
    required this.stop,
    required this.color,
    required this.isLast,
  });

  final ItineraryStop stop;
  final Color color;
  final bool isLast;

  void _openTarget(BuildContext context) {
    final Widget page = switch (stop.target) {
      StopTarget.trail => const HeritageTrailPage(),
      StopTarget.churches => Scaffold(
          appBar: AppBar(title: const Text('Heritage Churches')),
          body: const HeritageChurchesView(),
        ),
      StopTarget.attractions => const AttractionsPage(),
      StopTarget.dining => const DiningPage(),
      StopTarget.map => const TrailMapPage(),
    };
    Navigator.push(context, MaterialPageRoute(builder: (_) => page));
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return InkWell(
      borderRadius: BorderRadius.circular(AppRadius.sm),
      onTap: () => _openTarget(context),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.s),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Timeline dot + connecting line
            Column(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: color.withValues(alpha: 0.15),
                  ),
                  child: Icon(stop.icon, size: 17, color: color),
                ),
                if (!isLast)
                  Container(
                    width: 2,
                    height: 42,
                    color: color.withValues(alpha: 0.25),
                  ),
              ],
            ),
            const SizedBox(width: AppSpacing.m),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    stop.time,
                    style: text.labelSmall?.copyWith(
                      color: color,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    stop.title,
                    style:
                        text.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    stop.detail,
                    style: text.bodySmall?.copyWith(color: colors.onSurfaceVariant),
                  ),
                  const SizedBox(height: AppSpacing.s),
                ],
              ),
            ),
            Icon(Icons.chevron_right, size: 18, color: colors.outline),
          ],
        ),
      ),
    );
  }
}
