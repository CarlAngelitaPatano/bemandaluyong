import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import 'theme.dart';

// ===========================================================================
// Dining — iconic local eats of Mandaluyong. Each place has full details,
// an embedded map, and Call / Get directions actions.
// ===========================================================================
class Eatery {
  final String category; // 'Restaurants' or 'Malls & Stores'
  final String name;
  final String? since; // founding year, e.g. '1991'
  final String specialty;
  final String address;
  final String hours;
  final String priceRange;
  final String description;
  final double lat;
  final double lng;
  final String? phone; // optional — some places have no single public line
  final IconData icon;

  const Eatery({
    this.category = 'Restaurants',
    required this.name,
    this.since,
    required this.specialty,
    required this.address,
    required this.hours,
    required this.priceRange,
    required this.description,
    required this.lat,
    required this.lng,
    this.phone,
    this.icon = Icons.restaurant,
  });

  /// Search query for opening the place in Google Maps (name + address is more
  /// reliable than approximate coordinates).
  String get mapsQuery => Uri.encodeComponent('$name, $address');
}

const List<Eatery> kEateries = [
  Eatery(
    name: 'R&J Bulalohan',
    since: '1995',
    specialty: 'Bulalo — beef shank & bone-marrow soup',
    address: '600 Boni Avenue, Plainview, Mandaluyong (near Maysilo Circle)',
    hours: 'Open 24 hours, daily',
    priceRange: 'Budget-friendly Filipino carinderia',
    phone: '(02) 8533-4811',
    // Approximate — near Maysilo Circle on Boni Ave. "Get directions" searches
    // by name so it still resolves to the exact spot.
    lat: 14.5769,
    lng: 121.0367,
    icon: Icons.ramen_dining,
    description:
        'A beloved family-owned institution serving hearty bulalo since the '
        'mid-1990s — one of Mandaluyong\'s original "OG" kainan spots, still '
        'going strong today. Beyond its signature marrow-rich beef soup, it '
        'also offers Filipino favorites like chicharon bulaklak, tokwa\'t '
        'baboy, and daing na bangus. Open around the clock for late-night '
        'cravings, with generous servings at friendly prices — also available '
        'via Grab and foodpanda.\n\n'
        'Note: bulalo as a dish hails from Batangas, but R&J is a homegrown '
        'Mandaluyong classic near Maysilo Circle and City Hall.',
  ),
  Eatery(
    category: 'Malls & Stores',
    name: 'SM Megamall',
    since: '1991',
    specialty: 'Shopping mall — one of the country\'s largest',
    address: 'EDSA cor. Doña Julia Vargas Ave, Ortigas Center, Mandaluyong',
    hours: 'Daily, 10 AM – 10 PM',
    priceRange: 'Retail, dining, cinemas & more',
    lat: 14.5852,
    lng: 121.0565,
    icon: Icons.local_mall_outlined,
    description:
        'Opened on June 28, 1991, SM Megamall was the third SM Supermall and '
        'has been a Mandaluyong landmark for over three decades. One of the '
        'largest malls in the Philippines, it remains a major shopping, '
        'dining, and entertainment destination in Ortigas Center — and the '
        'birthplace of several homegrown Filipino food brands.',
  ),
  Eatery(
    category: 'Malls & Stores',
    name: 'Shangri-La Plaza',
    since: '1991',
    specialty: 'Upscale shopping mall',
    address: 'EDSA cor. Shaw Blvd, Mandaluyong (near MRT-3 Shaw Boulevard)',
    hours: 'Daily, 11 AM – 9 PM',
    priceRange: 'Upscale retail, dining & cinemas',
    lat: 14.5817,
    lng: 121.0557,
    icon: Icons.local_mall_outlined,
    description:
        'Opened on November 21, 1991, Shangri-La Plaza has been an upscale '
        'shopping and dining landmark at the corner of EDSA and Shaw Boulevard '
        'for over 30 years. Operated by the Kuok Group, it remains one of '
        'Mandaluyong\'s premier malls, right beside MRT-3 Shaw Boulevard.',
  ),
  Eatery(
    category: 'Malls & Stores',
    name: 'Puregold (Shaw)',
    since: '1998',
    specialty: 'Supermarket & hypermart',
    address: 'Mandala Park (former Liberty Center), Shaw Blvd, Mandaluyong',
    hours: 'Daily, approx. 8 AM – 9 PM',
    priceRange: 'Affordable groceries & household goods',
    lat: 14.5807,
    lng: 121.0505,
    icon: Icons.shopping_cart_outlined,
    description:
        'Puregold was founded in 1998, and its very first store opened on '
        'December 12, 1998 along Shaw Boulevard in Mandaluyong — then Liberty '
        'Center, now Mandala Park. From this single Mandaluyong branch, the '
        'Filipino-owned retail chain led by Lucio Co grew into one of the '
        'largest supermarket chains in the country — and it all began here.',
  ),
];

class DiningPage extends StatelessWidget {
  const DiningPage({super.key});

