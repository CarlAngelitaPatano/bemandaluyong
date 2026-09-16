import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'email_service.dart';
import 'city_content.dart'; // for the shared LeadingThumb widget
import 'theme.dart'; // design tokens (AppTheme.success, AppSpacing, AppRadius)
import 'achievements.dart'; // trail badges + unlock celebration
import 'motion.dart'; // Reveal / PopIn animations
import 'tcims_api.dart'; // shared TCIMS backend (MySQL) — trail check-ins
import 'user_profile.dart'; // date of birth / minimum trail age

/// A heritage church in Mandaluyong.
class Church {
  final String name;
  final String era; // short label, e.g. "Established 1863"
  final String location; // address / district
  final String nearest; // nearest landmark or MRT station
  final String description;
  final String? image; // optional asset path
  final double lat; // latitude of the church (for GPS check-in)
  final double lng; // longitude of the church (for GPS check-in)

  /// True when the coordinates were taken from OpenStreetMap (building-accurate).
  /// False = approximate area position that should be confirmed on-site.
  final bool coordVerified;

  const Church({
    required this.name,
    required this.era,
    required this.location,
    required this.nearest,
    required this.description,
    required this.lat,
    required this.lng,
    this.coordVerified = false,
    this.image,
  });

  /// Expected 3D model path for AR, derived from the image filename
  /// (e.g. assets/models/san_felipe_neri.glb). The file may not exist yet —
  /// the AR page falls back to a sample model until you add it.
  String? get model {
    final img = image;
    if (img == null) return null;
    return img
        .replaceFirst('/images/churches/', '/models/')
        .replaceFirst('.jpg', '.glb');
  }
}

/// Real heritage / notable churches of Mandaluyong, in trail order.
/// (Sources: San Felipe Neri Parish, RCAM, Mandaluyong Visita Iglesia guides.)
const List<Church> kChurches = [
  Church(
    name: 'San Felipe Neri Parish Church',
    image: 'assets/images/churches/san_felipe_neri.jpg',
    lat: 14.585933,
    lng: 121.026634,
    coordVerified: true,
    era: 'Established 1863 · Oldest in the city',
    location: 'Boni Ave. cor. Aglipay St., Poblacion',
    nearest: 'MRT-3 Boni Avenue',
    description:
        'The oldest and largest church in Mandaluyong. The city itself was '
        'once named San Felipe Neri, after the patron saint, before it was '
        'renamed Mandaluyong. The cornerstone was blessed in 1870 under the '
        'title La Purísima Concepción. It is known for its Neo-Gothic facade '
        'with twin bell towers and a semicircular arched entrance, and it '
        'houses a relic of St. Philip Neri. The church witnessed events from '
        'the Philippine Revolution to World War II.',
  ),
  Church(
    name: 'Archdiocesan Shrine of the Divine Mercy',
    image: 'assets/images/churches/divine_mercy.jpg',
    lat: 14.577360,
    lng: 121.035930,
    era: 'Pilgrimage shrine',
    location: 'Maysilo Circle, near Mandaluyong City Hall',
    nearest: 'Mandaluyong City Hall',
    description:
        'A well-loved pilgrimage shrine devoted to the Divine Mercy, set '
        'beside the historic Maysilo Circle at the civic heart of the city. '
        'A popular stop for prayer and reflection, especially during Lent.',
  ),
  Church(
    name: 'San Roque de Barangka Parish Church',
    image: 'assets/images/churches/san_roque_barangka.jpg',
    lat: 14.583900,
    lng: 121.034300,
    era: 'Historic riverside district',
    location: 'Barangka, Mandaluyong',
    nearest: 'MRT-3 Boni Avenue',
    description:
        'A parish rooted in the old Barangka district along the Pasig River, '
        'one of the historic riverside communities of Mandaluyong. Dedicated '
        'to San Roque, long invoked by Filipinos for protection from illness.',
  ),
  Church(
    name: 'St. Francis of Assisi Parish Church',
    image: 'assets/images/churches/st_francis_assisi.jpg',
    lat: 14.582000,
    lng: 121.050500,
    era: 'Franciscan heritage',
    location: 'Behind Shangri-La Plaza, Ortigas area',
    nearest: 'MRT-3 Shaw Boulevard',
    description:
        'A quiet parish tucked behind the malls near Shaw Boulevard, named '
        'for St. Francis of Assisi — a nod to the Franciscan friars who '
        'established the early churches of this part of Manila.',
  ),
  Church(
    name: 'St. Dominic Savio Parish Church',
    image: 'assets/images/churches/st_dominic_savio.jpg',
    lat: 14.590579,
    lng: 121.027544,
    coordVerified: true,
    era: 'Salesian community',
    location: 'Pag-Asa St., beside Don Bosco',
    nearest: 'Marketplace Mall',
    description:
        'A parish beside the Salesian Don Bosco Technical College, named for '
        'the young saint Dominic Savio. A center of the Don Bosco community '
        'and its schools in Mandaluyong.',
  ),
  Church(
    name: 'Santuario de San Jose Parish Church',
    image: 'assets/images/churches/santuario_san_jose.jpg',
    lat: 14.600160,
    lng: 121.052963,
    coordVerified: true,
    era: 'Devoted to St. Joseph',
    location: 'Mandaluyong City',
    nearest: 'Mandaluyong City',
    description:
        'A parish church dedicated to St. Joseph, serving its community in '
        'Mandaluyong.',
  ),
  Church(
    name: 'Our Lady of the Abandoned Parish',
    image: 'assets/images/churches/our_lady_abandoned.jpg',
    lat: 14.569800,
    lng: 121.037100,
    era: 'Marian parish',
    location: 'Mandaluyong City',
    nearest: 'Mandaluyong City',
    description:
        'A parish devoted to Our Lady of the Abandoned '
        '(Nuestra Señora de los Desamparados).',
  ),
  Church(
    name: 'Our Lady of Fatima Parish Church',
    image: 'assets/images/churches/our_lady_fatima.jpg',
    lat: 14.579000,
    lng: 121.044000,
    era: 'Marian parish',
    location: 'Liko St. cor. Mariveles St.',
    nearest: 'Mandaluyong City',
    description:
        'A parish church devoted to Our Lady of Fatima.',
  ),
  Church(
    name: 'Sacred Heart of Jesus Parish Church',
    image: 'assets/images/churches/sacred_heart.jpg',
    lat: 14.572674,
    lng: 121.037133,
    coordVerified: true,
    era: 'Welfareville community',
    location: 'Welfareville Compound',
    nearest: 'Mandaluyong City',
    description:
        'A parish church in the Welfareville area devoted to the Sacred Heart '
        'of Jesus.',
  ),
];

