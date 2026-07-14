import 'package:flutter/material.dart';

import 'city_content.dart'; // reuses CityItem + CityCard + CityDetailPage
import 'theme.dart'; // design tokens (AppSpacing, AppRadius)

// ---------------------------------------------------------------------------
// Tourist Attractions of Mandaluyong (official categorized list).
//
// SEPARATE from the Heritage Church Trail (the app's main feature). The five
// churches that make up the trail — San Felipe Neri, San Roque de Mandaluyong,
// St. Francis of Assisi, St. Dominic Savio, and the Divine Mercy shrine — are
// intentionally NOT repeated here; they live only in the Heritage section.
// ---------------------------------------------------------------------------
const List<CityItem> kAttractions = [
  // ===== Heritage Sites / Structures (extras only) =====
  CityItem(
    title: 'Villa San Miguel (Archbishop\'s Residence)',
    tag: 'Heritage Sites',
    meta: 'Shaw Boulevard',
    icon: Icons.account_balance_outlined,
    image: 'assets/images/attractions/villa_san_miguel.jpg',
    body: 'The official residence of the Archbishop of Manila — a notable '
        'heritage compound, home to the Archbishop\'s chapels.',
  ),
  CityItem(
    title: 'Nawasa Old Water Tank',
    tag: 'Heritage Sites',
    meta: 'Mandaluyong City',
    icon: Icons.water_drop_outlined,
    image: 'assets/images/attractions/nawasa_water_tank.jpg',
    body: 'A historic water tank from the NAWASA era — a surviving piece of '
        'the city\'s utility heritage.',
  ),

  // ===== Historical Sites / Landmarks / Monuments =====
  CityItem(
    title: 'Tatlong Bayani Statue',
    tag: 'Historical & Monuments',
    meta: 'Brgy. Hagdang Bato',
    icon: Icons.military_tech_outlined,
    image: 'assets/images/attractions/tatlong_bayani.jpg',
    body: 'A statue honoring three heroes — a historical landmark of the city.',
  ),
  CityItem(
    title: 'Liberation Marker',
    tag: 'Historical & Monuments',
    meta: 'Brgy. Pag-Asa',
    icon: Icons.flag_outlined,
    image: 'assets/images/attractions/liberation_marker.jpg',
    body: 'A marker commemorating the liberation of Mandaluyong at the end of '
        'World War II.',
  ),
  CityItem(
    title: 'Dambana ng Ala-Ala',
    tag: 'Historical & Monuments',
    meta: 'Mandaluyong City',
    icon: Icons.account_balance_outlined,
    image: 'assets/images/attractions/dambana_ala_ala.jpg',
    body: 'A shrine of remembrance honoring those who shaped the city\'s '
        'history.',
  ),
  CityItem(
    title: 'Dove of Peace',
    tag: 'Historical & Monuments',
    meta: 'Mandaluyong City',
    icon: Icons.volunteer_activism_outlined,
    image: 'assets/images/attractions/dove_of_peace.jpg',
    body: 'A monument symbolizing peace in the community.',
  ),
  CityItem(
    title: 'Bantayog ng Kabataan',
    tag: 'Historical & Monuments',
    meta: 'Mandaluyong City',
    icon: Icons.groups_outlined,
    image: 'assets/images/attractions/bantayog_kabataan.jpg',
    body: 'A monument dedicated to the Filipino youth.',
  ),

  // ===== Institutions =====
  CityItem(
    title: 'National Center for Mental Health',
    tag: 'Institutions',
    meta: 'Brgy. Mauway',
    icon: Icons.local_hospital_outlined,
    image: 'assets/images/attractions/ncmh.jpg',
    body: 'The Philippines\' largest government psychiatric facility and a '
        'major institutional landmark in the city.',
  ),
  CityItem(
    title: 'Correctional Institution for Women',
    tag: 'Institutions',
    meta: 'Brgy. Addition Hills',
    icon: Icons.gavel_outlined,
    image: 'assets/images/attractions/ciw.jpg',
    body: 'The national correctional facility for women — a historic '
        'government institution in Mandaluyong.',
  ),
  CityItem(
    title: 'Asian Development Bank (ADB)',
    tag: 'Institutions',
    meta: 'ADB Ave., Ortigas Center',
    icon: Icons.account_balance_outlined,
    image: 'assets/images/attractions/adb.jpg',
    lat: 14.5881,
    lng: 121.0582,
    body: 'The headquarters of the Asian Development Bank, a major '
        'international institution based in Mandaluyong.',
  ),
  CityItem(
    title: 'Wack-Wack Golf & Country Club',
    tag: 'Institutions',
    meta: 'Brgy. Wack-Wack',
    icon: Icons.sports_golf,
    image: 'assets/images/attractions/wackwack_golf.jpg',
    lat: 14.5931,
    lng: 121.0496,
    body: 'One of the oldest and most prestigious golf and country clubs in '
        'the Philippines.',
  ),
  CityItem(
    title: 'San Miguel Main Office',
    tag: 'Institutions',
    meta: 'Brgy. Wack-Wack',
    icon: Icons.business_outlined,
    image: 'assets/images/attractions/san_miguel_hq.jpg',
    lat: 14.5817,
    lng: 121.0582,
    body: 'The head office of San Miguel Corporation, one of the largest '
        'conglomerates in the Philippines.',
  ),

  // ===== Schools =====
  CityItem(
    title: 'Don Bosco Technical College',
    tag: 'Schools',
    meta: 'Brgy. Pag-Asa',
    icon: Icons.school_outlined,
    image: 'assets/images/attractions/don_bosco_college.jpg',
    body: 'A Salesian technical college, long associated with the Don Bosco '
        'community in the city.',
  ),
  CityItem(
    title: 'Jose Rizal University',
    tag: 'Schools',
    meta: 'Shaw Boulevard',
    icon: Icons.school_outlined,
    image: 'assets/images/attractions/jru.jpg',
    body: 'A long-established private university along Shaw Boulevard.',
  ),
  CityItem(
    title: 'Rizal Technological University',
    tag: 'Schools',
    meta: 'Boni Avenue',
    icon: Icons.school_outlined,
    image: 'assets/images/attractions/rtu.jpg',
    body: 'A state university known for its engineering and technology '
        'programs.',
  ),
  CityItem(
    title: 'La Salle Greenhills',
    tag: 'Schools',
    meta: 'Ortigas Avenue',
    icon: Icons.school_outlined,
    image: 'assets/images/attractions/lasalle_greenhills.jpg',
    lat: 14.5969,
    lng: 121.0551,
    body: 'A prominent Catholic school run by the De La Salle Brothers.',
  ),
  CityItem(
    title: 'Lourdes School of Mandaluyong',
    tag: 'Schools',
    meta: 'Brgy. Wack-Wack',
    icon: Icons.school_outlined,
    image: 'assets/images/attractions/lourdes_school.jpg',
    body: 'A well-known Catholic school in the city.',
  ),
  CityItem(
    title: 'Arellano University – Plaridel',
    tag: 'Schools',
    meta: 'Plaridel St.',
    icon: Icons.school_outlined,
    image: 'assets/images/attractions/arellano_plaridel.jpg',
    body: 'The Plaridel campus of Arellano University.',
  ),
  CityItem(
    title: 'Mandaluyong Elementary School',
    tag: 'Schools',
    meta: 'Mandaluyong City',
    icon: Icons.school_outlined,
    image: 'assets/images/attractions/mandaluyong_elementary.jpg',
    body: 'A public elementary school serving the city.',
  ),

  // ===== Parks =====
  CityItem(
    title: 'Hardin ng Pag-Asa',
    tag: 'Parks',
    meta: 'Brgy. Pag-Asa',
    icon: Icons.park_outlined,
    image: 'assets/images/attractions/hardin_pag_asa.jpg',
    body: 'A community garden park in Barangay Pag-Asa.',
  ),
  CityItem(
    title: 'Vergara Linear Park',
    tag: 'Parks',
    meta: 'Brgy. Barangka',
    icon: Icons.park_outlined,
    image: 'assets/images/attractions/vergara_linear_park.jpg',
    body: 'A landscaped linear park in the Vergara area.',
  ),
  CityItem(
    title: 'Garden of Life Park',
    tag: 'Parks',
    meta: 'Mandaluyong City',
    icon: Icons.park_outlined,
    image: 'assets/images/attractions/garden_of_life.jpg',
    body: 'A green open space and memorial garden in the city.',
  ),

  // ===== Shopping & Leisure =====
  CityItem(
    title: 'SM Megamall',
    tag: 'Shopping & Leisure',
    meta: 'EDSA, Brgy. Wack-Wack',
    icon: Icons.shopping_bag_outlined,
    image: 'assets/images/attractions/sm_megamall.jpg',
    lat: 14.5852,
    lng: 121.0566,
    body: 'One of the largest shopping malls in the Philippines, located '
        'along EDSA in Mandaluyong.',
  ),
  CityItem(
    title: 'Shangri-La Plaza Mall',
    tag: 'Shopping & Leisure',
    meta: 'EDSA cor. Shaw Blvd.',
    icon: Icons.shopping_bag_outlined,
    image: 'assets/images/attractions/shangrila_plaza.jpg',
    lat: 14.5820,
    lng: 121.0554,
    body: 'An upscale shopping mall at the corner of EDSA and Shaw Boulevard, '
        'near MRT-3 Shaw Boulevard.',
  ),
  CityItem(
    title: 'The Podium',
    tag: 'Shopping & Leisure',
    meta: 'ADB Avenue, Ortigas',
    icon: Icons.shopping_bag_outlined,
    image: 'assets/images/attractions/the_podium.jpg',
    lat: 14.5851,
    lng: 121.0591,
    body: 'A premium shopping mall along ADB Avenue in the Ortigas area.',
  ),
  CityItem(
    title: 'Greenfield District Central Park',
    tag: 'Shopping & Leisure',
    meta: 'Brgy. Highway Hills',
    icon: Icons.park_outlined,
    image: 'assets/images/attractions/greenfield_park.jpg',
    body: 'An open park and events space at the heart of the Greenfield '
        'District, host to concerts, markets, and community gatherings.',
  ),
];

