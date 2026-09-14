import 'dart:math' as math;
import 'dart:ui' show ImageFilter, lerpDouble;

import 'package:flutter/material.dart';

import 'app_features.dart';
import 'heritage.dart'; // kChurches, TrailProgress — for the featured card
import 'theme.dart';
import 'user_role.dart';

// ===========================================================================
// The floating quick menu.
//
// A single round button hovers above the bottom navigation on every main tab.
// Tapping it blooms open a full-screen sheet holding every feature the signed-
// in person is allowed to see, grouped and drawn as circular shortcuts — so
// any part of the app is two taps away from anywhere, without hunting through
// tabs.
//
// The contents come from app_features.dart, the same catalogue the Services
// tab reads, so the two can never disagree about what a Tourist or a Mandaleño
// is offered.
// ===========================================================================

/// Diameter of the resting button.
const double _kButtonSize = 62;

/// How far each petal travels from the centre when the menu opens.
const double _kPetalReach = 26;

/// Number of petals in the bloom.
const int _kPetalCount = 8;

/// The bloom wears the city's own colours: the vivid flag blue and the seal's
/// gold, alternating around the circle the way they sit on the seal itself.
///
/// The city red is deliberately absent. The palette reserves it for
/// emergencies so it always reads as urgent — spending it on decoration here
/// would blunt that signal everywhere else in the app.
const List<Color> _kPetalColors = <Color>[
  AppTheme.flagBlue,
  AppTheme.brandGold,
];

/// Space the open bloom needs around the circle.
const double _kBloomExtent = _kButtonSize + (_kPetalReach * 2) + 24;

/// Height of the app's bottom bar at the default text size.
const double _kFooterBaseHeight = 76;

/// Height of the app's bottom bar, shared with main.dart.
///
/// The sheet needs it to place its circle at exactly the same point on screen
/// as the docked button underneath — otherwise the button appears to jump the
/// moment the menu opens, instead of blooming in place.
///
/// It grows with the reader's chosen text size, because this app serves a
/// whole city and plenty of residents run their phone at a large font. Capped
/// at 1.4x so a very large setting cannot eat the screen; past that the labels
/// ellipsise rather than the bar swallowing the page.
double footerHeight(BuildContext context) {
  final scale = MediaQuery.textScalerOf(context).scale(1);
  return _kFooterBaseHeight * (scale <= 1 ? 1 : math.min(scale, 1.4));
}

/// Each feature carries a fixed brand colour, chosen against a white page.
/// Several of them — the deep navy, the forest green, the maroon red — go
/// nearly invisible on a dark background, so in dark mode the same hue is
/// lifted to a lightness that still reads. The hue is preserved, which is what
/// keeps a feature recognisable as "the green one" in either theme.
Color _readable(Color base, Brightness brightness) {
  if (brightness == Brightness.light) return base;
  final hsl = HSLColor.fromColor(base);
  return hsl
      .withLightness(math.max(hsl.lightness, 0.68))
      .withSaturation(math.min(hsl.saturation, 0.80))
      .toColor();
}

// ---------------------------------------------------------------------------
// The resting button
// ---------------------------------------------------------------------------

/// The floating "Services" button. Drop this into a Scaffold's
/// [Scaffold.floatingActionButton] slot with a centred location.
class QuickMenuButton extends StatelessWidget {
  const QuickMenuButton({super.key});

  @override
  Widget build(BuildContext context) {
    // No label here: docked into the footer, the word "Services" is drawn by
    // the navigation bar itself, in line with the other destination labels.
    return _MenuOrb(
      icon: Icons.grid_view_rounded,
      semanticLabel: 'Open services',
      onTap: () => openQuickMenu(context),
    );
  }
}

/// The round button itself, drawn identically in the footer and in the open
/// sheet so the two read as one object rather than two widgets swapping.
///
/// Deliberately unlabelled: the footer prints "Services" beneath it in line
/// with the other destination labels, and adding a word here would push the
/// circle off the point the sheet anchors to.
class _MenuOrb extends StatelessWidget {
  const _MenuOrb({
    required this.icon,
    required this.semanticLabel,
    required this.onTap,
    this.halo,
  });

  final IconData icon;
  final String semanticLabel;
  final VoidCallback onTap;

