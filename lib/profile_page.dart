import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'auth_pages.dart'; // RoleSelectPage (welcome screen) for logout
import 'heritage.dart'; // TrailProgress, kChurches, HeritageTrailPage
import 'theme.dart'; // AppTheme.cityRed
import 'theme_controller.dart'; // light/dark/system setting
import 'achievements.dart'; // TrailBadge, kBadges
import 'motion.dart'; // Reveal / PopIn animations
import 'face_check.dart'; // profile-photo face verification
import 'avatars.dart'; // built-in avatar option
import 'user_role.dart'; // Tourist / Mandaleño
import 'feedback_page.dart'; // visitor feedback → CCAT sentiment analysis
import 'staff_access.dart'; // CCAT roles + admin console
import 'events_manager.dart'; // staff event management

/// Loads/saves the current user's profile photo (stored on-device as base64,
/// keyed per account). Shared so other screens (e.g. the home app bar) can
/// show the same avatar.
class ProfileAvatarStore {
  ProfileAvatarStore._();

  static String? keyForCurrentUser() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    return uid == null ? null : 'profile_pic_$uid';
  }

  static Future<Uint8List?> load() async {
    final key = keyForCurrentUser();
    if (key == null) return null;
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getString(key);
    if (data == null) return null;
    try {
      return base64Decode(data);
    } catch (_) {
      return null;
    }
  }

  // ---- Built-in avatar (used instead of a photo, if chosen) ----

  static String? presetKeyForCurrentUser() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    return uid == null ? null : 'profile_avatar_$uid';
  }

  /// Id of the chosen built-in avatar, or null if none.
  static Future<String?> loadPreset() async {
    final key = presetKeyForCurrentUser();
    if (key == null) return null;
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(key);
  }
}