// ---------------------------------------------------------------------------
// Reusable cards
// ---------------------------------------------------------------------------

/// Full-width church card used in lists.
class ChurchCard extends StatelessWidget {
  const ChurchCard({super.key, required this.church});
  final Church church;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => ChurchDetailPage(church: church)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.l),
          child: Row(
            children: [
              LeadingThumb(
                image: church.image,
                icon: Icons.church,
                radius: 26,
              ),
              const SizedBox(width: AppSpacing.l),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      church.name,
                      style: Theme.of(context)
                          .textTheme
                          .titleSmall
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      church.era,
                      style: TextStyle(
                          color: colors.primary,
                          fontSize: 13,
                          fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Icon(Icons.location_on_outlined,
                            size: 14, color: colors.outline),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            church.location,
                            style: TextStyle(color: colors.outline, fontSize: 12),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
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

/// Compact card for the horizontal "featured" row on the dashboard.
class FeaturedChurchCard extends StatelessWidget {
  const FeaturedChurchCard({super.key, required this.church});
  final Church church;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return SizedBox(
      width: 200,
      child: Card(
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => ChurchDetailPage(church: church)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Decorative header band
              Container(
                height: 80,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [colors.primary, colors.primaryContainer],
                  ),
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(AppRadius.lg),
                  ),
                ),
                child: church.image == null
                    ? const Center(
                        child: Icon(Icons.church, color: Colors.white, size: 36),
                      )
                    : ClipRRect(
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(AppRadius.lg),
                        ),
                        child: Image.asset(
                          church.image!,
                          height: 80,
                          width: double.infinity,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => const Center(
                            child: Icon(Icons.church,
                                color: Colors.white, size: 36),
                          ),
                        ),
                      ),
              ),
              Padding(
                padding: const EdgeInsets.all(AppSpacing.m),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      church.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style:
                          text.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      church.era,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.bodySmall?.copyWith(
                          color: colors.primary, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// The heritage churches list.
//
// [HeritageChurchesView] is the bare content (no Scaffold), kept for anywhere
// that already supplies its own frame. [HeritageChurchesPage] wraps it in a
// screen with an app bar, which is what the Services menu opens.
// ---------------------------------------------------------------------------
class HeritageChurchesPage extends StatelessWidget {
  const HeritageChurchesPage({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Heritage Trail')),
        body: const HeritageChurchesView(),
      );
}

class HeritageChurchesView extends StatelessWidget {
  const HeritageChurchesView({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Reveal(
          delayMs: 0,
          child: Text(
            'Heritage Churches',
            style: Theme.of(context).textTheme.headlineSmall
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
        ),
        const SizedBox(height: 4),
        const Reveal(
            delayMs: 40, child: Text('Historic churches of Mandaluyong')),
        const SizedBox(height: 16),

        // Trail call-to-action — springs in to draw the eye
        PopIn(delayMs: 120, child: _TrailBanner()),
        const SizedBox(height: 16),

        // All churches cascade in one after another
        for (int i = 0; i < kChurches.length; i++) ...[
          Reveal(
            delayMs: 220 + i * 60,
            child: ChurchCard(church: kChurches[i]),
          ),
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}

/// A banner that opens the trail.
class _TrailBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const HeritageTrailPage()),
      ),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          // Fixed navy gradient so the white text is always readable, in
          // light and dark mode alike.
          gradient: const LinearGradient(
            colors: [Color(0xFF12305F), Color(0xFF1E4B8F)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          children: [
            const Icon(Icons.map_outlined, color: Colors.white, size: 40),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Heritage Church Trail',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 17,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'A self-guided walk through ${kChurches.length} historic churches',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.9),
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward, color: Colors.white),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Church detail page
// ---------------------------------------------------------------------------
class ChurchDetailPage extends StatelessWidget {
  const ChurchDetailPage({super.key, required this.church});
  final Church church;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 180,
            pinned: true,
            flexibleSpace: FlexibleSpaceBar(
              title: Text(
                church.name,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
              ),
              background: Stack(
                fit: StackFit.expand,
                children: [
                  church.image == null
                      ? Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [colors.primary, colors.primaryContainer],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                          ),
                          child: const Center(
                            child: Icon(Icons.church,
                                color: Colors.white, size: 64),
                          ),
                        )
                      : Image.asset(
                          church.image!,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  colors.primary,
                                  colors.primaryContainer
                                ],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                            ),
                            child: const Center(
                              child: Icon(Icons.church,
                                  color: Colors.white, size: 64),
                            ),
                          ),
                        ),
                  // Dark scrim so the white title stays readable on any photo
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.center,
                        end: Alignment.bottomCenter,
                        colors: [Colors.transparent, Colors.black54],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.all(20),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _InfoChip(icon: Icons.history, label: church.era),
                    _InfoChip(icon: Icons.train_outlined, label: church.nearest),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Icon(Icons.location_on_outlined, color: colors.primary),
                    const SizedBox(width: 8),
                    Expanded(child: Text(church.location)),
                  ],
                ),
                const SizedBox(height: 20),
                Text(
                  'About',
                  style: Theme.of(context).textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  church.description,
                  style: const TextStyle(height: 1.5),
                ),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: AppSpacing.m, vertical: AppSpacing.s),
      decoration: BoxDecoration(
        color: colors.secondaryContainer,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: colors.onSecondaryContainer),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: colors.onSecondaryContainer,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Heritage Church Trail — numbered, ordered stops
// ---------------------------------------------------------------------------
/// Tracks which churches the user has marked as visited.
///
/// In-memory: it persists while the app is running but resets on restart.
/// Saving it permanently is a quick next step with the shared_preferences
/// package.
class TrailProgress {
  TrailProgress._();

  // Storage keys are scoped to the signed-in account.
  //
  // They were once plain 'verified_churches' and 'church_proofs' — one key
  // shared by everyone who used the phone. Signing out and signing in as
  // somebody else loaded the previous person's trail, and the next sync
  // pushed their check-ins up under the new account. Anyone testing on one
  // handset saw it as accounts bleeding into each other.
  //
  // The uid keeps them apart. Signed out, nothing is written at all.
  static String? _uid() => FirebaseAuth.instance.currentUser?.uid;
  static String? _visitedKeyFor() {
    final uid = _uid();
    return uid == null ? null : 'verified_churches_$uid';
  }

  static String? _proofsKeyFor() {
    final uid = _uid();
    return uid == null ? null : 'church_proofs_$uid';
  }

  /// Churches verified by submitting photo proof.
  static final Set<String> visited = <String>{};

  /// Photo-proof file paths submitted per church.
  static final Map<String, List<String>> proofs = <String, List<String>>{};

  static bool isVisited(Church c) => visited.contains(c.name);
  static bool get isComplete =>
      kChurches.isNotEmpty && visited.length >= kChurches.length;

  /// Loads this account's saved progress. Call after sign-in and at startup.
  ///
  /// Always starts by emptying what is in memory: these are static fields that
  /// outlive a sign-out, so without the clear, a second account would inherit
  /// whatever the first had left behind.
  static Future<void> load() async {
    visited.clear();
    proofs.clear();

    final visitedKey = _visitedKeyFor();
    final proofsKey = _proofsKeyFor();
    if (visitedKey == null || proofsKey == null) return; // signed out

    final prefs = await SharedPreferences.getInstance();
    visited.addAll(prefs.getStringList(visitedKey) ?? const []);
    final raw = prefs.getString(proofsKey);
    if (raw != null) {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      decoded.forEach((key, value) {
        proofs[key] = (value as List).cast<String>();
      });
    }
  }

  /// Forgets this device's copy of the trail, in memory and on disk.
  /// Used on sign-out; the account's real progress stays on the server.
  static Future<void> clear() async {
    visited.clear();
    proofs.clear();
    final visitedKey = _visitedKeyFor();
    final proofsKey = _proofsKeyFor();
    final prefs = await SharedPreferences.getInstance();
    if (visitedKey != null) await prefs.remove(visitedKey);
    if (proofsKey != null) await prefs.remove(proofsKey);
    // The old shared keys, from before progress was scoped per account.
    await prefs.remove('verified_churches');
    await prefs.remove('church_proofs');
  }

  static Future<void> _save() async {
    final visitedKey = _visitedKeyFor();
    final proofsKey = _proofsKeyFor();
    if (visitedKey == null || proofsKey == null) return; // signed out
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(visitedKey, visited.toList());
    await prefs.setString(proofsKey, jsonEncode(proofs));
  }

  /// Merges this device's progress with the account's progress in the shared
  /// MySQL database (api/visits.php), so the trail is the same on the app and
  /// the CCAT website. Call after login (and at startup for a remembered
  /// session).
  static Future<void> syncWithCloud() async {
    // Pull anything verified on another platform (e.g. the website).
    //
    // ?verified=1 matters. Without it the endpoint also returns casual
    // "check in" taps made from the website's Explore page — no GPS, no photo
    // proof. Counting those would let someone tap their way to a complete
    // trail in the app, and the backend's own reward gate gets it right, so
    // the app would promise a mug the server then refuses to issue.
    final remoteRaw = await TcimsApi.get('/api/visits.php?verified=1');
    final remote =
        (remoteRaw is List) ? remoteRaw.cast<String>().toSet() : <String>{};
    if (remote.isNotEmpty) {
      final before = visited.length;
      visited.addAll(remote); // union — nothing is ever lost
      if (visited.length != before) await _save();
    }
    // Push anything verified ONLY on this device (it has local photo proof
    // but the server doesn't know about it — e.g. verified while offline).
    // Best-effort: if the proof photos are gone from disk, that stop is
    // skipped until it is re-verified.
    for (final name in visited) {
      if (remote.contains(name)) continue;
      final photos = proofs[name];
      if (photos == null || photos.length < 2) continue;
      if (!await File(photos[0]).exists()) continue;
      if (!await File(photos[1]).exists()) continue;
      await TcimsApi.postMultipart(
        '/api/checkin.php',
        fields: {'place': name},
        files: {'selfie': photos[0], 'site': photos[1]},
      );
    }
  }

  /// Marks a church verified once the required photo proof is provided,
  /// saves it locally, and records the check-in (with photo proof) on the
  /// shared backend — this is what makes it appear on the website too.
  ///
  /// Returns true when the backend accepted the check-in. A false result is
  /// NOT a failure to verify: the visit is already saved on the device and
  /// [syncWithCloud] will push it the next time the app has a connection. The
  /// caller uses the answer only to be honest about what has happened so far,
  /// rather than claiming the office has it when it may not yet.
  static Future<bool> markVerified(Church c, List<String> photoPaths) async {
    proofs[c.name] = photoPaths;
    visited.add(c.name);
    await _save();
    if (photoPaths.length < 2) return false;
    final result = await TcimsApi.postMultipart(
      '/api/checkin.php',
      fields: {'place': c.name},
      files: {'selfie': photoPaths[0], 'site': photoPaths[1]},
    );
    return result != null;
  }

  /// Re-syncs the current progress with the shared account (app ↔ website).
  static Future<void> pushToCloud() => syncWithCloud();

  // -------------------------------------------------------------------------
  // Heritage Mug reward
  //
  // Finishing the trail earns a physical reward collected from CCAT. The
  // backend issues it, holds the claim code, and shows it to staff on the
  // website's Rewards page — the code is what a tourist and an officer match
  // against each other at the counter.
  // -------------------------------------------------------------------------

  /// This account's reward record, or null if none has been issued yet.
  /// Shape: {id, reward, code, status, created_at, claimed_at}.
  static Future<Map<String, dynamic>?> fetchReward() async {
    final res = await TcimsApi.get('/api/claim_reward.php');
    return res is Map<String, dynamic> ? res : null;
  }

  /// Asks the backend to issue the reward for this account.
  ///
  /// Safe to call optimistically: the server re-checks completion itself and
  /// answers 400 when the trail is not genuinely finished, which TcimsApi
  /// surfaces as null rather than an exception. Issuing is idempotent, so a
  /// repeat call returns the existing reward instead of a second one.
  ///
  /// Returns null when the server declines or the device is offline.
  static Future<Map<String, dynamic>?> claimReward() async {
    final existing = await fetchReward();
    if (existing != null && existing['code'] != null) return existing;
    final res = await TcimsApi.post('/api/claim_reward.php', const {});
    return res is Map<String, dynamic> && res['code'] != null ? res : null;
  }

  /// Unlocks the entire trail in memory (used by the demo account). Not saved
  /// to device storage, so it only lasts for the current session — but it IS
  /// recorded on the shared database so the demo also looks complete when the
  /// same account is opened on the website.
  static Future<void> unlockAll() async {
    visited.addAll(kChurches.map((c) => c.name));
    final remoteRaw = await TcimsApi.get('/api/visits.php');
    final remote =
        (remoteRaw is List) ? remoteRaw.cast<String>().toSet() : <String>{};
    for (final c in kChurches) {
      // visits.php POST TOGGLES — only call it for places the server does not
      // already have, or a second demo login would un-check them.
      if (remote.contains(c.name)) continue;
      await TcimsApi.post('/api/visits.php', {'place': c.name});
    }
  }
}

class HeritageTrailPage extends StatefulWidget {
  const HeritageTrailPage({super.key});

  @override
  State<HeritageTrailPage> createState() => _HeritageTrailPageState();
}

class _HeritageTrailPageState extends State<HeritageTrailPage> {
  /// The Heritage Mug record once the backend has issued it.
  Map<String, dynamic>? _reward;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  /// Pulls anything verified elsewhere, then makes sure a finished trail has
  /// its reward. Syncing here — rather than only at sign-in — means a visit
  /// verified on the website shows up as soon as this page is opened, instead
  /// of waiting for the app to be restarted.
  Future<void> _refresh() async {
    await TrailProgress.syncWithCloud();
    if (!mounted) return;
    setState(() {});
    await _ensureReward();
  }

  /// Issues the reward if the trail is complete. The backend re-checks
  /// completion itself and declines otherwise, so calling this is harmless
  /// even when the app's own count is wrong.
  Future<void> _ensureReward() async {
    if (!TrailProgress.isComplete) return;
    final reward = await TrailProgress.claimReward();
    if (!mounted || reward == null) return;
    setState(() => _reward = reward);
  }

  Future<void> _verify(Church c) async {
    // The trail involves travelling to real locations, so it has a minimum
    // age requirement.
    if (!UserProfileStore.canJoinTrail) {
      await showDialog(
        context: context,
        builder: (context) => AlertDialog(
          icon: const Icon(Icons.info_outline, size: 40),
          title: const Text('Age requirement'),
          content: Text(
            'The Heritage Church Trail is for visitors aged '
            '$kMinimumTrailAge and above, because it involves travelling to '
            'churches around the city and verifying each visit.\n\n'
            'You can still explore every church, attraction and city service '
            'in the app.',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('I understand'),
            ),
          ],
        ),
      );
      return;
    }

    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => VerifyVisitPage(church: c)),
    );
    if (mounted) setState(() {}); // refresh after returning
    // That visit may have been the last one.
    await _ensureReward();
  }

  Future<void> _claimCertificate() async {
    final name = await _askName();
    if (name == null || name.trim().isEmpty) return;
    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => CertificatePage(name: name.trim())),
    );
  }

  Future<String?> _askName() {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Name on certificate'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'Full name',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final visitedCount = TrailProgress.visited.length;
    final total = kChurches.length;
    final complete = TrailProgress.isComplete;

    return Scaffold(
      appBar: AppBar(title: const Text('Heritage Church Trail')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            'Follow the trail',
            style: Theme.of(context).textTheme.titleLarge
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          const Text(
            'A self-guided route through Mandaluyong\'s historic churches. '
            'At each stop, take a live selfie and a photo of the church — the '
            'app confirms your GPS location to verify you were really there. '
            'Finish all stops to earn your certificate of completion.',
            style: TextStyle(height: 1.4),
          ),
          const SizedBox(height: 20),

          // Progress bar (fills up smoothly on open)
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: total == 0 ? 0 : visitedCount / total),
              duration: const Duration(milliseconds: 900),
              curve: Curves.easeOutCubic,
              builder: (context, v, _) => LinearProgressIndicator(
                value: v,
                minHeight: 10,
                backgroundColor: colors.surfaceContainerHighest,
                color: AppTheme.brandGold, // gold = achievement
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '$visitedCount of $total stops visited',
            style: TextStyle(color: colors.onSurfaceVariant),
          ),
          const SizedBox(height: 20),

          // Achievement banner (only when all stops are visited)
          if (complete) ...[
            PopIn(
              delayMs: 150,
              child: _CompletionBanner(
                onClaim: _claimCertificate,
                rewardCode: _reward?['code'] as String?,
                rewardStatus: _reward?['status'] as String?,
              ),
            ),
            const SizedBox(height: 20),
          ],

          // Numbered timeline of stops — cascade in one after another
          for (int i = 0; i < kChurches.length; i++)
            Reveal(
              delayMs: 120 + i * 70,
              child: _TrailStop(
                index: i + 1,
                church: kChurches[i],
                isLast: i == kChurches.length - 1,
                verified: TrailProgress.isVisited(kChurches[i]),
                onVerify: () => _verify(kChurches[i]),
              ),
            ),
        ],
      ),
    );
  }
}

