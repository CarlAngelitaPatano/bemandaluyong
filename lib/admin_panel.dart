import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'theme.dart';
import 'motion.dart';
import 'accreditation.dart';
import 'announcements.dart';
import 'analytics_dashboard.dart';
import 'feedback_page.dart'; // FeedbackSchema

// ===========================================================================
// CCAT Staff Panel
//
// The staff-facing half of the system. Signed-in CCAT officers can:
//   • review accreditation applications and approve / reject them
//   • publish official city announcements (which notify every app user)
//   • open the sentiment analytics dashboard
//
// Access is controlled by a Firestore document: `staff/{uid}`. Creating that
// document in the Firebase console makes an account a CCAT officer, so no
// credentials are ever hard-coded in the app.
// ===========================================================================

/// Built-in demonstration accounts.
///
/// Logging in with either email grants CCAT access immediately, without
/// needing a `staff/{uid}` document — handy for presentations. Real officers
/// are registered in Firestore.
const String kAdminEmail = 'admin@bemandaluyong.com';
const String kStaffEmail = 'staff@bemandaluyong.com';

/// Author shown on announcements published from the app.
const String kAnnouncementPublisher = 'Office of the City Mayor';

/// Two levels of CCAT access.
///   • [CcatRole.admin] — full control: accreditation decisions, user records,
///     announcements, events and analytics.
///   • [CcatRole.staff] — day-to-day work: manage events, publish
///     announcements and read visitor feedback. No accreditation decisions
///     and no access to user records.
enum CcatRole { none, staff, admin }

class StaffAccess {
  StaffAccess._();

  static const String collection = 'staff';

  /// Cached so the UI can check synchronously after the first load.
  static CcatRole role = CcatRole.none;

  /// Any CCAT account (staff or admin).
  static bool get isStaff => role != CcatRole.none;

  /// Full administrator only.
  static bool get isAdmin => role == CcatRole.admin;

  /// Staff tier specifically (not an administrator).
  static bool get isStaffOnly => role == CcatRole.staff;

  /// Determines the signed-in account's CCAT role.
  static Future<CcatRole> check() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      role = CcatRole.none;
      return role;
    }

    // Built-in demonstration accounts.
    final email = user.email?.toLowerCase();
    if (email == kAdminEmail) {
      role = CcatRole.admin;
      return role;
    }
    if (email == kStaffEmail) {
      role = CcatRole.staff;
      return role;
    }

    try {
      final doc = await FirebaseFirestore.instance
          .collection(collection)
          .doc(user.uid)
          .get();
      if (!doc.exists) {
        role = CcatRole.none;
      } else {
        // A `role` field of "admin" grants full access; anything else
        // (or a missing field) is the staff tier.
        final r = (doc.data()?['role'] ?? 'staff').toString().toLowerCase();
        role = r == 'admin' ? CcatRole.admin : CcatRole.staff;
      }
    } catch (_) {
      role = CcatRole.none;
    }
    return role;
  }
}

class AdminPanelPage extends StatelessWidget {
  const AdminPanelPage({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('CCAT Admin Dashboard')),
        body: const AdminPanelView(),
      );
}

/// The admin dashboard without its own Scaffold, so it can also be used
/// directly as a bottom-navigation tab.
class AdminPanelView extends StatelessWidget {
  const AdminPanelView({super.key});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;

