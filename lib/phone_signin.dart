import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'main.dart'; // HomeShell
import 'theme.dart';

// ===========================================================================
// Sign in with phone number (Firebase Phone Auth / SMS OTP).
// For testing without cost, register a TEST phone number + fixed code in the
// Firebase Console (Authentication → Sign-in method → Phone). Real SMS to real
// phones requires the paid Blaze plan.
// ===========================================================================
class PhoneSignInPage extends StatefulWidget {
  const PhoneSignInPage({super.key});

  @override
  State<PhoneSignInPage> createState() => _PhoneSignInPageState();
}

class _PhoneSignInPageState extends State<PhoneSignInPage> {
  final _phone = TextEditingController(text: '+63');
  final _code = TextEditingController();

  String? _verificationId;
  bool _codeSent = false;
  bool _loading = false;

  @override
  void dispose() {
    _phone.dispose();
    _code.dispose();
    super.dispose();
  }

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  Future<void> _goHome() async {
    // Phone sign-ins are remembered by default.
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('remember_me', true);
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const HomeShell()),
    );
  }

  Future<void> _sendCode() async {
    final phone = _phone.text.trim();
    if (phone.length < 8) {
      _snack('Enter a valid number with country code, e.g. +63917…');
      return;
    }
    setState(() => _loading = true);
    await FirebaseAuth.instance.verifyPhoneNumber(
      phoneNumber: phone,
      timeout: const Duration(seconds: 60),
      // Android may auto-verify without entering a code.
      verificationCompleted: (PhoneAuthCredential cred) async {
        try {
          await FirebaseAuth.instance.signInWithCredential(cred);
          if (mounted) _goHome();
        } catch (_) {}
      },
      verificationFailed: (FirebaseAuthException e) {
        if (!mounted) return;
        setState(() => _loading = false);
        _snack(e.message ?? 'Verification failed (${e.code}).');
      },
      codeSent: (String verificationId, int? resendToken) {
        if (!mounted) return;
        setState(() {
          _verificationId = verificationId;
          _codeSent = true;
          _loading = false;
        });
        _snack('Enter the 6-digit code.');
      },
      codeAutoRetrievalTimeout: (String verificationId) {
        _verificationId = verificationId;
      },
    );
  }

  Future<void> _verify() async {
    final vid = _verificationId;
    if (vid == null) return;
    final code = _code.text.trim();
    if (code.length < 6) {
      _snack('Enter the 6-digit code.');
      return;
    }
    setState(() => _loading = true);
    try {
      final cred =
          PhoneAuthProvider.credential(verificationId: vid, smsCode: code);
      await FirebaseAuth.instance.signInWithCredential(cred);
      if (!mounted) return;
      _goHome();
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      _snack(e.code == 'invalid-verification-code'
          ? 'Incorrect code. Please try again.'
          : (e.message ?? 'Could not verify the code.'));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Widget get _spinner => const SizedBox(
        width: 18,
        height: 18,
        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
      );

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Sign in with phone')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.xl),
        children: [
          const SizedBox(height: AppSpacing.s),
          Icon(Icons.sms_outlined, size: 56, color: colors.primary),
          const SizedBox(height: AppSpacing.l),
          Text(
            _codeSent ? 'Enter the code' : 'Enter your phone number',
            textAlign: TextAlign.center,
            style: text.titleLarge,
          ),
          const SizedBox(height: 6),
          Text(
            _codeSent
                ? 'We sent a 6-digit code to ${_phone.text.trim()}.'
                : 'Include your country code — e.g. +63 for the Philippines.',
            textAlign: TextAlign.center,
            style: text.bodyMedium?.copyWith(color: colors.outline),
          ),
          const SizedBox(height: AppSpacing.xxl),
          if (!_codeSent) ...[
            TextField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'Phone number',
                prefixIcon: Icon(Icons.phone_outlined),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: AppSpacing.l),
            FilledButton.icon(
              onPressed: _loading ? null : _sendCode,
              icon: _loading ? _spinner : const Icon(Icons.send),
              style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(54)),
              label: Text(_loading ? 'Sending…' : 'Send code'),
            ),
          ] else ...[
            TextField(
              controller: _code,
              keyboardType: TextInputType.number,
              maxLength: 6,
              decoration: const InputDecoration(
                labelText: '6-digit code',
                prefixIcon: Icon(Icons.lock_outline),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: AppSpacing.s),
            FilledButton.icon(
              onPressed: _loading ? null : _verify,
              icon: _loading ? _spinner : const Icon(Icons.check),
              style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(54)),
              label: Text(_loading ? 'Verifying…' : 'Verify & sign in'),
            ),
            const SizedBox(height: AppSpacing.s),
            TextButton(
              onPressed: _loading
                  ? null
                  : () => setState(() {
                        _codeSent = false;
                        _code.clear();
                      }),
              child: const Text('Change number'),
            ),
          ],
        ],
      ),
    );
  }
}
