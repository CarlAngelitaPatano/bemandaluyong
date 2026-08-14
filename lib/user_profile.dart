import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ===========================================================================
// User profile — date of birth and age.
//
// The Heritage Church Trail asks people to travel to real locations around
// the city and verify each visit with photos, so it is restricted to users
// aged [kMinimumTrailAge] and above. Younger users can still browse every
// other part of the app.
// ===========================================================================

/// Minimum age required to take part in the Heritage Church Trail.
const int kMinimumTrailAge = 17;

class UserProfileStore {
  UserProfileStore._();

  /// Cached birth date of the signed-in user, if known.
  static DateTime? birthDate;

  /// Chosen during sign-up, before the account exists.
  static DateTime? pendingSignupBirthDate;

  static String? _key() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    return uid == null ? null : 'birth_date_$uid';
  }

  static Future<void> save(DateTime date) async {
    birthDate = date;
    final key = _key();
    if (key == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, date.toIso8601String());
  }

  static Future<DateTime?> load() async {
    final key = _key();
    if (key == null) return null;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(key);
    birthDate = raw == null ? null : DateTime.tryParse(raw);
    return birthDate;
  }

  /// Age in whole years, or null if the birth date isn't known.
  static int? get age => ageFrom(birthDate);

  static int? ageFrom(DateTime? d) {
    if (d == null) return null;
    final now = DateTime.now();
    var years = now.year - d.year;
    // Subtract a year if the birthday hasn't happened yet this year.
    if (now.month < d.month || (now.month == d.month && now.day < d.day)) {
      years--;
    }
    return years;
  }

  /// True when the user is old enough for the Heritage Church Trail.
  /// Unknown birth dates are allowed through so existing accounts created
  /// before this feature are never locked out.
  static bool get canJoinTrail {
    final a = age;
    return a == null || a >= kMinimumTrailAge;
  }
}
