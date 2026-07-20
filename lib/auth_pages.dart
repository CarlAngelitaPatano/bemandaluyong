import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'main.dart'; // for HomeShell (the screen shown after login)
import 'theme.dart'; // light theme for the auth screens
import 'phone_signin.dart'; // phone number / SMS sign-in
import 'heritage.dart'; // TrailProgress (demo unlock)

/// Logging in with this email unlocks the whole app for demos (auto-completes
/// the Heritage Trail and skips email verification). Change it if you like.
const String kDemoEmail = 'demo@bemandaluyong.com';

// ---------------------------------------------------------------------------
// NOTE: These screens are UI-only for now. "Logging in" just checks that the
// form is filled in correctly, then opens the home screen. Connecting real
// accounts (Firebase: email/password + Google + password reset) is the next
// step — the buttons and flows are already here, ready to be wired up.
// ---------------------------------------------------------------------------

/// Shared email validator.
String? validateEmail(String? value) {
  if (value == null || value.trim().isEmpty) return 'Please enter your email';
  final emailRegex = RegExp(r'^[\w.+-]+@[\w-]+\.[\w.-]+$');
  if (!emailRegex.hasMatch(value.trim())) return 'Enter a valid email address';
  return null;
}

/// Shared password validator.
String? validatePassword(String? value) {
  if (value == null || value.isEmpty) return 'Please enter a password';
  if (value.length < 6) return 'Password must be at least 6 characters';
  return null;
}

/// Turns a Firebase auth error into a friendly, readable message.
String authErrorMessage(FirebaseAuthException e) {
  switch (e.code) {
    case 'invalid-email':
      return 'That email address looks invalid.';
    case 'user-disabled':
      return 'This account has been disabled.';
    case 'user-not-found':
    case 'wrong-password':
    case 'invalid-credential':
      return 'Incorrect email or password.';
    case 'email-already-in-use':
      return 'An account already exists for that email.';
    case 'weak-password':
      return 'Password is too weak (use at least 6 characters).';
    case 'network-request-failed':
      return 'No internet connection. Please try again.';
    case 'operation-not-allowed':
      return 'Email sign-in is not enabled in Firebase yet.';
    case 'too-many-requests':
      return 'Too many attempts. Please wait a moment and try again.';
    default:
      return e.message ?? 'Something went wrong. Please try again.';
  }
}

/// A "Continue with Google" button (UI only for now).
class GoogleButton extends StatefulWidget {
  const GoogleButton({super.key, required this.label});
  final String label;

  @override
  State<GoogleButton> createState() => _GoogleButtonState();
}

class _GoogleButtonState extends State<GoogleButton> {
  bool _loading = false;

  Future<void> _signInWithGoogle() async {
    setState(() => _loading = true);
    try {
      // Uses Firebase Auth's built-in federated flow (opens a secure browser
      // tab). No extra package needed.
      await FirebaseAuth.instance.signInWithProvider(GoogleAuthProvider());
      // Google sign-ins are remembered by default.
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('remember_me', true);
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const HomeShell()),
      );
    } on FirebaseAuthException catch (e) {
      // User dismissed the Google sheet — not an error.
      if (e.code == 'canceled' || e.code == 'web-context-canceled') return;
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(authErrorMessage(e))),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Google sign-in failed. Please try again.')),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: _loading ? null : _signInWithGoogle,
      icon: _loading
          ? const SizedBox(
              height: 20,
              width: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.g_mobiledata, size: 28),
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 14),
      ),
      label: Text(_loading ? 'Please wait…' : widget.label),
    );
  }
}

/// Small "or" divider used between email login and the Google button.
class OrDivider extends StatelessWidget {
  const OrDivider({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: const [
        Expanded(child: Divider()),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 12),
          child: Text('or'),
        ),
        Expanded(child: Divider()),
      ],
    );
  }
}

/// The Mandaluyong seal logo, with an icon fallback if the image is missing.
Widget _sealLogo(double size) => Image.asset(
      'assets/icon/new_logo.png',
      height: size,
      width: size,
      fit: BoxFit.contain,
      errorBuilder: (_, _, _) =>
          Icon(Icons.location_city, size: size * 0.7, color: const Color(0xFF0038A8)),
    );

/// Shared light, blue-tinted background used across the auth screens.
class _AuthBackground extends StatelessWidget {
  const _AuthBackground({required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Text(title),
        backgroundColor: const Color(0xFF0038A8),
        foregroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleTextStyle: const TextStyle(
          color: Colors.white,
          fontSize: 20,
          fontWeight: FontWeight.bold,
        ),
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFDDE9FB), Color(0xFFF7FAFF)],
          ),
        ),
        child: SafeArea(
          // Force the light theme so text stays dark and readable on the light
          // gradient even when the phone is in dark mode.
          child: Theme(data: AppTheme.light(), child: child),
        ),
      ),
    );
  }
}

