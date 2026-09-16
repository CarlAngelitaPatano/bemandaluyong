import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'heritage.dart'; // TrailProgress
import 'staff_access.dart'; // CcatRole
import 'tcims_api.dart'; // api_token + backend role
import 'user_profile.dart'; // date of birth
import 'user_role.dart'; // Tourist / Mandaleño

// ===========================================================================
// Signing out.
//
// Firebase sign-out only ends the Firebase session. Everything else this app
// keeps about a person lives in static fields and SharedPreferences, and none
// of it is tied to Firebase's lifecycle — so it survives a sign-out and is
// still sitting there when the next person signs in.
//
// That was not a cosmetic problem. The TCIMS api_token is the office's session
// for one account; left behind, the next person to use the phone would have
// filed their feedback and trail check-ins under the previous account's name.
// Trail progress behaved the same way, showing one person's verified churches
// to another.
//
// One place does the clearing now, so a new piece of per-person state has one
// obvious home rather than being forgotten here and remembered in a bug report.
// ===========================================================================
class AppSession {
  AppSession._();

  /// Ends the session completely: Firebase, the office's token, and every
  /// cached thing that belonged to the person signing out.
  ///
  /// Never throws — a sign-out that fails halfway is worse than one that
  /// quietly does as much as it can, because the alternative is leaving a
  /// signed-out person holding another account's token.
  static Future<void> signOut() async {
    // The backend session first. If anything below fails, this is the piece
    // that must not survive.
    try {
      await TcimsApi.clearToken();
    } catch (_) {}

    try {
      await TrailProgress.clear();
    } catch (_) {}

    try {
      final prefs = await SharedPreferences.getInstance();
      // Do not silently sign the next person straight back in.
      await prefs.setBool('remember_me', false);
    } catch (_) {}

    // In-memory caches. These are plain statics; nothing resets them on its
    // own, and each one is read synchronously while widgets build.
    StaffAccess.role = CcatRole.none;
    UserRoleStore.current = UserRole.tourist;
    UserProfileStore.birthDate = null;
    UserProfileStore.pendingSignupBirthDate = null;

    try {
      await FirebaseAuth.instance.signOut();
    } catch (_) {}
  }
}