/// The Profile tab — shows the logged-in user and account actions.
/// Lives inside HomeShell, so it has no Scaffold of its own.
class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  User? get _user => FirebaseAuth.instance.currentUser;

  final ImagePicker _picker = ImagePicker();
  Uint8List? _avatarBytes; // saved profile photo, if any
  String? _presetId; // chosen built-in avatar, if any
  UserRole _role = UserRoleStore.current; // Tourist / Mandaleño

  /// Only the demo account may switch roles (to showcase both dashboards).
  bool get _isDemoAccount =>
      FirebaseAuth.instance.currentUser?.email?.toLowerCase() == kDemoEmail;

  // Each account gets its own saved photo on this device.
  String? get _avatarKey => ProfileAvatarStore.keyForCurrentUser();

  @override
  void initState() {
    super.initState();
    _loadAvatar();
  }

  Future<void> _loadAvatar() async {
    final bytes = await ProfileAvatarStore.load();
    final preset = await ProfileAvatarStore.loadPreset();
    final role = await UserRoleStore.load();
    await StaffAccess.check(); // is this account CCAT staff?
    if (mounted) {
      setState(() {
        _avatarBytes = bytes;
        _presetId = preset;
        _role = role;
      });
    }
  }

  /// Lets the user switch between Tourist and Mandaleño.
  Future<void> _changeRole() async {
    final chosen = await showModalBottomSheet<UserRole>(
      context: context,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('I am a…',
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 4),
              Text(
                'This changes what your home screen shows first.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: AppSpacing.l),
              RoleOptionCard(
                role: UserRole.tourist,
                selected: _role == UserRole.tourist,
                onTap: () => Navigator.pop(context, UserRole.tourist),
              ),
              const SizedBox(height: AppSpacing.m),
              RoleOptionCard(
                role: UserRole.mandaleno,
                selected: _role == UserRole.mandaleno,
                onTap: () => Navigator.pop(context, UserRole.mandaleno),
              ),
            ],
          ),
        ),
      ),
    );
    if (chosen == null) return;
    await UserRoleStore.save(chosen);
    if (!mounted) return;
    setState(() => _role = chosen);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('You\'re now browsing as ${chosen.label}')),
    );
  }

  /// Opens the photo source chooser (camera / gallery / remove).
  void _changeAvatar() {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined),
              title: const Text('Take a photo'),
              onTap: () {
                Navigator.pop(context);
                _pickAvatar(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from gallery'),
              onTap: () {
                Navigator.pop(context);
                _pickAvatar(ImageSource.gallery);
              },
            ),
            ListTile(
              leading: const Icon(Icons.face_retouching_natural_outlined),
              title: const Text('Use an avatar instead'),
              subtitle: const Text('No photo needed'),
              onTap: () {
                Navigator.pop(context);
                _pickPresetAvatar();
              },
            ),
            if (_avatarBytes != null)
              ListTile(
                leading: const Icon(Icons.delete_outline,
                    color: AppTheme.cityRed),
                title: const Text('Remove photo',
                    style: TextStyle(color: AppTheme.cityRed)),
                onTap: () {
                  Navigator.pop(context);
                  _removeAvatar();
                },
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickAvatar(ImageSource source) async {
    try {
      final img = await _picker.pickImage(
        source: source,
        maxWidth: 512,
        imageQuality: 85,
      );
      if (img == null) return;

      // ---- Security check: the photo must show a real human face ----
      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (_) => const AlertDialog(
            content: Row(
              children: [
                CircularProgressIndicator(),
                SizedBox(width: AppSpacing.l),
                Expanded(child: Text('Verifying your photo…')),
              ],
            ),
          ),
        );
      }
      final result = await FaceCheckService.check(img.path);
      if (mounted) Navigator.of(context).pop(); // close the checking dialog

      if (result != FaceCheck.ok && result != FaceCheck.failed) {
        if (!mounted) return;
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            icon: const Icon(Icons.no_accounts_outlined,
                color: AppTheme.cityRed, size: 40),
            title: const Text('Photo not accepted'),
            content: Text(result.message),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Try another photo'),
              ),
            ],
          ),
        );
        return; // blocked — nothing is saved
      }

      final bytes = await img.readAsBytes();
      final key = _avatarKey;
      if (key == null) return;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(key, base64Encode(bytes));
      if (!mounted) return;
      setState(() => _avatarBytes = bytes);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.verified_user, color: Colors.white, size: 20),
              const SizedBox(width: AppSpacing.s),
              const Expanded(child: Text('Face verified — photo updated')),
            ],
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not update the photo.')),
      );
    }
  }

  /// Lets the user pick one of the built-in avatars (no face photo needed).
  Future<void> _pickPresetAvatar() async {
    final id = await showAvatarPicker(context);
    if (id == null) return;
    final prefs = await SharedPreferences.getInstance();
    final presetKey = ProfileAvatarStore.presetKeyForCurrentUser();
    if (presetKey != null) await prefs.setString(presetKey, id);
    // An avatar replaces any uploaded photo.
    final photoKey = _avatarKey;
    if (photoKey != null) await prefs.remove(photoKey);
    if (!mounted) return;
    setState(() {
      _presetId = id;
      _avatarBytes = null;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Avatar updated')),
    );
  }

  Future<void> _removeAvatar() async {
    final key = _avatarKey;
    if (key == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(key);
    final presetKey = ProfileAvatarStore.presetKeyForCurrentUser();
    if (presetKey != null) await prefs.remove(presetKey);
    if (!mounted) return;
    setState(() {
      _avatarBytes = null;
      _presetId = null;
    });
  }

  Future<void> _chooseAppearance() async {
    final current = ThemeController.instance.mode.value;
    final chosen = await showDialog<ThemeMode>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Appearance'),
        children: [
          RadioGroup<ThemeMode>(
            groupValue: current,
            onChanged: (v) => Navigator.pop(context, v),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final m in ThemeMode.values)
                  RadioListTile<ThemeMode>(
                    value: m,
                    title: Text(ThemeController.label(m)),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
    if (chosen != null) {
      await ThemeController.instance.set(chosen);
      if (mounted) setState(() {}); // refresh the subtitle
    }
  }

  Future<void> _sendFeedback() async {
    // Change this to your preferred feedback inbox.
    const to = 'sagarinoemmanuel08@gmail.com';
    final uri = Uri(
      scheme: 'mailto',
      path: to,
      query: 'subject=${Uri.encodeComponent('Be@Mandaluyong feedback')}',
    );
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Please email us at $to')),
      );
    }
  }

  Future<void> _editName() async {
    final controller = TextEditingController(text: _user?.displayName ?? '');
    final newName = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit name'),
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
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (newName == null || newName.trim().isEmpty) return;
    await _user?.updateDisplayName(newName.trim());
    await _user?.reload();
    if (!mounted) return;
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Name updated')),
    );
  }

  Future<void> _logout() async {
    await FirebaseAuth.instance.signOut();
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const RoleSelectPage()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final success = AppTheme.successFor(Theme.of(context).brightness);
    final user = _user;
    final hasName = (user?.displayName?.trim().isNotEmpty) ?? false;
    final name = hasName ? user!.displayName!.trim() : 'Resident';
    final email = user?.email ?? '';
    final initial = name.isNotEmpty ? name[0].toUpperCase() : 'R';

    final visited = TrailProgress.visited.length;
    final total = kChurches.length;
    final completed = total > 0 && visited >= total;

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.l),
      children: [
        // ----- Header -----
        Center(
          child: Column(
            children: [
              GestureDetector(
                onTap: _changeAvatar,
                child: PopIn(
                  delayMs: 60,
                  child: Stack(
                  children: [
                    // Photo → built-in avatar → initial (in that order).
                    if (_avatarBytes == null &&
                        presetAvatarById(_presetId) != null)
                      PresetAvatarCircle(
                        avatar: presetAvatarById(_presetId)!,
                        radius: 48,
                      )
                    else
                      CircleAvatar(
                        radius: 48,
                        backgroundColor: colors.primaryContainer,
                        backgroundImage: _avatarBytes != null
                            ? MemoryImage(_avatarBytes!)
                            : null,
                        child: _avatarBytes == null
                            ? Text(
                                initial,
                                style: TextStyle(
                                  fontSize: 36,
                                  fontWeight: FontWeight.bold,
                                  color: colors.onPrimaryContainer,
                                ),
                              )
                            : null,
                      ),
                    // Small camera badge to show the photo is editable.
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: colors.primary,
                          shape: BoxShape.circle,
                          border: Border.all(color: colors.surface, width: 2),
                        ),
                        child: Icon(
                          Icons.camera_alt,
                          size: 16,
                          color: colors.onPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
                ),
              ),
              const SizedBox(height: AppSpacing.m),
              Text(name, style: text.titleLarge),
              const SizedBox(height: 2),
              Text(email, style: text.bodyMedium?.copyWith(color: colors.outline)),
              const SizedBox(height: AppSpacing.s),
              // Role badge — "CCAT Officer" for staff, Tourist/Mandaleño
              // for visitors.
              Builder(builder: (context) {
                final staff = StaffAccess.isStaff;
                final badgeColor =
                    staff ? colors.primary : _role.color;
                final badgeIcon = staff
                    ? Icons.admin_panel_settings_outlined
                    : _role.icon;
                final badgeLabel = staff ? 'CCAT Staff' : _role.label;
                return Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: badgeColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                        color: badgeColor.withValues(alpha: 0.5)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(badgeIcon, size: 15, color: badgeColor),
                      const SizedBox(width: 6),
                      Text(
                        badgeLabel,
                        style: text.labelMedium?.copyWith(
                          color: badgeColor,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.xxl),

        // ----- Trail progress (visitors only — not relevant to CCAT staff) --
        if (!StaffAccess.isStaff)
        Reveal(
          delayMs: 120,
          child: Card(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.l),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.church_outlined, color: colors.primary),
                    const SizedBox(width: AppSpacing.s),
                    Text('Heritage Church Trail', style: text.titleMedium),
                  ],
                ),
                const SizedBox(height: AppSpacing.m),
                ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  child: TweenAnimationBuilder<double>(
                    tween:
                        Tween(begin: 0, end: total == 0 ? 0 : visited / total),
                    duration: const Duration(milliseconds: 900),
                    curve: Curves.easeOutCubic,
                    builder: (context, v, _) => LinearProgressIndicator(
                      value: v,
                      minHeight: 10,
                      backgroundColor: colors.surfaceContainerHighest,
                      // Gold = progress/achievement.
                      color: AppTheme.brandGold,
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.s),
                Text(
                  completed
                      ? 'Completed all $total stops'
                      : '$visited of $total stops visited',
                  style: text.bodyMedium?.copyWith(
                    color: completed ? success : colors.outline,
                    fontWeight: completed ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
                const SizedBox(height: AppSpacing.m),
                FilledButton.tonalIcon(
                  onPressed: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const HeritageTrailPage()),
                    );
                    if (mounted) setState(() {}); // refresh progress on return
                  },
                  icon: const Icon(Icons.map_outlined),
                  label: Text(completed ? 'View the trail' : 'Continue the trail'),
                ),
              ],
            ),
          ),
          ),
        ),
        const SizedBox(height: AppSpacing.xl),

        // ----- Achievements (visitors only) -----
        if (!StaffAccess.isStaff) ...[
          Text('Achievements', style: text.titleMedium),
          const SizedBox(height: 2),
          Text(
            '${kBadges.where((b) => visited >= b.threshold).length} of '
            '${kBadges.length} earned',
            style: text.bodySmall?.copyWith(color: colors.outline),
          ),
          const SizedBox(height: AppSpacing.m),
          SizedBox(
            height: 110,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: kBadges.length,
              separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.l),
              // Badges pop in one after another with a springy bounce.
              itemBuilder: (context, i) => PopIn(
                delayMs: 250 + i * 90,
                child: _BadgeTile(
                  badge: kBadges[i],
                  earned: visited >= kBadges[i].threshold,
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
        ],

        // ----- Account -----
        Text('Account', style: text.titleMedium),
        const SizedBox(height: AppSpacing.s),
        Reveal(
          delayMs: 320,
          child: Card(
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: const Text('Edit name'),
                trailing: const Icon(Icons.chevron_right),
                onTap: _editName,
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.lock_reset_outlined),
                title: const Text('Change password'),
                subtitle: const Text('Set a new password'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const ChangePasswordPage()),
                ),
              ),
            ],
          ),
          ),
        ),
        const SizedBox(height: AppSpacing.xl),

        // ----- CCAT staff panel (only for registered staff accounts) -----
        if (StaffAccess.isStaff) ...[
          Reveal(
            delayMs: 300,
            child: Card(
              color: colors.primary.withValues(alpha: 0.06),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: colors.primary.withValues(alpha: 0.12),
                  child: Icon(Icons.admin_panel_settings_outlined,
                      color: colors.primary),
                ),
                title: const Text('CCAT Staff Console'),
                subtitle:
                    const Text('Events, announcements, visitor feedback'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const EventsManagerPage()),
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
        ],

        // ----- Settings -----
        Text('Settings', style: text.titleMedium),
        const SizedBox(height: AppSpacing.s),
        Reveal(
          delayMs: 400,
          child: Card(
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.brightness_6_outlined),
                title: const Text('Appearance'),
                subtitle: Text(
                  ThemeController.label(ThemeController.instance.mode.value),
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: _chooseAppearance,
              ),
              // Role switching is a demo-account convenience only, so both
              // the Tourist and Mandaleño dashboards can be shown in one
              // session. Regular users pick their role when signing up.
              if (_isDemoAccount) ...[
                const Divider(height: 1),
                ListTile(
                  leading: Icon(_role.icon, color: _role.color),
                  title: const Text('I am a…'),
                  subtitle: Text('${_role.label}  ·  demo only'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _changeRole,
                ),
              ],
              const Divider(height: 1),
              // Visitor feedback is for the public — CCAT accounts read it in
              // the analytics dashboard instead of submitting it.
              if (!StaffAccess.isStaff) ...[
                ListTile(
                  leading: const Icon(Icons.rate_review_outlined),
                  title: const Text('Share your feedback'),
                  subtitle: const Text('Rate your experience — sent to CCAT'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const FeedbackPage()),
                  ),
                ),
                const Divider(height: 1),
              ],
              ListTile(
                leading: const Icon(Icons.bug_report_outlined),
                title: const Text('Report a problem'),
                subtitle: const Text('Email the developers about a bug'),
                trailing: const Icon(Icons.chevron_right),
                onTap: _sendFeedback,
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.info_outline),
                title: const Text('About'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const AboutPage()),
                ),
              ),
            ],
          ),
          ),
        ),
        const SizedBox(height: AppSpacing.xl),

        // ----- Log out -----
        Reveal(
          delayMs: 480,
          child: OutlinedButton.icon(
            onPressed: _logout,
            style: OutlinedButton.styleFrom(foregroundColor: AppTheme.cityRed),
            icon: const Icon(Icons.logout),
            label: const Text('Log out'),
          ),
        ),
        const SizedBox(height: AppSpacing.xxl),
        Center(
          child: Text(
            'Be@Mandaluyong',
            style: text.labelMedium?.copyWith(color: colors.outline),
          ),
        ),
      ],
    );
  }
}