// ===========================================================================
// 1) WELCOME  — the first screen the app shows
// ===========================================================================
class RoleSelectPage extends StatefulWidget {
  const RoleSelectPage({super.key});

  @override
  State<RoleSelectPage> createState() => _RoleSelectPageState();
}

class _RoleSelectPageState extends State<RoleSelectPage>
    with TickerProviderStateMixin {
  static const _blue = Color(0xFF0038A8);
  static const _deepBlue = Color(0xFF0B2E73);

  late final AnimationController _intro; // staged reveal
  late final AnimationController _spin; // rotating loader ring

  @override
  void initState() {
    super.initState();
    _spin = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat();
    _intro = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2800),
    )..forward();
    // Stop the ring once the intro finishes (it's faded out by then).
    _intro.addStatusListener((s) {
      if (s == AnimationStatus.completed) _spin.stop();
    });
  }

  @override
  void dispose() {
    _intro.dispose();
    _spin.dispose();
    super.dispose();
  }

  // A curved sub-animation over an interval of the intro timeline.
  Animation<double> _step(double a, double b, [Curve c = Curves.easeOut]) =>
      CurvedAnimation(parent: _intro, curve: Interval(a, b, curve: c));

  // Fade + slide-up reveal.
  Widget _reveal(Animation<double> t, Widget child) => FadeTransition(
        opacity: t,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.18),
            end: Offset.zero,
          ).animate(t),
          child: child,
        ),
      );

  Widget _logoCircle(String asset, IconData fallback) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: _blue.withValues(alpha: 0.15),
              blurRadius: 20,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Image.asset(
          asset,
          height: 104,
          width: 104,
          fit: BoxFit.contain,
          errorBuilder: (_, _, _) => Icon(fallback, size: 80, color: _blue),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final ringFade = Tween<double>(begin: 1, end: 0)
        .animate(_step(0.42, 0.60, Curves.easeIn));
    final logoOpacity = _step(0.46, 0.72);
    final logoScale =
        Tween<double>(begin: 0.85, end: 1).animate(_step(0.46, 0.74, Curves.easeOutBack));

    return Scaffold(
      body: Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFDDE9FB), Color(0xFFF7FAFF)],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Logo area: spinner ring fades out as the two logos fade in.
                SizedBox(
                  height: 150,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      FadeTransition(
                        opacity: ringFade,
                        child: RotationTransition(
                          turns: _spin,
                          child: const _ColorRing(size: 84),
                        ),
                      ),
                      FadeTransition(
                        opacity: logoOpacity,
                        child: ScaleTransition(
                          scale: logoScale,
                          child: _logoCircle(
                              'assets/icon/new_logo.png', Icons.location_city),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 22),
                _reveal(
                  _step(0.66, 0.80),
                  Text(
                    'Be@Mandaluyong',
                    textAlign: TextAlign.center,
                    style:
                        AppTheme.brandTextStyle(fontSize: 34, color: _deepBlue),
                  ),
                ),
                const SizedBox(height: 10),
                _reveal(
                  _step(0.72, 0.86),
                  const Text(
                    'Discover the heritage and culture of Mandaluyong',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF243043),
                      height: 1.4,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                _reveal(
                  _step(0.76, 0.90),
                  const Text(
                    'A Jose Rizal University student project',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF5B6472),
                    ),
                  ),
                ),
                const SizedBox(height: 40),
                _reveal(
                  _step(0.82, 0.96),
                  FilledButton.icon(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const LoginPage()),
                    ),
                    icon: const Icon(Icons.login),
                    style: FilledButton.styleFrom(
                      backgroundColor: _blue,
                      foregroundColor: Colors.white,
                      minimumSize: const Size.fromHeight(56),
                      textStyle: const TextStyle(
                          fontSize: 17, fontWeight: FontWeight.bold),
                    ),
                    label: const Text('Log in'),
                  ),
                ),
                const SizedBox(height: 14),
                _reveal(
                  _step(0.86, 1.0),
                  OutlinedButton.icon(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const RegisterPage()),
                    ),
                    icon: const Icon(Icons.person_add_outlined),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _blue,
                      side: const BorderSide(color: _blue, width: 1.5),
                      minimumSize: const Size.fromHeight(56),
                      textStyle: const TextStyle(
                          fontSize: 17, fontWeight: FontWeight.bold),
                    ),
                    label: const Text('Create account'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A 4-arc colored loader ring (echoes the eGovPH-style spinner), painted in
/// the Mandaluyong palette.
class _ColorRing extends StatelessWidget {
  const _ColorRing({required this.size});
  final double size;

  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: Size.square(size), painter: _RingPainter());
}