/// Shown when every stop is visited.
class _CompletionBanner extends StatelessWidget {
  const _CompletionBanner({
    required this.onClaim,
    this.rewardCode,
    this.rewardStatus,
  });

  final VoidCallback onClaim;

  /// The claim code for the Heritage Mug, once the backend has issued one.
  /// This is the string CCAT staff see on the website's Rewards page, so it is
  /// what a tourist and an officer match against each other at the counter.
  final String? rewardCode;

  /// "Unclaimed" until an officer hands the mug over, then "Claimed".
  final String? rewardStatus;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        // Navy field with a gold trophy — the certificate look.
        gradient: const LinearGradient(
          colors: [Color(0xFF12305F), Color(0xFF1E4B8F)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
            color: AppTheme.brandGold.withValues(alpha: 0.6), width: 1.5),
      ),
      child: Column(
        children: [
          const Icon(Icons.emoji_events,
              color: AppTheme.brandGold, size: 44),
          const SizedBox(height: 8),
          const Text(
            'Trail Complete!',
            style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'You visited all the heritage churches of Mandaluyong.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white.withValues(alpha: 0.9)),
          ),
          // The mug claim code, once the backend has issued it. Shown in a
          // panel of its own and spaced out, because this is a string someone
          // will read aloud or copy at a counter.
          if (rewardCode != null) ...[
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: AppTheme.brandGold.withValues(alpha: 0.45)),
              ),
              child: Column(
                children: [
                  Text(
                    'Heritage Mug claim code',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.85),
                      fontSize: 11,
                      letterSpacing: 0.4,
                    ),
                  ),
                  const SizedBox(height: 4),
                  SelectableText(
                    rewardCode!,
                    style: const TextStyle(
                      color: AppTheme.brandGold,
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 2,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    rewardStatus == 'Claimed'
                        ? 'Claimed — thank you for walking the trail.'
                        : 'Show this code at the CCAT office to collect '
                            'your mug.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.9),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: onClaim,
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.brandGold,
              foregroundColor: const Color(0xFF12305F),
            ),
            icon: const Icon(Icons.workspace_premium),
            label: const Text('Claim your certificate'),
          ),
        ],
      ),
    );
  }
}

