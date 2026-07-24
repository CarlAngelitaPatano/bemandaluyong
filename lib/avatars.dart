import 'package:flutter/material.dart';

import 'theme.dart';

// ===========================================================================
// Built-in avatars.
//
// For users who'd rather not upload a photo of their face, the app offers a
// set of ready-made avatars. They're drawn with icons + colors (no image
// files), so they cost nothing in app size and look crisp at any resolution.
// ===========================================================================

class PresetAvatar {
  final String id; // saved in SharedPreferences
  final IconData icon;
  final Color color;
  final String label;

  const PresetAvatar(this.id, this.icon, this.color, this.label);
}

const List<PresetAvatar> kPresetAvatars = [
  PresetAvatar('church', Icons.church_rounded, Color(0xFF1E88E5), 'Church'),
  PresetAvatar('explorer', Icons.explore_rounded, Color(0xFF00897B), 'Explorer'),
  PresetAvatar('camera', Icons.photo_camera_rounded, Color(0xFFF4511E), 'Shutterbug'),
  PresetAvatar('city', Icons.location_city_rounded, Color(0xFF3949AB), 'City'),
  PresetAvatar('hiker', Icons.hiking_rounded, Color(0xFF43A047), 'Hiker'),
  PresetAvatar('star', Icons.star_rounded, Color(0xFFFDD835), 'Star'),
  PresetAvatar('heart', Icons.favorite_rounded, Color(0xFFE53935), 'Heart'),
  PresetAvatar('trophy', Icons.emoji_events_rounded, Color(0xFFFB8C00), 'Trophy'),
  PresetAvatar('map', Icons.map_rounded, Color(0xFF8E24AA), 'Navigator'),
  PresetAvatar('coffee', Icons.local_cafe_rounded, Color(0xFF6D4C41), 'Kapé'),
  PresetAvatar('sun', Icons.wb_sunny_rounded, Color(0xFFFFA000), 'Sunny'),
  PresetAvatar('pet', Icons.pets_rounded, Color(0xFF546E7A), 'Pets'),
];

/// Looks up a preset avatar by its saved id.
PresetAvatar? presetAvatarById(String? id) {
  if (id == null) return null;
  for (final a in kPresetAvatars) {
    if (a.id == id) return a;
  }
  return null;
}

/// Renders a preset avatar as a circle (used in the profile + app bar).
class PresetAvatarCircle extends StatelessWidget {
  const PresetAvatarCircle({
    super.key,
    required this.avatar,
    this.radius = 20,
  });

  final PresetAvatar avatar;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: radius * 2,
      height: radius * 2,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            avatar.color.withValues(alpha: 0.85),
            avatar.color,
          ],
        ),
      ),
      child: Icon(avatar.icon, size: radius, color: Colors.white),
    );
  }
}

/// Grid sheet that lets the user pick one of the built-in avatars.
/// Returns the chosen avatar's id, or null if dismissed.
Future<String?> showAvatarPicker(BuildContext context) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    builder: (context) {
      final text = Theme.of(context).textTheme;
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Choose an avatar', style: text.titleLarge),
              const SizedBox(height: 4),
              Text(
                'Prefer not to use your photo? Pick one of these instead.',
                style: text.bodyMedium,
              ),
              const SizedBox(height: AppSpacing.l),
              GridView.count(
                crossAxisCount: 4,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: AppSpacing.l,
                crossAxisSpacing: AppSpacing.l,
                children: [
                  for (final a in kPresetAvatars)
                    InkWell(
                      borderRadius: BorderRadius.circular(999),
                      onTap: () => Navigator.pop(context, a.id),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          PresetAvatarCircle(avatar: a, radius: 28),
                          const SizedBox(height: 6),
                          Text(a.label,
                              style: text.labelSmall,
                              overflow: TextOverflow.ellipsis),
                        ],
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      );
    },
  );
}
