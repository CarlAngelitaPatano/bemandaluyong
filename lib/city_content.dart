import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'theme.dart'; // design tokens (AppSpacing, AppRadius)

/// A generic content item used for News, Services, Events, and Attractions.
class CityItem {
  final String title;
  final String tag; // short category label
  final String meta; // date, department, or location line
  final IconData icon;
  final String body;
  final String? image; // optional asset path, e.g. 'assets/images/...jpg'

  // Optional action data (used mainly by Services).
  final String? phone; // e.g. '8535-7357' — shows a Call button
  final String? url; // official web page — shows an Open website button
  final List<String>? steps; // requirements / how-to list

  const CityItem({
    required this.title,
    required this.tag,
    required this.meta,
    required this.icon,
    required this.body,
    this.image,
    this.phone,
    this.url,
    this.steps,
  });
}

/// A round thumbnail that shows a photo if available, otherwise an icon.
/// Missing/failed images fall back to the icon, so nothing ever breaks.
class LeadingThumb extends StatelessWidget {
  const LeadingThumb({
    super.key,
    this.image,
    required this.icon,
    this.radius = 24,
  });
  final String? image;
  final IconData icon;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final iconChild = Icon(icon, color: colors.onPrimaryContainer);
    if (image == null) {
      return CircleAvatar(
        radius: radius,
        backgroundColor: colors.primaryContainer,
        child: iconChild,
      );
    }
    return CircleAvatar(
      radius: radius,
      backgroundColor: colors.primaryContainer,
      child: ClipOval(
        child: Image.asset(
          image!,
          width: radius * 2,
          height: radius * 2,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => iconChild,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// SERVICES — based on real City of Mandaluyong departments (mandaluyong.gov.ph)
// ---------------------------------------------------------------------------
const List<CityItem> kServices = [
  CityItem(
    title: 'Business Permit (New / Renewal)',
    tag: 'Business',
    meta: 'Business Permits & Licensing Department',
    icon: Icons.storefront_outlined,
    body:
        'Any person or business operating in Mandaluyong must secure a business '
        'permit. Permits are valid for the legal owner named and expire at the '
        'end of the calendar year, so they must be renewed annually. Handled by '
        'the Business Permits and Licensing Department (BPLO).',
    phone: '8535-7357',
    url: 'https://mandaluyong.gov.ph/business/',
    steps: [
      'Prepare requirements: DTI/SEC/CDA registration, Barangay Business '
          'Clearance, lease contract or land title, and valid IDs.',
      'Apply at the BPLO (G/F Left Wing, City Hall) or online at '
          'online.mandaluyong.gov.ph.',
      'Have your application assessed for taxes and fees.',
      'Pay at the City Treasurer\'s Office (or via LBP/DBP online).',
      'Claim your Business Permit and Mayor\'s Permit.',
    ],
  ),
  CityItem(
    title: 'Civil Registry Documents',
    tag: 'Records',
    meta: 'City Civil Registry Department',
    icon: Icons.description_outlined,
    body:
        'Request certified copies of civil registry documents — Birth, '
        'Marriage, and Death certificates — and register civil events. The City '
        'Civil Registry Office handles registration under the Civil Registry Law.',
    url: 'https://mandaluyong.gov.ph/city-civil-registry-services/',
    steps: [
      'Go to the City Civil Registry Department at City Hall.',
      'Fill out the request form and present a valid ID.',
      'Provide the details of the record (name, date, place of event).',
      'Pay the required fee at the cashier.',
      'Claim the certified document (or request delivery, if available).',
    ],
  ),
  CityItem(
    title: 'City Health Services',
    tag: 'Health',
    meta: 'City Health Department',
    icon: Icons.local_hospital_outlined,
    body:
        'Health center services including medical and dental consultations, '
        'immunization, maternal and child health, and the city\'s public health '
        'programs, led by the City Health Office.',
    url: 'https://mandaluyong.gov.ph/services/',
    steps: [
      'Visit your nearest city health center or the City Health Department.',
      'Bring a valid Mandaluyong ID or proof of residency.',
      'Register at the desk and wait for your turn.',
      'Most basic services (consultation, immunization) are free.',
    ],
  ),
  CityItem(
    title: 'Sanitary & Health Permits',
    tag: 'Health',
    meta: 'Sanitation Office',
    icon: Icons.verified_outlined,
    body:
        'Issuance of Health Worker\'s Permits (Health Certificate), Sanitary '
        'Permits, Occupancy Permits, Certificate of Potability, and other '
        'health-related permits for business operations.',
    url: 'https://mandaluyong.gov.ph/services/',
    steps: [
      'Secure the medical/laboratory tests required for your permit type.',
      'Submit results and business documents to the Sanitation Office.',
      'Pay the corresponding fee.',
      'Claim your Health Certificate or Sanitary Permit.',
    ],
  ),
  CityItem(
    title: 'Real Property Tax',
    tag: 'Payments',
    meta: 'City Treasurer\'s Office',
    icon: Icons.receipt_long_outlined,
    body:
        'Pay your annual real property tax (amilyar) and settle property '
        'assessments at the City Treasurer\'s Office, or online.',
    url: 'https://online.mandaluyong.gov.ph',
    steps: [
      'Have your Tax Declaration or previous RPT receipt ready.',
      'Get your assessment at the City Treasurer\'s Office, or log in online.',
      'Pay at the cashier, or online via Land Bank (LBP) or DBP.',
      'Keep the official receipt for your records.',
    ],
  ),
  CityItem(
    title: 'Online Payments Portal',
    tag: 'Online',
    meta: 'online.mandaluyong.gov.ph',
    icon: Icons.payments_outlined,
    body:
        'The city\'s official online portal lets you register your business or '
        'property and pay taxes and fees through Land Bank (LBP) or DBP — '
        'business permits, real property tax, and more.',
    url: 'https://online.mandaluyong.gov.ph',
    steps: [
      'Go to online.mandaluyong.gov.ph and create an account.',
      'Register your business and/or property.',
      'View your assessment and pay via LBP or DBP.',
    ],
  ),
];

// ---------------------------------------------------------------------------
// NEWS — sample content (replace with live announcements later)
// ---------------------------------------------------------------------------
const List<CityItem> kNews = [
  CityItem(
    title: 'Free Medical & Dental Mission',
    tag: 'Health',
    meta: 'City Health Department',
    icon: Icons.medical_services_outlined,
    body:
        'The City Health Department invites residents to a free medical and '
        'dental mission. Services include check-ups, basic medicines, and dental '
        'extractions. Bring a valid Mandaluyong ID. (Sample announcement.)',
  ),
  CityItem(
    title: 'City Scholarship Applications Open',
    tag: 'Education',
    meta: 'City Government',
    icon: Icons.school_outlined,
    body:
        'Applications for the city scholarship program are now being accepted '
        'for qualified Mandaluyong students. Check requirements and deadlines at '
        'City Hall or the official website. (Sample announcement.)',
  ),
  CityItem(
    title: 'Road Improvement Along Boni Avenue',
    tag: 'Public Works',
    meta: 'Engineering Department',
    icon: Icons.construction_outlined,
    body:
        'Road re-blocking and drainage works are scheduled along Boni Avenue. '
        'Expect rerouting on weekends. Motorists are advised to use alternate '
        'routes. (Sample announcement.)',
  ),
  CityItem(
    title: 'Anti-Dengue Clean-Up Drive',
    tag: 'Health',
    meta: 'Barangays Citywide',
    icon: Icons.cleaning_services_outlined,
    body:
        'Join the 4 o\'clock habit and citywide clean-up to eliminate mosquito '
        'breeding sites. Residents are urged to search and destroy stagnant '
        'water around their homes. (Sample announcement.)',
  ),
];

// ---------------------------------------------------------------------------
// EVENTS — sample content (replace with the real calendar later)
// ---------------------------------------------------------------------------
const List<CityItem> kEvents = [
  // ---- JANUARY ----
  CityItem(
    title: 'Regular Monday Morning Programs',
    tag: 'Morning Program',
    meta: 'January · Weekly',
    icon: Icons.wb_sunny_outlined,
    body: 'The city\'s regular Monday morning flag and community programs.',
  ),
  CityItem(
    title: 'Sto. Niño Images Exhibit',
    tag: 'Religious Exhibit',
    meta: 'January',
    icon: Icons.museum_outlined,
    body: 'A display of Sto. Niño (Holy Child) images for the January feast.',
  ),
  // ---- FEBRUARY ----
  CityItem(
    title: 'Mandaluyong Liberation & Cityhood Anniversary',
    tag: 'Historical',
    meta: 'February',
    icon: Icons.flag_outlined,
    body: 'Commemorates the city\'s liberation and its charter as the City of '
        'Mandaluyong.',
  ),
  CityItem(
    title: 'Miss Mandaluyong Pageant',
    tag: 'Pageant',
    meta: 'February',
    icon: Icons.emoji_events_outlined,
    body: 'The city\'s flagship beauty pageant.',
  ),
  CityItem(
    title: 'Bilbiling Mandaluyong Pageant',
    tag: 'Pageant',
    meta: 'February',
    icon: Icons.emoji_events_outlined,
    body: 'A community beauty pageant held during the anniversary celebrations.',
  ),
  CityItem(
    title: 'Kasalang Bayan',
    tag: 'Community',
    meta: 'February',
    icon: Icons.favorite_outline,
    body: 'A free mass wedding for Mandaluyong couples organized by the city.',
  ),
  CityItem(
    title: 'Mandaluyong Hymn Making Contest',
    tag: 'Music',
    meta: 'February',
    icon: Icons.music_note_outlined,
    body: 'A songwriting competition celebrating the city.',
  ),
  CityItem(
    title: 'Trade Fair Exhibits',
    tag: 'Trade Fair',
    meta: 'February',
    icon: Icons.storefront_outlined,
    body: 'Local products and businesses on display.',
  ),
  CityItem(
    title: 'National Arts Month',
    tag: 'Arts',
    meta: 'February · Month-long',
    icon: Icons.palette_outlined,
    body: 'Nationwide celebration of Philippine arts.',
  ),
  // ---- MARCH / APRIL ----
  CityItem(
    title: 'Lenten Season Presentation',
    tag: 'Religious Festival',
    meta: 'March / April',
    icon: Icons.church_outlined,
    body: 'Holy Week observances including Pabasa ng Bayan, Senakulo, and '
        'Visita Iglesia.',
  ),
  CityItem(
    title: 'Carozza – Lenten Images Exhibit',
    tag: 'Religious Exhibit',
    meta: 'March / April',
    icon: Icons.museum_outlined,
    body: 'A display of carrozas and Lenten religious images.',
  ),
  CityItem(
    title: 'Araw ng Kagitingan',
    tag: 'Historical',
    meta: 'April 9',
    icon: Icons.flag_outlined,
    body: 'Day of Valor — honoring the bravery of Filipino and Allied soldiers '
        'in World War II.',
  ),
  CityItem(
    title: 'Cultural & Arts Workshop',
    tag: 'Arts',
    meta: 'March / April',
    icon: Icons.palette_outlined,
    body: 'Hands-on arts workshops for residents.',
  ),
  CityItem(
    title: 'National Women\'s Month',
    tag: 'Observance',
    meta: 'March · Month-long',
    icon: Icons.event_note_outlined,
    body: 'Nationwide celebration of women\'s achievements and rights.',
  ),
  CityItem(
    title: 'National Literature Month',
    tag: 'Arts',
    meta: 'April · Month-long',
    icon: Icons.menu_book_outlined,
    body: 'A celebration of Philippine literature.',
  ),
  CityItem(
    title: 'Flavors of NCR (Food Festival)',
    tag: 'Food Fair',
    meta: 'March / April',
    icon: Icons.restaurant_outlined,
    body: 'A food trade fair showcasing dishes of the National Capital Region '
        '(ATO-NCR).',
  ),
  // ---- MAY ----
  CityItem(
    title: 'Maytime Festivals',
    tag: 'Festival',
    meta: 'May',
    icon: Icons.local_florist_outlined,
    body: 'Santa Cruzan and Flores de Mayo processions and festivities.',
  ),
  CityItem(
    title: 'National Heritage Month',
    tag: 'Heritage',
    meta: 'May · Month-long',
    icon: Icons.account_balance_outlined,
    body: 'Celebration of the nation\'s cultural heritage.',
  ),
  // ---- JUNE ----
  CityItem(
    title: 'Araw ng Kalayaan',
    tag: 'Observance',
    meta: 'June 12',
    icon: Icons.flag_outlined,
    body: 'Philippine Independence Day.',
  ),
  CityItem(
    title: 'Dr. Jose Rizal\'s Birth Anniversary',
    tag: 'Observance',
    meta: 'June 19',
    icon: Icons.event_note_outlined,
    body: 'Marks the birth of national hero Dr. Jose Rizal.',
  ),
  CityItem(
    title: 'Filipino-Chinese Friendship Day',
    tag: 'Observance',
    meta: 'June',
    icon: Icons.handshake,
    body: 'Celebrates Filipino-Chinese friendship and shared heritage.',
  ),
  // ---- JULY ----
  CityItem(
    title: 'Saints Images Exhibit',
    tag: 'Religious Exhibit',
    meta: 'July',
    icon: Icons.museum_outlined,
    body: 'An exhibit of images of the saints.',
  ),
  CityItem(
    title: 'National Nutrition Month',
    tag: 'Observance',
    meta: 'July · Month-long',
    icon: Icons.restaurant_outlined,
    body: 'Nationwide campaign promoting good nutrition.',
  ),
  CityItem(
    title: 'National Culture Consciousness Week',
    tag: 'Observance',
    meta: 'July',
    icon: Icons.event_note_outlined,
    body: 'A week promoting awareness of Filipino culture.',
  ),
  CityItem(
    title: 'Linggo ng Musikang Pilipino',
    tag: 'Observance',
    meta: 'July',
    icon: Icons.music_note_outlined,
    body: 'A week celebrating Filipino music.',
  ),
  CityItem(
    title: 'Iglesia ni Cristo Day',
    tag: 'Observance',
    meta: 'July 27',
    icon: Icons.event_note_outlined,
    body: 'Anniversary of the registration of the Iglesia ni Cristo.',
  ),
  // ---- AUGUST ----
  CityItem(
    title: '29 de Agosto – Araw ng mga Bayani',
    tag: 'Historical',
    meta: 'August',
    icon: Icons.flag_outlined,
    body: 'National Heroes\' Day, honoring the nation\'s heroes.',
  ),
  CityItem(
    title: 'Buwan ng Wikang Pambansa',
    tag: 'Observance',
    meta: 'August · Month-long',
    icon: Icons.translate,
    body: 'National Language Month celebrating Filipino.',
  ),
  CityItem(
    title: 'National History Month',
    tag: 'Observance',
    meta: 'August · Month-long',
    icon: Icons.history_edu_outlined,
    body: 'A celebration of Philippine history.',
  ),
  // ---- SEPTEMBER ----
  CityItem(
    title: 'Our Lady of Peñafrancia Feast',
    tag: 'Religious',
    meta: 'September',
    icon: Icons.church_outlined,
    body: 'Devotion and feast in honor of Our Lady of Peñafrancia.',
  ),
  CityItem(
    title: 'National Tourism Week',
    tag: 'Observance',
    meta: 'September',
    icon: Icons.luggage_outlined,
    body: 'A week promoting Philippine tourism.',
  ),
  CityItem(
    title: 'National Literacy Day',
    tag: 'Arts',
    meta: 'September',
    icon: Icons.menu_book_outlined,
    body: 'Promotes literacy and education.',
  ),
  // ---- OCTOBER ----
  CityItem(
    title: 'Convention of Association of Tourism Officers',
    tag: 'Conference',
    meta: 'October · Annual',
    icon: Icons.groups_outlined,
    body: 'Annual gathering of the Association of Tourism Officers.',
  ),
  CityItem(
    title: 'Marian Images Exhibit',
    tag: 'Religious Exhibit',
    meta: 'October',
    icon: Icons.museum_outlined,
    body: 'An exhibit of images of the Blessed Virgin Mary.',
  ),
  CityItem(
    title: 'Museums and Galleries Month',
    tag: 'Observance',
    meta: 'October · Month-long',
    icon: Icons.museum_outlined,
    body: 'Celebrating the nation\'s museums and galleries.',
  ),
  CityItem(
    title: 'National Archives Day',
    tag: 'Observance',
    meta: 'October',
    icon: Icons.event_note_outlined,
    body: 'Recognizes the importance of public archives.',
  ),
  // ---- NOVEMBER ----
  CityItem(
    title: 'All Souls\' Day',
    tag: 'Religious',
    meta: 'November 1–2',
    icon: Icons.church_outlined,
    body: 'Remembrance of the faithful departed.',
  ),
  CityItem(
    title: 'Lavandero Festival',
    tag: 'City Festival',
    meta: 'November',
    icon: Icons.celebration_outlined,
    body: 'Mandaluyong\'s signature festival celebrating its heritage as a '
        'community of lavanderas (laundry folk).',
  ),
  CityItem(
    title: 'Pistang Daluyong',
    tag: 'City Festival',
    meta: 'November',
    icon: Icons.celebration_outlined,
    body: 'A cultural city festival of Mandaluyong.',
  ),
  CityItem(
    title: 'Library and Information Services Month',
    tag: 'Observance',
    meta: 'November · Month-long',
    icon: Icons.local_library_outlined,
    body: 'Celebrating libraries and information services.',
  ),
  CityItem(
    title: 'Bonifacio Day',
    tag: 'Observance',
    meta: 'November 30',
    icon: Icons.flag_outlined,
    body: 'Honors revolutionary hero Andrés Bonifacio.',
  ),
  // ---- DECEMBER ----
  CityItem(
    title: 'Paskuhan sa Lungsod',
    tag: 'Christmas',
    meta: 'December · Citywide',
    icon: Icons.celebration_outlined,
    body: 'Citywide Christmas festivities, including Daluyong sa Mandaluyong '
        'and the Christmas Parol Contest.',
  ),
  CityItem(
    title: 'Rizal Day',
    tag: 'Observance',
    meta: 'December 30',
    icon: Icons.event_note_outlined,
    body: 'Commemorates the martyrdom of Dr. Jose Rizal.',
  ),
];

// ---------------------------------------------------------------------------
// Shared widgets
// ---------------------------------------------------------------------------
class CityCard extends StatelessWidget {
  const CityCard({super.key, required this.item});
  final CityItem item;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => CityDetailPage(item: item)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.l),
          child: Row(
            children: [
              LeadingThumb(image: item.image, icon: item.icon),
              const SizedBox(width: AppSpacing.l),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      item.meta,
                      style: text.bodySmall?.copyWith(color: colors.outline),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.s),
              _Tag(label: item.tag),
            ],
          ),
        ),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.m, vertical: 6),
      decoration: BoxDecoration(
        color: colors.secondaryContainer,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: colors.onSecondaryContainer,
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class CityDetailPage extends StatelessWidget {
  const CityDetailPage({super.key, required this.item});
  final CityItem item;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(item.tag)),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.xl),
        children: [
          if (item.image != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.md),
              child: Image.asset(
                item.image!,
                height: 180,
                width: double.infinity,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => CircleAvatar(
                  radius: 32,
                  backgroundColor: colors.primaryContainer,
                  child:
                      Icon(item.icon, size: 32, color: colors.onPrimaryContainer),
                ),
              ),
            )
          else
            CircleAvatar(
              radius: 32,
              backgroundColor: colors.primaryContainer,
              child: Icon(item.icon, size: 32, color: colors.onPrimaryContainer),
            ),
          const SizedBox(height: AppSpacing.l),
          Text(
            item.title,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: AppSpacing.s),
          Row(
            children: [
              Icon(Icons.place_outlined, size: 16, color: colors.outline),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  item.meta,
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: colors.outline),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xl),
          Text(item.body, style: Theme.of(context).textTheme.bodyLarge),

