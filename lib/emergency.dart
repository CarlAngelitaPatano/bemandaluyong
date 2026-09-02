import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'theme.dart';
import 'motion.dart';

// ===========================================================================
// Emergency hotlines — one tap to call. Available to everyone (Tourists and
// Mandaleños alike), because emergencies don't care who you are.
//
// Numbers are Mandaluyong City government / national emergency lines.
// ===========================================================================

class Hotline {
  final String name;
  final String number; // dialable form
  final String display; // pretty form
  final String detail;
  final IconData icon;
  final Color color;

  const Hotline({
    required this.name,
    required this.number,
    required this.display,
    required this.detail,
    required this.icon,
    required this.color,
  });
}

/// National emergency line first, then Mandaluyong city services.
const List<Hotline> kHotlines = [
  Hotline(
    name: 'National Emergency Hotline',
    number: '911',
    display: '911',
    detail: 'Police, fire and medical emergencies anywhere in the Philippines',
    icon: Icons.emergency_rounded,
    color: Color(0xFFD32F2F),
  ),
  Hotline(
    name: 'Mandaluyong CDRRMO (Rescue)',
    number: '85332225',
    display: '(02) 8533-2225',
    detail: 'City Disaster Risk Reduction & Management Office — rescue, floods,'
        ' earthquakes and other disasters',
    icon: Icons.health_and_safety_rounded,
    color: Color(0xFFEF6C00),
  ),
  Hotline(
    name: 'Mandaluyong CDRRMO (alternate)',
    number: '85331897',
    display: '(02) 8533-1897',
    detail: 'Second CDRRMO line if the first is busy',
    icon: Icons.support_agent_rounded,
    color: Color(0xFFF9A825),
  ),
  Hotline(
    name: 'Mandaluyong Police',
    number: '85322145',
    display: '(02) 8532-2145',
    detail: 'Mandaluyong City Police Station — crime and public safety',
    icon: Icons.local_police_rounded,
    color: Color(0xFF1565C0),
  ),
  Hotline(
    name: 'Mandaluyong Fire Station',
    number: '85322189',
    display: '(02) 8532-2189',
    detail: 'Bureau of Fire Protection — fires and fire-related rescue',
    icon: Icons.local_fire_department_rounded,
    color: Color(0xFFE53935),
  ),
  Hotline(
    name: 'Mandaluyong Fire (alternate)',
    number: '85322402',
    display: '(02) 8532-2402',
    detail: 'Second fire station line',
    icon: Icons.fire_truck_rounded,
    color: Color(0xFFFF7043),
  ),
  Hotline(
    name: 'Mandaluyong City Medical Center',
    number: '85320480',
    display: '(02) 8532-0480',
    detail: 'City hospital — medical emergencies and admissions',
    icon: Icons.local_hospital_rounded,
    color: Color(0xFF00897B),
  ),
  Hotline(
    name: 'City Health Office',
    number: '85340163',
    display: '(02) 8534-0163',
    detail: 'Health programs, clinics and public health concerns',
    icon: Icons.medical_services_rounded,
    color: Color(0xFF43A047),
  ),
  Hotline(
    name: 'Mandaluyong City Hall Trunkline',
    number: '85325001',
    display: '(02) 8532-5001',
    detail: 'Main city government line for other departments',
    icon: Icons.account_balance_rounded,
    color: Color(0xFF5E35B1),
  ),
];

class EmergencyPage extends StatelessWidget {
  const EmergencyPage({super.key});

  Future<void> _call(BuildContext context, Hotline h) async {
    final uri = Uri(scheme: 'tel', path: h.number);
    try {
      final ok = await launchUrl(uri);
      if (!ok && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open the dialer for ${h.display}')),
        );
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open the dialer for ${h.display}')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Emergency Hotlines')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.l),
        children: [
          // Big, obvious 911 call button.
          Reveal(
            delayMs: 0,
            child: Material(
              color: const Color(0xFFD32F2F),
              borderRadius: BorderRadius.circular(AppRadius.lg),
              child: InkWell(
                borderRadius: BorderRadius.circular(AppRadius.lg),
                onTap: () => _call(context, kHotlines.first),
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.xl),
                  child: Row(
                    children: [
                      const Icon(Icons.emergency_share_rounded,
                          color: Colors.white, size: 42),
                      const SizedBox(width: AppSpacing.l),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Call 911',
                              style: text.headlineSmall?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'National emergency hotline',
                              style: text.bodyMedium
                                  ?.copyWith(color: Colors.white70),
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.call, color: Colors.white),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          Reveal(
            delayMs: 80,
            child: Text('Mandaluyong City hotlines', style: text.titleMedium),
          ),
          const SizedBox(height: AppSpacing.s),
          Reveal(
            delayMs: 120,
            child: Text(
              'Tap any line to dial it.',
              style: text.bodySmall?.copyWith(color: colors.onSurfaceVariant),
            ),
          ),
          const SizedBox(height: AppSpacing.m),

          // Skip the first (911) — it already has the big button above.
          for (int i = 1; i < kHotlines.length; i++)
            Reveal(
              delayMs: 160 + (i - 1) * 60,
              child: Card(
                margin: const EdgeInsets.only(bottom: AppSpacing.m),
                child: ListTile(
                  onTap: () => _call(context, kHotlines[i]),
                  leading: CircleAvatar(
                    backgroundColor:
                        const Color(0xFFD32F2F).withValues(alpha: 0.10),
                    child: Icon(kHotlines[i].icon,
                        color: const Color(0xFFD32F2F)),
                  ),
                  title: Text(
                    kHotlines[i].name,
                    style: text.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 2),
                      Text(
                        kHotlines[i].display,
                        style: text.bodyMedium?.copyWith(
                          color: const Color(0xFFD32F2F),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(kHotlines[i].detail, style: text.bodySmall),
                    ],
                  ),
                  isThreeLine: true,
                  trailing: const Icon(Icons.call, color: Color(0xFFD32F2F)),
                ),
              ),
            ),

          const SizedBox(height: AppSpacing.l),
          Card(
            color: colors.surfaceContainerHighest,
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.l),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: colors.outline),
                  const SizedBox(width: AppSpacing.m),
                  Expanded(
                    child: Text(
                      'In a life-threatening emergency, call 911 first. '
                      'City lines are best for local rescue, health and '
                      'government concerns.',
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