class _TrailStop extends StatelessWidget {
  const _TrailStop({
    required this.index,
    required this.church,
    required this.isLast,
    required this.verified,
    required this.onVerify,
  });
  final int index;
  final Church church;
  final bool isLast;
  final bool verified;
  final VoidCallback onVerify;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    // Verified stops are an achievement — gold, matching the trail system.
    const success = AppTheme.brandGold;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Left: number (or check when verified) + connecting line
          Column(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: verified ? success : colors.primary,
                child: verified
                    ? const Icon(Icons.check,
                        color: Color(0xFF12305F), size: 20)
                    : Text(
                        '$index',
                        style: TextStyle(
                          color: colors.onPrimary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
              ),
              if (!isLast)
                Expanded(
                  child: Container(
                    width: 3,
                    color: colors.primary.withValues(alpha: 0.3),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 14),
          // Right: church card + verify control
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ChurchCard(church: church),
                  const SizedBox(height: 6),
                  if (verified)
                    Row(
                      children: [
                        Icon(Icons.verified, color: success, size: 20),
                        const SizedBox(width: 6),
                        Text(
                          'Verified with photos',
                          style: TextStyle(
                            color: success,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    )
                  else
                    Align(
                      alignment: Alignment.centerLeft,
                      child: FilledButton.tonalIcon(
                        onPressed: onVerify,
                        icon: const Icon(Icons.camera_alt_outlined, size: 18),
                        label: const Text('Verify visit (selfie + photo)'),
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

// ---------------------------------------------------------------------------
// Verify a visit: live selfie + church photo + GPS check-in
// ---------------------------------------------------------------------------
class VerifyVisitPage extends StatefulWidget {
  const VerifyVisitPage({super.key, required this.church});
  final Church church;

  @override
  State<VerifyVisitPage> createState() => _VerifyVisitPageState();
}

class _VerifyVisitPageState extends State<VerifyVisitPage> {
  // The visitor must be within this many metres of the church to verify.
  static const double _radiusMeters = 300;

  final ImagePicker _picker = ImagePicker();
  XFile? _selfie; // taken with the front camera
  XFile? _churchPhoto; // taken with the back camera

  bool _checking = false; // location check in progress
  String? _error; // last error / "too far" message

  bool get _ready => _selfie != null && _churchPhoto != null;

  Future<void> _capture({required bool selfie}) async {
    try {
      final img = await _picker.pickImage(
        source: ImageSource.camera, // live camera only — no gallery
        preferredCameraDevice:
            selfie ? CameraDevice.front : CameraDevice.rear,
        // Compression happens at capture time: the image is downscaled and
        // re-encoded as JPEG before it ever reaches storage. 1024px is plenty
        // for verifying a visit, and keeps each photo around 100–180 KB —
        // important because every check-in stores two photos, and they are
        // uploaded to the CCAT backend.
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 70,
      );
      if (img == null) return;
      setState(() {
        if (selfie) {
          _selfie = img;
        } else {
          _churchPhoto = img;
        }
        _error = null;
      });
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open the camera.')),
      );
    }
  }

  /// Gets the current GPS position, handling permissions and disabled GPS.
  Future<Position> _currentPosition() async {
    final serviceOn = await Geolocator.isLocationServiceEnabled();
    if (!serviceOn) {
      throw 'Location (GPS) is turned off. Please turn it on, then try again.';
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied) {
      throw 'Location permission is needed to confirm you are at the church.';
    }
    if (permission == LocationPermission.deniedForever) {
      throw 'Location permission is blocked. Enable it for this app in your '
          'phone Settings, then try again.';
    }
    return Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
    );
  }

  Future<void> _verify() async {
    if (!_ready) return;
    setState(() {
      _checking = true;
      _error = null;
    });
    try {
      final pos = await _currentPosition();
      final meters = Geolocator.distanceBetween(
        pos.latitude,
        pos.longitude,
        widget.church.lat,
        widget.church.lng,
      );
      if (meters <= _radiusMeters) {
        final sentToOffice = await TrailProgress.markVerified(
          widget.church,
          [_selfie!.path, _churchPhoto!.path],
        );
        if (!mounted) return;
        // Celebrate if this verification unlocked a new badge.
        final badge = badgeForCount(TrailProgress.visited.length);
        if (badge != null) {
          await showBadgeUnlocked(context, badge);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor:
                  AppTheme.successFor(Theme.of(context).brightness),
              content: Text(
                'Verified! You were about ${meters.round()} m from the church.',
              ),
            ),
          );
        }
        if (!mounted) return;
        // The visit itself is safe on this device either way. Say so plainly
        // when the office does not have it yet, rather than letting the person
        // assume it was filed when the upload has not gone through.
        if (!sentToOffice) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              duration: Duration(seconds: 5),
              content: Text(
                'Saved on this phone. The photos have not reached the tourism '
                'office yet — they will be sent automatically once you have a '
                'connection.',
              ),
            ),
          );
        }
        if (!mounted) return;
        Navigator.pop(context);
      } else {
        setState(() {
          _error =
              'You seem to be about ${meters.round()} m away. You need to be '
              'within ${_radiusMeters.round()} m of ${widget.church.name} to '
              'verify. Please take the photos while you are at the church.';
        });
      }
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Verify your visit')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            widget.church.name,
            style: Theme.of(context).textTheme.titleLarge
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          const Text(
            'To verify you are really here, take a live selfie at the church '
            'and one photo of the church (inside or outside). The app then '
            'checks your GPS location. Saved or downloaded pictures cannot be '
            'used — only the live camera.',
            style: TextStyle(height: 1.4),
          ),
          const SizedBox(height: 20),

          _CaptureTile(
            label: '1. Selfie at the church',
            hint: 'Front camera',
            icon: Icons.person_outline,
            file: _selfie,
            onTap: () => _capture(selfie: true),
          ),
          const SizedBox(height: 14),
          _CaptureTile(
            label: '2. Photo of the church',
            hint: 'Inside or outside',
            icon: Icons.church_outlined,
            file: _churchPhoto,
            onTap: () => _capture(selfie: false),
          ),

          if (_error != null) ...[
            const SizedBox(height: AppSpacing.l),
            Container(
              padding: const EdgeInsets.all(AppSpacing.l),
              decoration: BoxDecoration(
                color: colors.errorContainer,
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.location_off_outlined,
                      color: colors.onErrorContainer),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _error!,
                      style: TextStyle(
                        color: colors.onErrorContainer,
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: (_ready && !_checking) ? _verify : null,
            icon: _checking
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.verified_outlined),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
            label: Text(
              _checking
                  ? 'Checking your location…'
                  : _ready
                      ? 'Check location & verify'
                      : 'Take both photos first',
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Tip: stand close to the church and keep GPS on for the most '
            'accurate check.',
            style: TextStyle(color: colors.outline, fontSize: 12.5),
          ),
        ],
      ),
    );
  }
}

/// One photo-capture slot used on the verify page.
class _CaptureTile extends StatelessWidget {
  const _CaptureTile({
    required this.label,
    required this.hint,
    required this.icon,
    required this.file,
    required this.onTap,
  });

  final String label;
  final String hint;
  final IconData icon;
  final XFile? file;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final success = AppTheme.successFor(Theme.of(context).brightness);
    final done = file != null;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.m),
        decoration: BoxDecoration(
          color: colors.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(
            color: done ? success : colors.outlineVariant,
            width: done ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.sm),
              child: SizedBox(
                width: 60,
                height: 60,
                child: done
                    ? Image.file(File(file!.path), fit: BoxFit.cover)
                    : Container(
                        color: colors.surface,
                        child: Icon(icon, color: colors.primary),
                      ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    done ? 'Photo taken — tap to retake' : hint,
                    style: TextStyle(
                      color: done ? success : colors.outline,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              done ? Icons.check_circle : Icons.camera_alt_outlined,
              color: done ? success : colors.primary,
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Certificate of Completion
// ---------------------------------------------------------------------------
class CertificatePage extends StatefulWidget {
  const CertificatePage({super.key, required this.name, this.preview = false});
  final String name;
  final bool preview; // preview mode skips the auto-email

  @override
  State<CertificatePage> createState() => _CertificatePageState();
}

class _CertificatePageState extends State<CertificatePage> {
  static const _months = [
    'January', 'February', 'March', 'April', 'May', 'June', 'July',
    'August', 'September', 'October', 'November', 'December',
  ];

  late final String _dateStr;
  // Email status: 'sending', 'sent', 'failed', or 'no-email'.
  String _status = 'sending';
  String _message = '';

  final GlobalKey _certKey = GlobalKey(); // for capturing the certificate image
  bool _sharing = false;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _dateStr = '${_months[now.month - 1]} ${now.day}, ${now.year}';
    if (widget.preview) {
      _status = 'preview';
    } else {
      _sendEmail();
    }
  }

  /// Captures the certificate as a PNG and opens the share sheet.
  Future<void> _share() async {
    setState(() => _sharing = true);
    try {
      final boundary =
          _certKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 3.0);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      final bytes = data!.buffer.asUint8List();
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/be_mandaluyong_certificate.png');
      await file.writeAsBytes(bytes);
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path)],
          text: 'I completed the Heritage Church Trail of Mandaluyong '
              '— Be@Mandaluyong',
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not share the certificate.')),
      );
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  Future<void> _sendEmail() async {
    final email = FirebaseAuth.instance.currentUser?.email;
    if (email == null || email.isEmpty) {
      setState(() {
        _status = 'no-email';
        _message = 'No email is linked to your account.';
      });
      return;
    }
    setState(() {
      _status = 'sending';
      _message = '';
    });
    final error = await EmailService.sendCertificate(
      toEmail: email,
      toName: widget.name,
      churchCount: kChurches.length,
      completionDate: _dateStr,
    );
    if (!mounted) return;
    setState(() {
      if (error == null) {
        _status = 'sent';
        _message = 'Certificate sent to $email';
      } else {
        _status = 'failed';
        _message = error;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final name = widget.name;
    final dateStr = _dateStr;

    return Scaffold(
      appBar: AppBar(title: const Text('Certificate')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // The certificate (wrapped so it can be captured as an image)
          RepaintBoundary(
            key: _certKey,
            child: _CertificateCard(
              name: name,
              dateStr: dateStr,
              churchCount: kChurches.length,
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          FilledButton.icon(
            onPressed: _sharing ? null : _share,
            icon: _sharing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.share_outlined),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
            label: Text(_sharing ? 'Preparing…' : 'Share certificate'),
          ),
          const SizedBox(height: AppSpacing.l),
          _buildEmailStatus(colors),
        ],
      ),
    );
  }

  Widget _buildEmailStatus(ColorScheme colors) {
    switch (_status) {
      case 'preview':
        return Text(
          'Preview — this is how your certificate will look once you finish '
          'the trail. (Not emailed in preview.)',
          textAlign: TextAlign.center,
          style: TextStyle(color: colors.outline, fontSize: 12.5),
        );
      case 'sending':
        return const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              height: 18,
              width: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 12),
            Text('Emailing your certificate…'),
          ],
        );
      case 'sent':
        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color:
                AppTheme.successFor(colors.brightness).withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(AppRadius.sm),
          ),
          child: Row(
            children: [
              Icon(Icons.check_circle,
                  color: AppTheme.successFor(colors.brightness)),
              const SizedBox(width: 10),
              Expanded(child: Text(_message)),
            ],
          ),
        );
      default: // 'failed' or 'no-email'
        return Column(
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: colors.errorContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(Icons.error_outline, color: colors.onErrorContainer),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _message,
                      style: TextStyle(color: colors.onErrorContainer),
                    ),
                  ),
                ],
              ),
            ),
            if (_status == 'failed') ...[
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _sendEmail,
                icon: const Icon(Icons.refresh),
                label: const Text('Try again'),
              ),
            ],
          ],
        );
    }
  }
}

