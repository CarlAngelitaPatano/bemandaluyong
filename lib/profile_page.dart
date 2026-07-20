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

  // Each account gets its own saved photo on this device.
  String? get _avatarKey => ProfileAvatarStore.keyForCurrentUser();

  @override
  void initState() {
    super.initState();
    _loadAvatar();
  }

  Future<void> _loadAvatar() async {
    final bytes = await ProfileAvatarStore.load();
    if (bytes != null && mounted) {
      setState(() => _avatarBytes = bytes);
    }
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
      final bytes = await img.readAsBytes();
      final key = _avatarKey;
      if (key == null) return;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(key, base64Encode(bytes));
      if (!mounted) return;
      setState(() => _avatarBytes = bytes);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profile photo updated')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not update the photo.')),
      );
    }
  }

  Future<void> _removeAvatar() async {
    final key = _avatarKey;
    if (key == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(key);
    if (!mounted) return;
    setState(() => _avatarBytes = null);
  }

  Future<void> _chooseAppearance() async {
    final current = ThemeController.instance.mode.value;
    final chosen = await showDialog<ThemeMode>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Appearance'),
        children: [
          for (final m in ThemeMode.values)
            RadioListTile<ThemeMode>(
              value: m,
              groupValue: current,
              title: Text(ThemeController.label(m)),
              onChanged: (v) => Navigator.pop(context, v),
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
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.xxl),

        // ----- Trail progress -----
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
                      color: completed ? success : colors.primary,
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.s),
                Text(
                  completed
                      ? 'Completed all $total stops 🎉'
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

        // ----- Achievements -----
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
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.feedback_outlined),
                title: const Text('Send feedback'),
                subtitle: const Text('Report a bug or share a suggestion'),
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
    final success = AppTheme.successFor(Theme.of(context).brightness);
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
                // Green check when the challenge is complete.
                if (earned)
                  CircleAvatar(
                    radius: 9,
                    backgroundColor: colors.surface,
                    child: Icon(Icons.check_circle, size: 16, color: success),
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
