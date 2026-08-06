import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ===========================================================================
// User roles.
//
// Be@Mandaluyong serves two kinds of people:
//   • Tourist   — visiting the city; wants to discover and explore.
//   • Mandaleño — lives in Mandaluyong; wants city services and local news.
//
// The role is chosen at sign-up (and changeable in Profile). It doesn't lock
// any feature — every user can still reach everything — it simply reorders
// the home dashboard so the most relevant content comes first.
// ===========================================================================

enum UserRole { tourist, mandaleno }

extension UserRoleInfo on UserRole {
  String get id => this == UserRole.tourist ? 'tourist' : 'mandaleno';

  String get label => this == UserRole.tourist ? 'Tourist' : 'Mandaleño';

  String get description => this == UserRole.tourist
      ? 'Visiting Mandaluyong — discover its heritage and attractions'
      : 'I live in Mandaluyong — city services, news and events';

  IconData get icon =>
      this == UserRole.tourist ? Icons.luggage_rounded : Icons.home_rounded;

  Color get color => this == UserRole.tourist
      ? const Color(0xFFF4511E) // orange — explorer
      : const Color(0xFF0038A8); // city blue — local

  /// Section shown first on the home dashboard.
  String get primarySectionTitle =>
      this == UserRole.tourist ? 'Explore Mandaluyong' : 'City & services';

  /// Section shown second.
  String get secondarySectionTitle =>
      this == UserRole.tourist ? 'City & services' : 'Explore Mandaluyong';
}

class UserRoleStore {
  UserRoleStore._();

  /// Cached role so widgets can read it synchronously while building.
  static UserRole current = UserRole.tourist;

  static String? _keyForCurrentUser() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    return uid == null ? null : 'user_role_$uid';
  }

  /// Reads the saved role for the signed-in account into [current].
  static Future<UserRole> load() async {
    final key = _keyForCurrentUser();
    if (key == null) return current;
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(key);
    current =
        saved == UserRole.mandaleno.id ? UserRole.mandaleno : UserRole.tourist;
    return current;
  }

  static Future<void> save(UserRole role) async {
    current = role;
    final key = _keyForCurrentUser();
    if (key == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, role.id);
  }

  /// Role chosen during sign-up, before the account exists yet.
  static UserRole? pendingSignupRole;
}

/// A selectable role card used on the sign-up screen and in Profile.
class RoleOptionCard extends StatelessWidget {
  const RoleOptionCard({
    super.key,
    required this.role,
    required this.selected,
    required this.onTap,
  });

  final UserRole role;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: selected
              ? role.color.withValues(alpha: 0.10)
              : colors.surfaceContainerHighest,
          border: Border.all(
            color: selected ? role.color : colors.outlineVariant,
            width: selected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    role.color.withValues(alpha: 0.85),
                    role.color,
                  ],
                ),
              ),
              child: Icon(role.icon, color: Colors.white, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(role.label,
                      style: text.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(role.description, style: text.bodySmall),
                ],
              ),
            ),
            if (selected)
              Icon(Icons.check_circle, color: role.color)
            else
              Icon(Icons.radio_button_unchecked, color: colors.outline),
          ],
        ),
      ),
    );
  }
}