          // Requirements / how-to steps (mainly for Services)
          if (item.steps != null && item.steps!.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xxl),
            Text('Requirements & steps',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: AppSpacing.m),
            for (int i = 0; i < item.steps!.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.m),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CircleAvatar(
                      radius: 12,
                      backgroundColor: colors.primaryContainer,
                      child: Text('${i + 1}',
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: colors.onPrimaryContainer)),
                    ),
                    const SizedBox(width: AppSpacing.m),
                    Expanded(
                      child: Text(item.steps![i],
                          style: Theme.of(context).textTheme.bodyMedium),
                    ),
                  ],
                ),
              ),
          ],

          // Action buttons — call the office / open the official website
          if (item.phone != null || item.url != null) ...[
            const SizedBox(height: AppSpacing.l),
            if (item.phone != null)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.m),
                child: FilledButton.icon(
                  onPressed: () =>
                      _launch(context, Uri(scheme: 'tel', path: item.phone!)),
                  icon: const Icon(Icons.call_outlined),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                  ),
                  label: Text('Call ${item.phone}'),
                ),
              ),
            if (item.url != null)
              OutlinedButton.icon(
                onPressed: () => _launch(context, Uri.parse(item.url!)),
                icon: const Icon(Icons.open_in_new),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                ),
                label: const Text('Open official website'),
              ),
          ],
        ],
      ),
    );
  }

  Future<void> _launch(BuildContext context, Uri uri) async {
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open $uri')),
      );
    }
  }
}