/// Simple About screen: logo, version, description, and credits.
class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('About')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.xl),
        children: [
          Center(
            child: Image.asset(
              'assets/icon/new_logo.png',
              height: 120,
              errorBuilder: (_, _, _) =>
                  Icon(Icons.location_city, size: 96, color: colors.primary),
            ),
          ),
          const SizedBox(height: AppSpacing.l),
          Center(
            child: Text(
              'Be@Mandaluyong',
              style: AppTheme.brandTextStyle(fontSize: 26, color: colors.primary),
            ),
          ),
          const SizedBox(height: 4),
          Center(
            child: Text('Version 1.0.0',
                style: text.bodyMedium?.copyWith(color: colors.outline)),
          ),
          const SizedBox(height: AppSpacing.xxl),
          Text('About the app', style: text.titleMedium),
          const SizedBox(height: AppSpacing.s),
          Text(
            'Be@Mandaluyong is a heritage, tourism, and civic app for the City '
            'of Mandaluyong. Discover historic churches through a guided trail, '
            'stay updated with city news and events, access city services, and '
            'explore the city\'s tourist attractions.',
            style: text.bodyLarge?.copyWith(height: 1.5),
          ),
          const SizedBox(height: AppSpacing.xxl),
          Text('Credits', style: text.titleMedium),
          const SizedBox(height: AppSpacing.s),
          _CreditRow(
            label: 'City of Mandaluyong',
            value: 'Seal, heritage & service information',
          ),
          _CreditRow(
            label: 'Maps',
            value: '© OpenStreetMap contributors',
          ),
          _CreditRow(
            label: 'Developed by',
            value: '4sight — student capstone project',
          ),
          const SizedBox(height: AppSpacing.xxl),
          Center(
            child: Text('© 2026 Be@Mandaluyong',
                style: text.bodySmall?.copyWith(color: colors.outline)),
          ),
        ],
      ),
    );
  }
}