  // Order the category sections.
  static const List<String> _order = ['Restaurants', 'Malls & Stores'];

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    final children = <Widget>[
      Container(
        padding: const EdgeInsets.all(AppSpacing.m),
        decoration: BoxDecoration(
          color: colors.tertiaryContainer,
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        child: Row(
          children: [
            Icon(Icons.storefront_outlined,
                size: 18, color: colors.onTertiaryContainer),
            const SizedBox(width: AppSpacing.s),
            Expanded(
              child: Text(
                'Iconic, long-running restaurants and stores that started and '
                'became known in Mandaluyong.',
                style: text.bodySmall
                    ?.copyWith(color: colors.onTertiaryContainer),
              ),
            ),
          ],
        ),
      ),
    ];

    for (final cat in _order) {
      final items = kEateries.where((e) => e.category == cat).toList();
      if (items.isEmpty) continue;

      children.add(Padding(
        padding: const EdgeInsets.only(top: AppSpacing.xl, bottom: AppSpacing.m),
        child: Row(
          children: [
            Container(
              width: 5,
              height: 22,
              decoration: BoxDecoration(
                color: colors.primary,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            const SizedBox(width: AppSpacing.m),
            Text(cat,
                style: text.titleMedium?.copyWith(color: colors.primary)),
          ],
        ),
      ));

      for (final e in items) {
        children.add(Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.m),
          child: _EateryCard(eatery: e),
        ));
      }
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Homegrown Mandaluyong')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.l),
        children: children,
      ),
    );
  }
}

class _EateryCard extends StatelessWidget {
  const _EateryCard({required this.eatery});
  final Eatery eatery;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => RestaurantDetailPage(eatery: eatery)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.l),
          child: Row(
            children: [
              CircleAvatar(
                radius: 26,
                backgroundColor: colors.primaryContainer,
                child: Icon(eatery.icon, color: colors.onPrimaryContainer),
              ),
              const SizedBox(width: AppSpacing.l),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(eatery.name,
                        style: text.titleSmall
                            ?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Text(eatery.specialty,
                        style: text.bodySmall?.copyWith(color: colors.primary),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 2),
                    Text(
                      eatery.since != null
                          ? 'Since ${eatery.since} · still operating'
                          : eatery.hours,
                      style: text.bodySmall?.copyWith(
                          color: colors.outline,
                          fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: colors.outline),
            ],
          ),
        ),
      ),
    );
  }
}

class RestaurantDetailPage extends StatelessWidget {
  const RestaurantDetailPage({super.key, required this.eatery});
  final Eatery eatery;

  Future<void> _launch(BuildContext context, Uri uri) async {
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open $uri')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: Text(eatery.name)),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.xl),
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 30,
                backgroundColor: colors.primaryContainer,
                child: Icon(eatery.icon,
                    size: 30, color: colors.onPrimaryContainer),
              ),
              const SizedBox(width: AppSpacing.l),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(eatery.name, style: text.headlineSmall),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.m, vertical: 4),
                      decoration: BoxDecoration(
                        color: colors.tertiaryContainer,
                        borderRadius: BorderRadius.circular(AppRadius.pill),
                      ),
                      child: Text(
                          eatery.since != null
                              ? 'Mandaluyong original · since ${eatery.since}'
                              : 'Mandaluyong original',
                          style: text.labelMedium
                              ?.copyWith(color: colors.onTertiaryContainer)),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xl),
          _InfoRow(icon: Icons.local_dining, label: eatery.specialty),
          _InfoRow(icon: Icons.place_outlined, label: eatery.address),
          _InfoRow(icon: Icons.schedule, label: eatery.hours),
          _InfoRow(icon: Icons.payments_outlined, label: eatery.priceRange),
          if (eatery.phone != null)
            _InfoRow(icon: Icons.call_outlined, label: eatery.phone!),
          const SizedBox(height: AppSpacing.l),
          Text(eatery.description,
              style: text.bodyLarge?.copyWith(height: 1.5)),
          const SizedBox(height: AppSpacing.xxl),
          Text('Location', style: text.titleMedium),
          const SizedBox(height: AppSpacing.m),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.md),
            child: SizedBox(
              height: 200,
              child: FlutterMap(
                options: MapOptions(
                  initialCenter: LatLng(eatery.lat, eatery.lng),
                  initialZoom: 16,
                ),
                children: [
                  TileLayer(
                    urlTemplate:
                        'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'com.example.be_mandaluyong',
                  ),
                  MarkerLayer(
                    markers: [
                      Marker(
                        point: LatLng(eatery.lat, eatery.lng),
                        width: 44,
                        height: 50,
                        alignment: Alignment.bottomCenter,
                        child: Icon(Icons.location_on,
                            size: 46, color: colors.primary),
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
            ),
          ),
          const SizedBox(height: AppSpacing.l),
          if (eatery.phone != null) ...[
            FilledButton.icon(
              onPressed: () => _launch(
                context,
                Uri(scheme: 'tel', path: eatery.phone!.replaceAll(' ', '')),
              ),
              icon: const Icon(Icons.call_outlined),
              style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(52)),
              label: Text('Call ${eatery.phone}'),
            ),
            const SizedBox(height: AppSpacing.m),
          ],
          OutlinedButton.icon(
            onPressed: () => _launch(
              context,
              Uri.parse(
                  'https://www.google.com/maps/search/?api=1&query=${eatery.mapsQuery}'),
            ),
            icon: const Icon(Icons.directions_outlined),
            style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(52)),
            label: const Text('Get directions'),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.s),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: colors.primary),
          const SizedBox(width: AppSpacing.m),
          Expanded(
            child: Text(label,
                style: Theme.of(context).textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }
}
