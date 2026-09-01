import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

// ===========================================================================
// CCAT access control (mobile app).
//
// The mobile app serves two audiences:
//   • the public — Tourists and Mandaleños
//   • CCAT field staff — events, announcements, visitor feedback
//
// Administrator functions (approving business accreditations, managing user
// records, city-wide configuration) live in the CCAT WEB DASHBOARD, which
// shares the same Firebase project and the same `staff` registry. Keeping
// administration on the web means officers do that work at a desk, while the
// app stays focused on what staff need in the field.
// ===========================================================================

/// Built-in demonstration staff account. Logging in with this email grants
/// CCAT staff access immediately, without needing a `staff/{uid}` document —
/// handy for presentations. Real officers are registered in Firestore.
const String kStaffEmail = 'staff@bemandaluyong.com';

/// Author shown on announcements published from the app.
const String kAnnouncementPublisher = 'Office of the City Mayor';

/// Access level of the signed-in account.
enum CcatRole { none, staff }

class StaffAccess {
  StaffAccess._();

  /// Firestore collection listing every CCAT account. Shared with the website.
  static const String collection = 'staff';

  /// Cached so the UI can check synchronously after the first load.
  static CcatRole role = CcatRole.none;

  /// True for any registered CCAT account.
  static bool get isStaff => role == CcatRole.staff;

  /// Determines whether the signed-in account is CCAT staff.
  static Future<CcatRole> check() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      role = CcatRole.none;
      return role;
    }

    // Built-in demonstration account.
    if (user.email?.toLowerCase() == kStaffEmail) {
      role = CcatRole.staff;
      return role;
    }

    try {
      final doc = await FirebaseFirestore.instance
          .collection(collection)
          .doc(user.uid)
          .get();
      role = doc.exists ? CcatRole.staff : CcatRole.none;
    } catch (_) {
      role = CcatRole.none;
    }
    return role;
  }
}