class _RingPainter extends CustomPainter {
  static const _colors = [
    Color(0xFF0038A8), // blue
    Color(0xFFFCD116), // yellow
    Color(0xFF0038A8), // blue
    Color(0xFFFCD116), // yellow
  ];

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 7.0;
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - stroke / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);
    const gap = 0.28; // radians between arcs
    const sweep = (2 * math.pi) / 4 - gap;
    for (int i = 0; i < 4; i++) {
      final start = i * (2 * math.pi / 4) + gap / 2;
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round
        ..color = _colors[i];
      canvas.drawArc(rect, start, sweep, false, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ===========================================================================
// 2) LOGIN  — used for both Resident and Admin (isAdmin switches the wording)
// ===========================================================================
class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _obscure = true;
  bool _loading = false;
  bool _remember = true;

  @override
  void initState() {
    super.initState();
    // Prefill the email if it was remembered last time.
    SharedPreferences.getInstance().then((prefs) {
      final saved = prefs.getString('saved_email');
      if (saved != null && saved.isNotEmpty && mounted) {
        setState(() => _email.text = saved);
      }
    });
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      final cred = await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: _email.text.trim(),
        password: _password.text,
      );
      await cred.user?.reload();
      final user = FirebaseAuth.instance.currentUser;
      final isDemo = user?.email?.toLowerCase() == kDemoEmail;

      // Block sign-in until the email is verified (the demo account is exempt).
      if (user != null && !user.emailVerified && !isDemo) {
        if (!mounted) return;
        final messenger = ScaffoldMessenger.of(context);
        await showDialog(
          context: context,
          builder: (dialogCtx) => AlertDialog(
            icon: Icon(Icons.mark_email_unread_outlined,
                color: Theme.of(dialogCtx).colorScheme.primary, size: 48),
            title: const Text('Verify your email first'),
            content: Text(
              'Your email (${_email.text.trim()}) isn\'t verified yet. Open the '
              'verification link we emailed you — check your Spam and All Mail '
              'folders, and search for "firebaseapp". Then log in again.',
            ),
            actions: [
              TextButton(
                onPressed: () async {
                  try {
                    await user.sendEmailVerification();
                    messenger.showSnackBar(const SnackBar(
                        content: Text('Verification email sent.')));
                  } catch (_) {
                    messenger.showSnackBar(const SnackBar(
                        content:
                            Text('Please wait a minute before resending.')));
                  }
                },
                child: const Text('Resend link'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogCtx),
                child: const Text('OK'),
              ),
            ],
          ),
        );
        await FirebaseAuth.instance.signOut();
        return;
      }

      // Save the "Remember me" choice + email for next launch.
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('remember_me', _remember);
      if (_remember) {
        await prefs.setString('saved_email', _email.text.trim());
      } else {
        await prefs.remove('saved_email');
      }

      if (isDemo) {
        // Demo account: unlock the whole trail so every feature is showcased.
        TrailProgress.unlockAll();
      } else {
        // Real account: restore this device's actual saved progress
        // (clears any leftover demo unlock from the same session).
        await TrailProgress.load();
      }

      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const HomeShell()),
      );
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(authErrorMessage(e))),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _AuthBackground(
      title: 'Log in',
      child: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, kToolbarHeight + 8, 24, 24),
          children: [
            Center(child: _sealLogo(88)),
            const SizedBox(height: 20),
            Text(
              'Welcome back',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineSmall
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            const Center(child: Text('Sign in to your account')),
            const SizedBox(height: 28),

            TextFormField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                labelText: 'Email',
                prefixIcon: Icon(Icons.email_outlined),
                border: OutlineInputBorder(),
              ),
              validator: validateEmail,
            ),
            const SizedBox(height: 16),

            TextFormField(
              controller: _password,
              obscureText: _obscure,
              decoration: InputDecoration(
                labelText: 'Password',
                prefixIcon: const Icon(Icons.lock_outline),
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
              validator: validatePassword,
            ),

            // Remember me + forgot password
            Row(
              children: [
                SizedBox(
                  width: 24,
                  height: 24,
                  child: Checkbox(
                    value: _remember,
                    onChanged: (v) => setState(() => _remember = v ?? true),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () => setState(() => _remember = !_remember),
                  child: const Text('Remember me'),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const ForgotPasswordPage()),
                  ),
                  child: const Text('Forgot password?'),
                ),
              ],
            ),
            const SizedBox(height: 8),

            FilledButton(
              onPressed: _loading ? null : _login,
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: _loading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('Log in'),
            ),
            const SizedBox(height: 20),

            const OrDivider(),
            const SizedBox(height: 20),

            const GoogleButton(label: 'Continue with Google'),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const PhoneSignInPage()),
              ),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
              ),
              icon: const Icon(Icons.sms_outlined),
              label: const Text('Sign in with phone number'),
            ),

            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text("Don't have an account?"),
                TextButton(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const RegisterPage()),
                  ),
                  child: const Text('Create one'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ===========================================================================
// 3) REGISTER  — new resident creates an account
// ===========================================================================
class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _obscure = true;
  bool _loading = false;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _register() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      final cred = await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: _email.text.trim(),
        password: _password.text,
      );
      await cred.user?.updateDisplayName(_name.text.trim());
      // Send a verification link to prove the email is real & owned by them.
      await cred.user?.sendEmailVerification();
      // Keep them signed out until they verify.
      await FirebaseAuth.instance.signOut();
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          icon: Icon(Icons.mark_email_read_outlined,
              color: AppTheme.successFor(Theme.of(context).brightness),
              size: 48),
          title: const Text('Verify your email'),
          content: Text(
            'Almost done, ${_name.text}! We sent a verification link to '
            '${_email.text.trim()}. Open it to confirm your email '
            '(check your spam folder too), then log in.',
          ),
          actions: [
            FilledButton(
              onPressed: () {
                Navigator.pop(context); // close dialog
                Navigator.pop(context); // back to login
              },
              child: const Text('Go to login'),
            ),
          ],
        ),
      );
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(authErrorMessage(e))),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _AuthBackground(
      title: 'Create Account',
      child: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, kToolbarHeight + 8, 24, 24),
          children: [
            Center(child: _sealLogo(80)),
            const SizedBox(height: 16),
            Center(
              child: Text(
                'Create your account',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            const SizedBox(height: 20),
            TextFormField(
              controller: _name,
              decoration: const InputDecoration(
                labelText: 'Full name',
                prefixIcon: Icon(Icons.person_outline),
                border: OutlineInputBorder(),
              ),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Please enter your name' : null,
            ),
            const SizedBox(height: 16),

            TextFormField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                labelText: 'Email',
                prefixIcon: Icon(Icons.email_outlined),
                border: OutlineInputBorder(),
              ),
              validator: validateEmail,
            ),
            const SizedBox(height: 16),

            TextFormField(
              controller: _password,
              obscureText: _obscure,
              decoration: InputDecoration(
                labelText: 'Password',
                prefixIcon: const Icon(Icons.lock_outline),
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
              validator: validatePassword,
            ),
            const SizedBox(height: 16),

            TextFormField(
              controller: _confirm,
              obscureText: _obscure,
              decoration: const InputDecoration(
                labelText: 'Confirm password',
                prefixIcon: Icon(Icons.lock_outline),
                border: OutlineInputBorder(),
              ),
              validator: (v) {
                if (v == null || v.isEmpty) return 'Please confirm your password';
                if (v != _password.text) return 'Passwords do not match';
                return null;
              },
            ),
            const SizedBox(height: 24),

            FilledButton(
              onPressed: _loading ? null : _register,
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: _loading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('Create account'),
            ),
            const SizedBox(height: 20),

            const OrDivider(),
            const SizedBox(height: 20),

            const GoogleButton(label: 'Sign up with Google'),
          ],
        ),
      ),
    );
  }
}