/// Order in which attraction categories are shown.
const List<String> _attractionTypes = [
  'Heritage Sites',
  'Historical & Monuments',
  'Institutions',
  'Schools',
  'Parks',
  'Shopping & Leisure',
];

/// Tourist attractions screen, grouped by category. Kept separate from Heritage.
class AttractionsPage extends StatelessWidget {
  const AttractionsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    final children = <Widget>[
      Container(
        padding: const EdgeInsets.all(AppSpacing.m),
        decoration: BoxDecoration(
          color: colors.tertiaryContainer,
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        child: Row(
          children: [
            Icon(Icons.photo_camera_outlined,
                size: 18, color: colors.onTertiaryContainer),
            const SizedBox(width: AppSpacing.s),
            Expanded(
              child: Text(
                'Official list of tourist attractions in Mandaluyong City. '
                'Heritage churches in the trail are featured separately.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colors.onTertiaryContainer,
                    ),
              ),
            ),
          ],
        ),
      ),
    ];

    for (final type in _attractionTypes) {
      final items = kAttractions.where((a) => a.tag == type).toList();
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
            Text(
              type,
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(color: colors.primary),
            ),
          ],
        ),
      ));

      for (final item in items) {
        children.add(Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.m),
          child: CityCard(item: item),
        ));
      }
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Tourist Attractions')),
      body: ListView(
          padding: const EdgeInsets.all(AppSpacing.l), children: children),
    );
  }
}