  /// Optional decoration painted *behind* the circle and centred on it —
  /// the petal bloom, when the sheet is open.
  final Widget? halo;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    final circle = Material(
      color: colors.primary,
      shape: const CircleBorder(),
      elevation: 6,
      shadowColor: Colors.black.withValues(alpha: 0.4),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: _kButtonSize,
          height: _kButtonSize,
          child: Icon(icon, size: 27, color: colors.onPrimary),
        ),
      ),
    );

    return Semantics(
      button: true,
      label: semanticLabel,
      child: halo == null
          ? circle
          : SizedBox(
              width: _kBloomExtent,
              height: _kBloomExtent,
              child: Stack(
                alignment: Alignment.center,
                children: [halo!, circle],
              ),
            ),
    );
  }
}

// ---------------------------------------------------------------------------
// Opening the sheet
// ---------------------------------------------------------------------------

/// Opens the quick menu over the current screen.
///
/// The launching navigator is captured before the sheet appears, so a chosen
/// shortcut can close the sheet and then push its destination onto the page
/// stack underneath rather than inside the dismissed overlay.
void openQuickMenu(BuildContext context) {
  final launcher = Navigator.of(context);

  showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Quick menu',
    barrierColor: Colors.transparent, // the sheet paints its own scrim
    // Long enough to watch: the circle grows, then the icons cascade in one
    // after another. showGeneralDialog applies this to both directions, so the
    // reverse curves below finish early to keep dismissal snappy.
    transitionDuration: const Duration(milliseconds: 720),
    pageBuilder: (_, _, _) => const SizedBox.shrink(),
    transitionBuilder: (dialogContext, animation, _, _) {
      // Opening eases out over the full duration. Closing is compressed into
      // the first stretch of it — the sheet is gone in about 250ms even though
      // the route itself takes the same time either way.
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: const Interval(0.55, 1, curve: Curves.easeIn),
      );
      // The sheet is revealed by a circle growing out of the Services button
      // itself, so the menu visibly comes from the thing that was pressed
      // rather than simply appearing over the page.
      return _CircularReveal(
        animation: curved,
        child: _QuickMenuSheet(animation: curved, launcher: launcher),
      );
    },
  );
}

// ---------------------------------------------------------------------------
// The sheet
// ---------------------------------------------------------------------------

class _QuickMenuSheet extends StatelessWidget {
  const _QuickMenuSheet({required this.animation, required this.launcher});

  final Animation<double> animation;
  final NavigatorState launcher;