/// The visual certificate. Uses its own fixed colors (not the app theme) so it
/// looks the same in light or dark mode and in the shared image.
class _CertificateCard extends StatelessWidget {
  const _CertificateCard({
    required this.name,
    required this.dateStr,
    required this.churchCount,
  });

  final String name;
  final String dateStr;
  final int churchCount;

  static const Color _parchment = Color(0xFFFBF8F0);
  static const Color _navy = AppTheme.brandBlue;
  static const Color _gold = Color(0xFFC9A227); // readable gold for lines/text
  static const Color _ink = Color(0xFF2B2B2B);
  static const Color _grey = Color(0xFF6E6E6E);

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: _parchment,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: _gold, width: 4),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      padding: const EdgeInsets.all(6),
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: _navy.withValues(alpha: 0.35), width: 1.5),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 28),
        child: Column(
          children: [
            Image.asset(
              'assets/icon/new_logo.png',
              height: 76,
              errorBuilder: (_, _, _) =>
                  const Icon(Icons.workspace_premium, size: 64, color: _navy),
            ),
            const SizedBox(height: 14),
            Text(
              'Certificate of Completion',
              textAlign: TextAlign.center,
              style: AppTheme.brandTextStyle(fontSize: 23, color: _navy),
            ),
            const SizedBox(height: 6),
            const Text(
              'HERITAGE CHURCH TRAIL',
              style: TextStyle(
                fontSize: 11.5,
                letterSpacing: 3,
                fontWeight: FontWeight.w700,
                color: _gold,
              ),
            ),
            const SizedBox(height: 18),
            _ornament(),
            const SizedBox(height: 18),
            const Text(
              'This certifies that',
              style: TextStyle(
                  color: _grey, fontStyle: FontStyle.italic, fontSize: 14),
            ),
            const SizedBox(height: 10),
            Text(
              name,
              textAlign: TextAlign.center,
              style: AppTheme.brandTextStyle(fontSize: 30, color: _ink),
            ),
            const SizedBox(height: 8),
            Container(height: 2, width: 180, color: _gold.withValues(alpha: 0.7)),
            const SizedBox(height: 16),
            Text(
              'has successfully completed the Heritage Church Trail of '
              'Mandaluyong, visiting all $churchCount historic churches of '
              'the city.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: _ink, height: 1.55, fontSize: 14.5),
            ),
            const SizedBox(height: 20),
            const Icon(Icons.verified, color: _navy, size: 34),
            const SizedBox(height: 8),
            Text(
              'Awarded on $dateStr',
              style: const TextStyle(color: _grey, fontSize: 12.5),
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _sign('Be@Mandaluyong'),
                _sign('City of Mandaluyong'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _ornament() => Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(width: 40, height: 1.5, color: _gold),
          const SizedBox(width: 8),
          const Icon(Icons.church, size: 16, color: _gold),
          const SizedBox(width: 8),
          Container(width: 40, height: 1.5, color: _gold),
        ],
      );

  Widget _sign(String label) => Column(
        children: [
          Container(width: 110, height: 1.4, color: _ink.withValues(alpha: 0.5)),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(
                fontSize: 11.5, color: _grey, fontWeight: FontWeight.w600),
          ),
        ],
      );
}