// ===========================================================================
// 4) FORGOT PASSWORD
// ===========================================================================
class ForgotPasswordPage extends StatefulWidget {
  const ForgotPasswordPage({super.key});

  @override
  State<ForgotPasswordPage> createState() => _ForgotPasswordPageState();
}

class _ForgotPasswordPageState extends State<ForgotPasswordPage> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  bool _loading = false;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _sendReset() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(
        email: _email.text.trim(),
      );
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          icon: const Icon(Icons.mark_email_read_outlined, size: 48),
          title: const Text('Check your email'),
          content: Text(
            'If an account exists for ${_email.text}, '
            'a password reset link has been sent.',
          ),
          actions: [
            FilledButton(
              onPressed: () {
                Navigator.pop(context); // close dialog
                Navigator.pop(context); // back to login
              },
              child: const Text('OK'),
            ),
          ],
        ),
      );
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(authErrorMessage(e))),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _AuthBackground(
      title: 'Forgot Password',
      child: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, kToolbarHeight + 8, 24, 24),
          children: [
            Center(child: _sealLogo(72)),
            const SizedBox(height: 20),
            const Text(
              'Enter the email linked to your account and we\'ll send you a '
              'link to reset your password.',
            ),
            const SizedBox(height: 24),
            TextFormField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                labelText: 'Email',
                prefixIcon: Icon(Icons.email_outlined),
                border: OutlineInputBorder(),
              ),
              validator: validateEmail,
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _loading ? null : _sendReset,
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: _loading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('Send reset link'),
            ),
          ],
        ),
      ),
    );
  }
}