/// A reusable list screen for News / Services / Events.
class CityListPage extends StatelessWidget {
  const CityListPage({
    super.key,
    required this.title,
    required this.items,
    this.note,
  });

  final String title;
  final List<CityItem> items;
  final String? note; // optional banner (e.g. "Sample content")

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.l),
        children: [
          if (note != null) ...[
            Container(
              padding: const EdgeInsets.all(AppSpacing.m),
              decoration: BoxDecoration(
                color: colors.tertiaryContainer,
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline,
                      size: 18, color: colors.onTertiaryContainer),
                  const SizedBox(width: AppSpacing.s),
                  Expanded(
                    child: Text(
                      note!,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: colors.onTertiaryContainer,
                          ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.l),
          ],
          for (final item in items) ...[
            CityCard(item: item),
            const SizedBox(height: AppSpacing.m),
          ],
        ],
      ),
    );
  }
}

// Convenience pages wired to the home cards.
// NewsPage now lives in news_page.dart (live Google News feed).

class ServicesPage extends StatelessWidget {
  const ServicesPage({super.key});
  @override
  Widget build(BuildContext context) => const CityListPage(
        title: 'City Services',
        items: kServices,
      );
}

/// Month sections for the events calendar, in the same order as [kEvents].
/// Each entry is (month label, number of events that month). If you add or
/// remove events above, keep these counts in sync.
const List<(String, int)> kEventMonths = [
  ('January', 2),
  ('February', 7),
  ('March – April', 7),
  ('May', 2),
  ('June', 3),
  ('July', 5),
  ('August', 3),
  ('September', 3),
  ('October', 4),
  ('November', 5),
  ('December', 2),
];

class EventsPage extends StatelessWidget {
  const EventsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final children = <Widget>[
      // Source note
      Container(
        padding: const EdgeInsets.all(AppSpacing.m),
        decoration: BoxDecoration(
          color: colors.tertiaryContainer,
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        child: Row(
          children: [
            Icon(Icons.event_available_outlined,
                size: 18, color: colors.onTertiaryContainer),
            const SizedBox(width: AppSpacing.s),
            Expanded(
              child: Text(
                'Mandaluyong City Cultural Affairs & Tourism — '
                '2026 Calendar of Activities.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colors.onTertiaryContainer,
                    ),
              ),
            ),
          ],
        ),
      ),
    ];

    // Build month sections by slicing kEvents in order.
    var i = 0;
    for (final (label, count) in kEventMonths) {
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
              label,
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(color: colors.primary),
            ),
          ],
        ),
      ));
      for (var j = 0; j < count && i < kEvents.length; j++, i++) {
        children.add(Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.m),
          child: CityCard(item: kEvents[i]),
        ));
      }
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Events')),
      body: ListView(
          padding: const EdgeInsets.all(AppSpacing.l), children: children),
    );
  }
}
