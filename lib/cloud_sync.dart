import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'user_profile.dart';

// ===========================================================================
// Cross-platform account sync.
//
// The mobile app and the CCAT website share ONE Firebase project
// (`be-mandaluyong-4sight`), so the same account signs in on both. This
// service keeps the user's Heritage Trail progress in the shared Firestore
// database, so a trail finished on the phone is already complete when the
// same person logs in on the website — and vice-versa.
//
// ---------------------------------------------------------------------------
// SHARED SCHEMA — collection `users`, document id = the Firebase uid.
// The website reads the same fields.
// ---------------------------------------------------------------------------
//   displayName      string
//   email            string
//   userType         string   'Tourist' | 'Mandaleño'
//   visitedChurches  array<string>   names of verified churches
//   visitedCount     number
//   trailCompleted   bool
//   completedAt      timestamp | null
//   lastSyncedAt     timestamp
//   platform         string   'mobile' (last client that wrote)
// ===========================================================================
class CloudSync {
  CloudSync._();

  static const String collection = 'users';

  static DocumentReference<Map<String, dynamic>>? _doc() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return null;
    return FirebaseFirestore.instance.collection(collection).doc(uid);
  }

  /// Pushes the current trail progress to the shared database.
  /// Safe to call often — failures are ignored so the app works offline.
  static Future<void> pushProgress({
    required Set<String> visited,
    required int totalChurches,
    required String userType,
  }) async {
    final doc = _doc();
    if (doc == null) return;
    final user = FirebaseAuth.instance.currentUser;
    final complete = totalChurches > 0 && visited.length >= totalChurches;

    try {
      await doc.set({
        'displayName': user?.displayName ?? '',
        'email': user?.email ?? '',
        'userType': userType,
        if (UserProfileStore.birthDate != null)
          'birthDate': UserProfileStore.birthDate!.toIso8601String(),
        if (UserProfileStore.age != null) 'age': UserProfileStore.age,
        'visitedChurches': visited.toList(),
        'visitedCount': visited.length,
        'trailCompleted': complete,
        if (complete) 'completedAt': FieldValue.serverTimestamp(),
        'lastSyncedAt': FieldValue.serverTimestamp(),
        'platform': 'mobile',
      }, SetOptions(merge: true)); // merge = never wipe the website's fields
    } catch (_) {
      // Offline or rules issue — local progress is still saved on the device.
    }
  }

  /// Reads the churches this account has verified on ANY platform.
  /// Returns null if unavailable (offline, not signed in, no record yet).
  static Future<Set<String>?> fetchVisited() async {
    final doc = _doc();
    if (doc == null) return null;
    try {
      final snap = await doc.get();
      if (!snap.exists) return null;
      final list = snap.data()?['visitedChurches'];
      if (list is List) return list.cast<String>().toSet();
      return null;
    } catch (_) {
      return null;
    }
  }
}