  void _open(BuildContext context, AppFeature feature) {
    Navigator.of(context).pop(); // close the sheet first
    final page = feature.page;
    if (page != null) {
      launcher.push(MaterialPageRoute(builder: page));
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final role = UserRoleStore.current;

    // This menu is for visitors and residents only — staff reach their tools
    // from the staff console, and never see the Services button at all.
    //
    // Residents lead with city business; visitors lead with places to go. The
    // trail is left out of the grid because it gets the featured card above.
    final explore = exploreFeatures(includeTrail: false);
    final city = cityServiceFeatures(role);
    final leadsWithCity = role == UserRole.mandaleno;
    final sections = <_Section>[
      _Section(role.primarySectionTitle, leadsWithCity ? city : explore),
      _Section(role.secondarySectionTitle, leadsWithCity ? explore : city),
      _Section('Urgent', [emergencyFeature()]),
    ];

    return Material(
      type: MaterialType.transparency,
      child: Stack(
        children: [
          // Frosted scrim — the page underneath stays faintly visible, which
          // keeps the menu feeling like a layer rather than a new screen.
          Positioned.fill(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
              child: Container(
                // Nearly opaque: enough of the page shows through to feel like
                // a layer, not so much that text sits on a busy background.
                color: colors.surface.withValues(alpha: 0.96),
              ),
            ),
          ),

          SafeArea(
            child: Column(
              children: [
                // A title in the brand serif gives the sheet an identity —
                // it reads as a place in the app rather than a menu that
                // dropped out of nowhere.
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                      AppSpacing.l, AppSpacing.s, AppSpacing.m, 0),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Services',
                              style: AppTheme.brandTextStyle(
                                fontSize: 26,
                                color: colors.onSurface,
                              ),
                            ),
                            Text(
                              'Everything Be@Mandaluyong can do',
                              style: text.bodySmall
                                  ?.copyWith(color: colors.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Close',
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.m),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.l,
                      0,
                      AppSpacing.l,
                      // Room for the closing button so the last row is never
                      // hidden behind it.
                      _kBloomExtent + AppSpacing.xxl,
                    ),
                    children: [
                      // The flagship feature leads, with progress on it, so
                      // the sheet opens on something that says where you are
                      // rather than twelve identical circles.
                      _TrailCard(
                        animation: animation,
                        onTap: () => _open(context, heritageTrailFeature()),
                      ),
                      const SizedBox(height: AppSpacing.l),
                      for (var i = 0; i < sections.length; i++) ...[
                        _SectionBlock(
                          section: sections[i],
                          animation: animation,
                          order: i,
                          // Running count of every shortcut above this block,
                          // so the cascade flows continuously down the sheet
                          // instead of restarting at each heading.
                          startIndex: sections
                              .take(i)
                              .fold(0, (sum, s) => sum + s.features.length),
                          onTap: (f) => _open(context, f),
                        ),
                        const SizedBox(height: AppSpacing.l),
                      ],
                      Center(
                        child: Text(
                          'Be@Mandaluyong',
                          style: text.labelMedium?.copyWith(
                            color: colors.outline,
                            letterSpacing: 1.2,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Anchored so the circle lands exactly over the docked button it
          // grew out of: the footer's height puts the button's centre on the
          // bar's top edge, and half the bloom box sits above that centre.
          Positioned(
            left: 0,
            right: 0,
            bottom: footerHeight(context) +
                MediaQuery.viewPaddingOf(context).bottom -
                (_kBloomExtent / 2),
            child: Center(
              child: _Bloom(
                animation: animation,
                onTap: () => Navigator.of(context).pop(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Section {
  const _Section(this.title, this.features);
  final String title;
  final List<AppFeature> features;
}

// ---------------------------------------------------------------------------
// Circular reveal
// ---------------------------------------------------------------------------

/// Wipes the sheet in behind a circle that grows out of the Services button.
///
/// The circle starts exactly the size of the button, at exactly the button's
/// place on screen, and swells until it covers the furthest corner — so the
/// menu reads as the button opening up rather than a panel appearing on top
/// of the page. Closing runs the same circle back down into the button.
class _CircularReveal extends StatelessWidget {
  const _CircularReveal({required this.animation, required this.child});

  final Animation<double> animation;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final inset = MediaQuery.viewPaddingOf(context).bottom;

    // The button's centre sits on the top edge of the footer.
    final centre = Offset(
      size.width / 2,
      size.height - footerHeight(context) - inset,
    );

    // Reach the furthest corner — the top ones, since the button is low.
    final maxRadius = math.sqrt(
      math.pow(size.width / 2, 2) + math.pow(centre.dy, 2),
    );

    // The wipe takes most of the opening, easing in gently rather than
    // snapping outward — a circle that reaches the screen edge in a fifth of a
    // second reads as "it just appeared", however carefully it was animated.
    final grow = CurvedAnimation(
      parent: animation,
      curve: const Interval(0, 0.78, curve: Curves.easeInOutCubic),
    );

    // A short fade over the top softens the clip's hard edge, so the sheet
    // arrives rather than being cut in.
    final soften = CurvedAnimation(
      parent: animation,
      curve: const Interval(0, 0.35, curve: Curves.easeOut),
    );

    return AnimatedBuilder(
      animation: grow,
      builder: (context, inner) => Opacity(
        opacity: soften.value,
        child: ClipPath(
          clipper: _CircleClipper(
            centre: centre,
            radius: lerpDouble(_kButtonSize / 2, maxRadius, grow.value)!,
          ),
          child: inner,
        ),
      ),
      child: child,
    );
  }
}

class _CircleClipper extends CustomClipper<Path> {
  const _CircleClipper({required this.centre, required this.radius});

  final Offset centre;
  final double radius;

  @override
  Path getClip(Size size) =>
      Path()..addOval(Rect.fromCircle(center: centre, radius: radius));

  @override
  bool shouldReclip(_CircleClipper old) =>
      old.radius != radius || old.centre != centre;
}

// ---------------------------------------------------------------------------
// The featured trail card
// ---------------------------------------------------------------------------

/// A full-width card leading the sheet, carrying the one number in this app
/// that is genuinely personal: how far along the Heritage Church Trail this
/// person is. Progress is read straight from [TrailProgress], which is already
/// in memory, so the card is correct the instant the menu opens.
class _TrailCard extends StatelessWidget {
  const _TrailCard({required this.animation, required this.onTap});

  final Animation<double> animation;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    final total = kChurches.length;
    final done = TrailProgress.visited.length.clamp(0, total).toInt();
    final complete = total > 0 && done >= total;
    final fraction = total == 0 ? 0.0 : done / total;

    final entrance = CurvedAnimation(
      parent: animation,
      curve: const Interval(0.22, 0.72, curve: Curves.easeOutCubic),
    );

    return AnimatedBuilder(
      animation: entrance,
      builder: (context, child) => Opacity(
        opacity: entrance.value,
        child: Transform.translate(
          offset: Offset(0, 18 * (1 - entrance.value)),
          child: child,
        ),
      ),
      child: Material(
        color: colors.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(AppSpacing.l),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.lg),
              border: Border.all(
                  color: AppTheme.brandGold.withValues(alpha: 0.45)),
            ),
            child: Row(
              children: [
                // Ring + count, gold because progress is a heritage moment.
                SizedBox(
                  width: 58,
                  height: 58,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      SizedBox(
                        width: 58,
                        height: 58,
                        child: CircularProgressIndicator(
                          value: fraction,
                          strokeWidth: 5,
                          backgroundColor:
                              AppTheme.brandGold.withValues(alpha: 0.18),
                          valueColor: const AlwaysStoppedAnimation<Color>(
                              AppTheme.brandGold),
                        ),
                      ),
                      Text(
                        '$done/$total',
                        style: text.labelLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: colors.onSurface,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.l),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Heritage Church Trail',
                        style: text.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        complete
                            ? 'All $total churches verified — your certificate '
                                'is ready.'
                            : done == 0
                                ? 'Visit and verify $total historic churches to '
                                    'earn your certificate.'
                                : '${total - done} more to go. Keep walking.',
                        style: text.bodySmall?.copyWith(color: colors.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: colors.outline),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// A titled group of circular shortcuts
// ---------------------------------------------------------------------------

class _SectionBlock extends StatelessWidget {
  const _SectionBlock({
    required this.section,
    required this.animation,
    required this.order,
    required this.startIndex,
    required this.onTap,
  });

  final _Section section;
  final Animation<double> animation;
  final int order;

  /// How many shortcuts appear above this block, used to keep the per-icon
  /// cascade running continuously from the top of the sheet.
  final int startIndex;
  final ValueChanged<AppFeature> onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    // Each section slides in a beat after the one above it.
    final start = math.min(order * 0.12, 0.6);
    final slide = CurvedAnimation(
      parent: animation,
      curve: Interval(start, 1, curve: Curves.easeOutCubic),
    );

    return AnimatedBuilder(
      animation: slide,
      builder: (context, child) => Opacity(
        opacity: slide.value,
        child: Transform.translate(
          offset: Offset(0, 22 * (1 - slide.value)),
          child: child,
        ),
      ),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.l),
        decoration: BoxDecoration(
          // A solid container rather than a translucent one: over the blurred
          // page, a see-through card muddied the labels in both themes.
          // No border — the surface change and the spacing already separate
          // the sections, and a line around each one only adds weight.
          color: colors.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                // A small gold stroke beside each heading — the seal's accent,
                // enough to carry the city's colour into the layout without
                // drawing another box.
                Container(
                  width: 3,
                  height: 15,
                  decoration: BoxDecoration(
                    color: AppTheme.brandGold,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: AppSpacing.s),
                Text(
                  section.title,
                  style:
                      text.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.l),
            GridView.count(
              crossAxisCount: 3,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: AppSpacing.l,
              crossAxisSpacing: AppSpacing.s,
              childAspectRatio: 0.84,
              children: [
                for (var i = 0; i < section.features.length; i++)
                  _Shortcut(
                    feature: section.features[i],
                    animation: animation,
                    order: startIndex + i,
                    onTap: () => onTap(section.features[i]),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Shortcut extends StatefulWidget {
  const _Shortcut({
    required this.feature,
    required this.animation,
    required this.order,
    required this.onTap,
  });

  final AppFeature feature;
  final Animation<double> animation;

  /// Position in the sheet-wide cascade — each icon starts a beat after the
  /// one before it, so the menu unfurls rather than appearing all at once.
  final int order;
  final VoidCallback onTap;

  @override
  State<_Shortcut> createState() => _ShortcutState();
}

class _ShortcutState extends State<_Shortcut> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = theme.textTheme;
    final f = widget.feature;
    final tint = _readable(f.color, theme.brightness);

    // Each icon occupies a slice of the opening animation. The slices overlap
    // heavily, so the effect is a flowing cascade rather than a queue of items
    // waiting their turn. The last one still lands before the sheet settles.
    // Starts once the circle has opened enough to show them, then each icon
    // follows the one before it.
    final begin = math.min(0.30 + (widget.order * 0.040), 0.70);
    final entrance = CurvedAnimation(
      parent: widget.animation,
      curve: Interval(begin, math.min(begin + 0.30, 1), curve: Curves.easeOut),
    );

    return AnimatedBuilder(
      animation: entrance,
      builder: (context, child) => Opacity(
        opacity: entrance.value,
        child: Transform.scale(
          // Starts a little small and settles, which reads as the icon
          // arriving rather than simply fading up.
          scale: 0.72 + (0.28 * entrance.value),
          child: child,
        ),
      ),
      child: AnimatedScale(
        scale: _pressed ? 0.92 : 1,
        duration: const Duration(milliseconds: 110),
        curve: Curves.easeOut,
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.md),
          onHighlightChanged: (v) => setState(() => _pressed = v),
          onTap: widget.onTap,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      // A gentle gradient instead of a flat wash, so each
                      // circle has a little depth and catches the light.
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          tint.withValues(alpha: 0.28),
                          tint.withValues(alpha: 0.10),
                        ],
                      ),
                      // A soft shadow in the feature's own colour lifts the
                      // circle off the card rather than outlining it.
                      boxShadow: [
                        BoxShadow(
                          color: tint.withValues(alpha: 0.20),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Icon(f.icon, size: 26, color: tint),
                  ),
                  if (f.badge != null)
                    Positioned(
                      top: -2,
                      right: -4,
                      child: FutureBuilder<int>(
                        future: f.badge,
                        builder: (context, snap) {
                          final n = snap.data ?? 0;
                          if (n <= 0) return const SizedBox.shrink();
                          return Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 1),
                            constraints: const BoxConstraints(minWidth: 20),
                            decoration: BoxDecoration(
                              // Gold is the palette's highlight; red would
                              // read as an alert, which a count is not.
                              color: AppTheme.brandGold,
                              borderRadius:
                                  BorderRadius.circular(AppRadius.pill),
                              border: Border.all(
                                  color: theme.colorScheme.surface, width: 2),
                            ),
                            child: Text(
                              n > 99 ? '99+' : '$n',
                              textAlign: TextAlign.center,
                              style: text.labelSmall?.copyWith(
                                color: Colors.black,
                                fontWeight: FontWeight.w800,
                                height: 1.2,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Flexible(
                child: Text(
                  f.label,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: text.bodySmall?.copyWith(fontWeight: FontWeight.w600),
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
// The bloom — petals fanning out behind the closing button
// ---------------------------------------------------------------------------

class _Bloom extends StatelessWidget {
  const _Bloom({required this.animation, required this.onTap});

  final Animation<double> animation;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;

    // Petals overshoot slightly then settle, which is what gives the bloom
    // its spring rather than a mechanical slide.
    final petals = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutBack,
      reverseCurve: Curves.easeIn,
    );

    // No label: the circle must line up pixel-for-pixel with the docked
    // button underneath, and a word below it would push the circle upward.
    return _MenuOrb(
      icon: Icons.close_rounded,
      semanticLabel: 'Close services',
      onTap: onTap,
      halo: AnimatedBuilder(
        animation: petals,
        builder: (context, _) {
          // easeOutBack overshoots past 1, which is what makes the petals
          // spring. Travel keeps the overshoot; scale is capped so a petal
          // never grows larger than its resting size.
          final t = petals.value < 0 ? 0.0 : petals.value;
          final petalScale = t > 1 ? 1.0 : t;
          return Stack(
            alignment: Alignment.center,
            children: [
              for (var i = 0; i < _kPetalCount; i++)
                Transform.rotate(
                  angle: (i * 2 * math.pi) / _kPetalCount,
                  child: Transform.translate(
                    offset: Offset(0, -_kPetalReach * t),
                    child: Transform.scale(
                      scale: petalScale,
                      child: Container(
                        width: 34,
                        height: 46,
                        decoration: BoxDecoration(
                          color: _readable(
                            _kPetalColors[i % _kPetalColors.length],
                            brightness,
                          ).withValues(alpha: 0.38),
                          borderRadius: BorderRadius.circular(24),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
