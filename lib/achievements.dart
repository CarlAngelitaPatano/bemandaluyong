import 'package:flutter/material.dart';

// ===========================================================================
// Trail achievement badges (shared by Profile and the verification flow).
// ===========================================================================
class TrailBadge {
  final String title;
  final String desc;
  final IconData icon;
  final int threshold; // churches needed to unlock
  const TrailBadge(this.title, this.desc, this.icon, this.threshold);
}

const List<TrailBadge> kBadges = [
  TrailBadge('First Step', 'Verify your first church', Icons.directions_walk, 1),
  TrailBadge('Explorer', 'Verify 3 heritage churches', Icons.explore_outlined, 3),
  TrailBadge('Halfway There', 'Reach 5 churches', Icons.timelapse_outlined, 5),
  TrailBadge(
      'Devotee', 'Verify 7 churches', Icons.local_fire_department_outlined, 7),
  TrailBadge('Trail Master', 'Complete all 9 churches', Icons.emoji_events, 9),
];

/// The badge unlocked exactly at [count] verified churches, if any.
TrailBadge? badgeForCount(int count) {
  for (final b in kBadges) {
    if (b.threshold == count) return b;
  }
  return null;
}

/// A celebratory "Badge unlocked!" dialog.
Future<void> showBadgeUnlocked(BuildContext context, TrailBadge badge) {
  final colors = Theme.of(context).colorScheme;
  final text = Theme.of(context).textTheme;
  return showDialog(
    context: context,
    builder: (context) => AlertDialog(
      icon: CircleAvatar(
        radius: 34,
        backgroundColor: colors.tertiaryContainer,
        child: Icon(badge.icon, size: 36, color: colors.onTertiaryContainer),
      ),
      title: const Text('Badge unlocked! 🎉'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(badge.title,
              style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(badge.desc,
              textAlign: TextAlign.center,
              style: TextStyle(color: colors.outline)),
        ],
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Nice!'),
        ),
      ],
    ),
  );
}