    return DefaultTabController(
      length: 4,
      child: Column(
        children: [
          Material(
            color: colors.surface,
            child: TabBar(
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              tabs: const [
                Tab(icon: Icon(Icons.dashboard_outlined), text: 'Overview'),
                Tab(
                    icon: Icon(Icons.assignment_outlined),
                    text: 'Applications'),
                Tab(icon: Icon(Icons.campaign_outlined), text: 'Announcements'),
                Tab(icon: Icon(Icons.people_outline), text: 'Users'),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              children: [
                const _OverviewTab(),
                const _ApplicationsReviewTab(),
                _AnnouncementsAdminTab(textTheme: text),
                const _UsersTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Tab 0 — system overview: everything at a glance
// ---------------------------------------------------------------------------
class _OverviewTab extends StatefulWidget {
  const _OverviewTab();

  @override
  State<_OverviewTab> createState() => _OverviewTabState();
}

class _OverviewTabState extends State<_OverviewTab> {
  late Future<_Overview> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_Overview> _load() async {
    final db = FirebaseFirestore.instance;
    final results = await Future.wait([
      db.collection('users').get(),
      db.collection(FeedbackSchema.collection).get(),
      db.collection(kAccreditationCollection).get(),
      db.collection(kAnnouncementCollection).get(),
    ]);

    final users = results[0].docs;
    final feedback = results[1].docs;
    final apps = results[2].docs;
    final anns = results[3].docs;

    int pos = 0, neu = 0, neg = 0;
    double ratingSum = 0;
    int rated = 0;
    for (final d in feedback) {
      final m = d.data();
      switch ((m['sentiment'] ?? '').toString()) {
        case 'positive':
          pos++;
        case 'negative':
          neg++;
        default:
          neu++;
      }
      final r = (m['rating'] as num?)?.toDouble() ?? 0;
      if (r > 0) {
        ratingSum += r;
        rated++;
      }
    }

    return _Overview(
      totalUsers: users.length,
      tourists: users
          .where((d) => (d.data()['userType'] ?? '') == 'Tourist')
          .length,
      trailCompleters:
          users.where((d) => d.data()['trailCompleted'] == true).length,
      totalFeedback: feedback.length,
      positive: pos,
      neutral: neu,
      negative: neg,
      avgRating: rated == 0 ? 0 : ratingSum / rated,
      totalApplications: apps.length,
      pendingApplications: apps
          .where((d) => (d.data()['status'] ?? 'pending') == 'pending')
          .length,
      approvedApplications:
          apps.where((d) => (d.data()['status'] ?? '') == 'approved').length,
      totalAnnouncements: anns.length,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return RefreshIndicator(
      onRefresh: () async => setState(() => _future = _load()),
      child: FutureBuilder<_Overview>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return ListView(
              padding: const EdgeInsets.all(AppSpacing.xl),
              children: [
                Icon(Icons.lock_outline, size: 48, color: colors.outline),
                const SizedBox(height: AppSpacing.l),
                Text(
                  'Could not read the system data.\n\nMake sure this account '
                  'is listed in the Firestore "staff" collection, and that the '
                  'security rules allow staff to read all records.',
                  textAlign: TextAlign.center,
                  style: text.bodyMedium,
                ),
              ],
            );
          }

          final o = snap.data!;
          return ListView(
            padding: const EdgeInsets.all(AppSpacing.l),
            children: [
              Reveal(
                delayMs: 0,
                child: Text('System overview', style: text.titleLarge),
              ),
              const SizedBox(height: 4),
              Reveal(
                delayMs: 30,
                child: Text(
                  'Live totals across the whole Be@Mandaluyong system.',
                  style: text.bodySmall?.copyWith(color: colors.outline),
                ),
              ),
              const SizedBox(height: AppSpacing.xl),

              // ---- Users ----
              Reveal(
                delayMs: 60,
                child: Row(children: [
                  _Stat(
                      label: 'Registered users',
                      value: '${o.totalUsers}',
                      icon: Icons.people_outline),
                  const SizedBox(width: AppSpacing.m),
                  _Stat(
                      label: 'Trail completions',
                      value: '${o.trailCompleters}',
                      icon: Icons.workspace_premium_outlined,
                      color: AppTheme.brandGold),
                ]),
              ),
              const SizedBox(height: AppSpacing.m),
              Reveal(
                delayMs: 90,
                child: Row(children: [
                  _Stat(
                      label: 'Feedback received',
                      value: '${o.totalFeedback}',
                      icon: Icons.forum_outlined),
                  const SizedBox(width: AppSpacing.m),
                  _Stat(
                      label: 'Average rating',
                      value: o.avgRating.toStringAsFixed(1),
                      icon: Icons.star_rounded,
                      color: AppTheme.brandGold),
                ]),
              ),
              const SizedBox(height: AppSpacing.m),
              Reveal(
                delayMs: 120,
                child: Row(children: [
                  _Stat(
                      label: 'Pending applications',
                      value: '${o.pendingApplications}',
                      icon: Icons.pending_actions_outlined,
                      color: o.pendingApplications > 0
                          ? const Color(0xFFEF6C00)
                          : null),
                  const SizedBox(width: AppSpacing.m),
                  _Stat(
                      label: 'Accredited businesses',
                      value: '${o.approvedApplications}',
                      icon: Icons.verified_outlined,
                      color: const Color(0xFF2E7D32)),
                ]),
              ),
              const SizedBox(height: AppSpacing.xl),

              // ---- Sentiment summary ----
              Reveal(
                delayMs: 160,
                child: Text('Visitor sentiment', style: text.titleMedium),
              ),
              const SizedBox(height: AppSpacing.m),
              Reveal(
                delayMs: 190,
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.l),
                    child: Column(
                      children: [
                        _Bar(
                            label: 'Positive',
                            count: o.positive,
                            total: o.totalFeedback,
                            color: const Color(0xFF2E7D32)),
                        const SizedBox(height: AppSpacing.m),
                        _Bar(
                            label: 'Neutral',
                            count: o.neutral,
                            total: o.totalFeedback,
                            color: const Color(0xFF9E9E9E)),
                        const SizedBox(height: AppSpacing.m),
                        _Bar(
                            label: 'Negative',
                            count: o.negative,
                            total: o.totalFeedback,
                            color: const Color(0xFFC62828)),
                        const SizedBox(height: AppSpacing.l),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) =>
                                      const AnalyticsDashboardPage()),
                            ),
                            icon: const Icon(Icons.insights_outlined),
                            label: const Text('Open full analytics'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.xl),

              // ---- Content totals ----
              Reveal(
                delayMs: 240,
                child: Card(
                  child: Column(
                    children: [
                      ListTile(
                        leading: const Icon(Icons.campaign_outlined),
                        title: const Text('Published announcements'),
                        trailing: Text('${o.totalAnnouncements}',
                            style: text.titleMedium),
                      ),
                      const Divider(height: 1),
                      ListTile(
                        leading: const Icon(Icons.assignment_outlined),
                        title: const Text('Total applications'),
                        trailing: Text('${o.totalApplications}',
                            style: text.titleMedium),
                      ),
                      const Divider(height: 1),
                      ListTile(
                        leading: const Icon(Icons.luggage_outlined),
                        title: const Text('Tourists / Mandaleños'),
                        trailing: Text(
                            '${o.tourists} / ${o.totalUsers - o.tourists}',
                            style: text.titleMedium),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Overview {
  final int totalUsers, tourists, trailCompleters;
  final int totalFeedback, positive, neutral, negative;
  final double avgRating;
  final int totalApplications, pendingApplications, approvedApplications;
  final int totalAnnouncements;

  const _Overview({
    required this.totalUsers,
    required this.tourists,
    required this.trailCompleters,
    required this.totalFeedback,
    required this.positive,
    required this.neutral,
    required this.negative,
    required this.avgRating,
    required this.totalApplications,
    required this.pendingApplications,
    required this.approvedApplications,
    required this.totalAnnouncements,
  });
}

class _Stat extends StatelessWidget {
  const _Stat({
    required this.label,
    required this.value,
    required this.icon,
    this.color,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.l),
        decoration: BoxDecoration(
          color: colors.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color ?? colors.primary, size: 22),
            const SizedBox(height: AppSpacing.s),
            Text(value,
                style: text.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w700, color: color)),
            Text(label,
                style: text.bodySmall?.copyWith(color: colors.outline)),
          ],
        ),
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({
    required this.label,
    required this.count,
    required this.total,
    required this.color,
  });

  final String label;
  final int count;
  final int total;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;
    final pct = total == 0 ? 0.0 : count / total;
    return Column(
      children: [
        Row(children: [
          Container(
              width: 10,
              height: 10,
              decoration:
                  BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: AppSpacing.s),
          Expanded(
              child: Text(label,
                  style: text.bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w600))),
          Text('$count  (${(pct * 100).toStringAsFixed(0)}%)',
              style: text.bodySmall),
        ]),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(99),
          child: LinearProgressIndicator(
            value: pct,
            minHeight: 8,
            backgroundColor: colors.surfaceContainerHighest,
            color: color,
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Tab 3 — every registered user and their progress
// ---------------------------------------------------------------------------
class _UsersTab extends StatelessWidget {
  const _UsersTab();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.collection('users').snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.xl),
              child: Text(
                'Could not read users. This account must be in the Firestore '
                '"staff" collection and the rules must allow staff reads.',
                textAlign: TextAlign.center,
                style: text.bodyMedium,
              ),
            ),
          );
        }
        final docs = snap.data?.docs ?? [];
        if (docs.isEmpty) {
          return const Center(child: Text('No registered users yet.'));
        }

        return ListView(
          padding: const EdgeInsets.all(AppSpacing.l),
          children: [
            Text('${docs.length} registered users', style: text.titleMedium),
            const SizedBox(height: AppSpacing.m),
            for (final d in docs)
              Builder(builder: (context) {
                final m = d.data();
                final visited = (m['visitedCount'] as num?)?.toInt() ?? 0;
                final done = m['trailCompleted'] == true;
                final type = (m['userType'] ?? 'Tourist').toString();
                return Card(
                  margin: const EdgeInsets.only(bottom: AppSpacing.s),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor:
                          colors.primary.withValues(alpha: 0.12),
                      child: Icon(
                        type == 'Tourist'
                            ? Icons.luggage_rounded
                            : Icons.home_rounded,
                        color: colors.primary,
                        size: 20,
                      ),
                    ),
                    title: Text((m['displayName'] ?? 'Unnamed').toString()),
                    subtitle: Text(
                      '${(m['email'] ?? '').toString()}\n$type · '
                      '$visited churches visited',
                    ),
                    isThreeLine: true,
                    trailing: done
                        ? const Icon(Icons.workspace_premium,
                            color: AppTheme.brandGold)
                        : null,
                  ),
                );
              }),
          ],
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Tab 1 — review accreditation applications
// ---------------------------------------------------------------------------
class _ApplicationsReviewTab extends StatelessWidget {
  const _ApplicationsReviewTab();

  Future<void> _setStatus(
      BuildContext context, String docId, AccreditationStatus status) async {
    try {
      await FirebaseFirestore.instance
          .collection(kAccreditationCollection)
          .doc(docId)
          .update({
        'status': status.id,
        'updatedAt': FieldValue.serverTimestamp(),
        'reviewedBy': FirebaseAuth.instance.currentUser?.email ?? '',
      });
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Marked as ${status.label}')),
        );
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not update the application.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection(kAccreditationCollection)
          .snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = snap.data?.docs ?? [];
        if (docs.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.xxl),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.inbox_outlined, size: 52, color: colors.outline),
                  const SizedBox(height: AppSpacing.m),
                  Text('No applications to review',
                      style: text.titleMedium),
                ],
              ),
            ),
          );
        }

        return ListView(
          padding: const EdgeInsets.all(AppSpacing.l),
          children: [
            for (int i = 0; i < docs.length; i++)
              Reveal(
                delayMs: i * 60,
                child: _ReviewCard(
                  doc: docs[i],
                  onSetStatus: (s) => _setStatus(context, docs[i].id, s),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _ReviewCard extends StatelessWidget {
  const _ReviewCard({required this.doc, required this.onSetStatus});

  final QueryDocumentSnapshot<Map<String, dynamic>> doc;
  final void Function(AccreditationStatus) onSetStatus;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final m = doc.data();
    final status = statusFromId(m['status']?.toString());
    final reqs = Map<String, dynamic>.from(m['requirements'] ?? {});
    final met = kRequirements.where((r) => reqs[r] == true).length;

    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.m),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.l),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text((m['businessName'] ?? '').toString(),
                      style: text.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700)),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: status.color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Text(status.label,
                      style: TextStyle(
                          color: status.color,
                          fontWeight: FontWeight.w700,
                          fontSize: 12)),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text((m['businessType'] ?? '').toString(),
                style: text.bodySmall?.copyWith(color: colors.outline)),
            const SizedBox(height: AppSpacing.m),
            _row(Icons.person_outline, (m['ownerName'] ?? '').toString()),
            _row(Icons.location_on_outlined, (m['address'] ?? '').toString()),
            _row(Icons.phone_outlined, (m['contact'] ?? '').toString()),
            _row(Icons.badge_outlined,
                'Permit: ${(m['permitNumber'] ?? '').toString()}'),
            const SizedBox(height: AppSpacing.s),
            Text('Requirements: $met of ${kRequirements.length} declared',
                style: text.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: met == kRequirements.length
                        ? AppTheme.brandGold
                        : colors.outline)),
            const SizedBox(height: AppSpacing.m),
            Wrap(
              spacing: AppSpacing.s,
              runSpacing: AppSpacing.s,
              children: [
                FilledButton.icon(
                  onPressed: () => onSetStatus(AccreditationStatus.approved),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF2E7D32),
                    foregroundColor: Colors.white,
                  ),
                  icon: const Icon(Icons.check, size: 18),
                  label: const Text('Approve'),
                ),
                OutlinedButton.icon(
                  onPressed: () => onSetStatus(AccreditationStatus.underReview),
                  icon: const Icon(Icons.fact_check_outlined, size: 18),
                  label: const Text('Under review'),
                ),
                OutlinedButton.icon(
                  onPressed: () => onSetStatus(AccreditationStatus.rejected),
                  style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFC62828)),
                  icon: const Icon(Icons.close, size: 18),
                  label: const Text('Reject'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(IconData icon, String value) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(
          children: [
            Icon(icon, size: 15),
            const SizedBox(width: 8),
            Expanded(child: Text(value, style: const TextStyle(fontSize: 13))),
          ],
        ),
      );
}

// ---------------------------------------------------------------------------
// Tab 2 — publish announcements
// ---------------------------------------------------------------------------
class _AnnouncementsAdminTab extends StatefulWidget {
  const _AnnouncementsAdminTab({required this.textTheme});
  final TextTheme textTheme;

  @override
  State<_AnnouncementsAdminTab> createState() =>
      _AnnouncementsAdminTabState();
}

class _AnnouncementsAdminTabState extends State<_AnnouncementsAdminTab> {
  final _formKey = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _body = TextEditingController();
  String _category = 'General';
  bool _pinned = false;
  bool _sending = false;

  static const _categories = ['General', 'Advisory', 'Event', 'Emergency'];

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _publish() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _sending = true);
    try {
      await FirebaseFirestore.instance
          .collection(kAnnouncementCollection)
          .add({
        'title': _title.text.trim(),
        'body': _body.text.trim(),
        'category': _category,
        'author': 'Office of the City Mayor',
        'pinned': _pinned,
        'publishedAt': FieldValue.serverTimestamp(),
        'postedBy': FirebaseAuth.instance.currentUser?.email ?? '',
      });
      if (!mounted) return;
      _title.clear();
      _body.clear();
      setState(() {
        _category = 'General';
        _pinned = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Announcement published — users will be notified')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not publish. Check connection.')),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _delete(String id) async {
    try {
      await FirebaseFirestore.instance
          .collection(kAnnouncementCollection)
          .doc(id)
          .delete();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final text = widget.textTheme;

    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.all(AppSpacing.l),
        children: [
          Text('Publish an announcement', style: text.titleMedium),
          const SizedBox(height: 4),
          Text(
            'Every app user receives a notification when this is posted.',
            style: text.bodySmall,
          ),
          const SizedBox(height: AppSpacing.m),
          TextFormField(
            controller: _title,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Headline',
              prefixIcon: Icon(Icons.title),
              border: OutlineInputBorder(),
            ),
            validator: (v) =>
                (v == null || v.trim().isEmpty) ? 'Enter a headline' : null,
          ),
          const SizedBox(height: AppSpacing.m),
          TextFormField(
            controller: _body,
            maxLines: 5,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Details',
              alignLabelWithHint: true,
              border: OutlineInputBorder(),
            ),
            validator: (v) =>
                (v == null || v.trim().isEmpty) ? 'Enter the details' : null,
          ),
          const SizedBox(height: AppSpacing.m),
          DropdownButtonFormField<String>(
            initialValue: _category,
            decoration: const InputDecoration(
              labelText: 'Category',
              prefixIcon: Icon(Icons.label_outline),
              border: OutlineInputBorder(),
            ),
            items: [
              for (final c in _categories)
                DropdownMenuItem(value: c, child: Text(c)),
            ],
            onChanged: (v) => setState(() => _category = v ?? _category),
          ),
          CheckboxListTile(
            value: _pinned,
            onChanged: (v) => setState(() => _pinned = v ?? false),
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
            title: const Text('Pin to the top'),
          ),
          const SizedBox(height: AppSpacing.s),
          FilledButton.icon(
            onPressed: _sending ? null : _publish,
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.m),
            ),
            icon: _sending
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.campaign_rounded),
            label: Text(_sending ? 'Publishing…' : 'Publish announcement'),
          ),
          const SizedBox(height: AppSpacing.xxl),

          Text('Published announcements', style: text.titleMedium),
          const SizedBox(height: AppSpacing.s),
          StreamBuilder<List<Announcement>>(
            stream: AnnouncementService.stream(),
            builder: (context, snap) {
              final items = snap.data ?? [];
              if (items.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.all(AppSpacing.l),
                  child: Text('Nothing published yet.'),
                );
              }
              return Column(
                children: [
                  for (final a in items)
                    Card(
                      margin: const EdgeInsets.only(bottom: AppSpacing.s),
                      child: ListTile(
                        leading: Icon(a.icon, color: a.color),
                        title: Text(a.title),
                        subtitle: Text(a.category),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () => _delete(a.id),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}