class _CreditRow extends StatelessWidget {
  const _CreditRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.s),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
          Text(value,
              style: text.bodyMedium?.copyWith(color: colors.outline)),
        ],
      ),
    );
  }
}

/// A real in-app "Change password" flow: verifies the current password
/// (re-authentication) then updates the Firebase account password.
class ChangePasswordPage extends StatefulWidget {
  const ChangePasswordPage({super.key});

  @override
  State<ChangePasswordPage> createState() => _ChangePasswordPageState();
}

class _ChangePasswordPageState extends State<ChangePasswordPage> {
  final _formKey = GlobalKey<FormState>();
  final _current = TextEditingController();
  final _new = TextEditingController();
  final _confirm = TextEditingController();
  bool _obscureCurrent = true;
  bool _obscureNew = true;
  bool _obscureConfirm = true;
  bool _loading = false;

  @override
  void dispose() {
    _current.dispose();
    _new.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final user = FirebaseAuth.instance.currentUser;
    final email = user?.email;
    if (user == null || email == null) return;

    setState(() => _loading = true);
    try {
      // Re-authenticate with the current password (required by Firebase).
      final cred =
          EmailAuthProvider.credential(email: email, password: _current.text);
      await user.reauthenticateWithCredential(cred);
      // Then set the new password.
      await user.updatePassword(_new.text);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppTheme.successFor(Theme.of(context).brightness),
          content: const Text('Password changed successfully'),
        ),
      );
      Navigator.pop(context);
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      final msg = switch (e.code) {
        'wrong-password' ||
        'invalid-credential' =>
          'Your current password is incorrect.',
        'weak-password' =>
          'The new password is too weak (use at least 6 characters).',
        'requires-recent-login' =>
          'For security, please log out and log in again, then try.',
        'too-many-requests' =>
          'Too many attempts. Please wait a moment and try again.',
        _ => e.message ?? 'Could not change the password.',
      };
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not change the password.')),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Widget _passwordField({
    required TextEditingController controller,
    required String label,
    required bool obscure,
    required VoidCallback onToggle,
    required String? Function(String?) validator,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: obscure,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: const Icon(Icons.lock_outline),
        suffixIcon: IconButton(
          icon: Icon(obscure ? Icons.visibility_off : Icons.visibility),
          onPressed: onToggle,
        ),
        border: const OutlineInputBorder(),
      ),
      validator: validator,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Change password')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.xl),
          children: [
            const Text(
              'Enter your current password, then choose a new one '
              '(at least 6 characters).',
              style: TextStyle(height: 1.4),
            ),
            const SizedBox(height: AppSpacing.xl),
            _passwordField(
              controller: _current,
              label: 'Current password',
              obscure: _obscureCurrent,
              onToggle: () =>
                  setState(() => _obscureCurrent = !_obscureCurrent),
              validator: (v) => (v == null || v.isEmpty)
                  ? 'Enter your current password'
                  : null,
            ),
            const SizedBox(height: AppSpacing.l),
            _passwordField(
              controller: _new,
              label: 'New password',
              obscure: _obscureNew,
              onToggle: () => setState(() => _obscureNew = !_obscureNew),
              validator: (v) {
                if (v == null || v.length < 6) {
                  return 'Use at least 6 characters';
                }
                if (v == _current.text) {
                  return 'New password must be different';
                }
                return null;
              },
            ),
            const SizedBox(height: AppSpacing.l),
            _passwordField(
              controller: _confirm,
              label: 'Confirm new password',
              obscure: _obscureConfirm,
              onToggle: () =>
                  setState(() => _obscureConfirm = !_obscureConfirm),
              validator: (v) =>
                  v != _new.text ? 'Passwords do not match' : null,
            ),
            const SizedBox(height: AppSpacing.xxl),
            FilledButton.icon(
              onPressed: _loading ? null : _submit,
              icon: _loading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.check),
              style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(54)),
              label: Text(_loading ? 'Changing…' : 'Change password'),
            ),
          ],
        ),
      ),
    );
  }
}

class _BadgeTile extends StatelessWidget {
  const _BadgeTile({required this.badge, required this.earned});
  final TrailBadge badge;
  final bool earned;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return GestureDetector(
      onTap: () => ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(earned
              ? '${badge.title} — ${badge.desc}'
              : 'Locked — ${badge.desc}'),
        ),
      ),
      child: SizedBox(
        width: 78,
        child: Column(
          children: [
            Stack(
              alignment: Alignment.bottomRight,
              children: [
                CircleAvatar(
                  radius: 28,
                  backgroundColor: earned
                      ? colors.tertiaryContainer
                      : colors.surfaceContainerHighest,
                  // Locked badges show a lock; earned badges show their icon.
                  child: Icon(
                    earned ? badge.icon : Icons.lock,
                    color:
                        earned ? colors.onTertiaryContainer : colors.outline,
                  ),
                ),
                // Gold check when the challenge is complete (achievement).
                if (earned)
                  CircleAvatar(
                    radius: 9,
                    backgroundColor: colors.surface,
                    child: const Icon(Icons.check_circle,
                        size: 16, color: AppTheme.brandGold),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              badge.title,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: text.labelSmall?.copyWith(
                color: earned ? colors.onSurface : colors.outline,
                fontWeight: earned ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
