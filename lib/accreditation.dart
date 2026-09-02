import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'theme.dart';
import 'motion.dart';

// ===========================================================================
// Policy Management — Tourism Business Accreditation
//
// Covers the policy module of Objective 1: tourism establishments apply for
// CCAT accreditation from the app, and can then monitor the status of their
// application and their compliance requirements.
//
// Applications are stored in the shared Firestore database so CCAT staff can
// process them from the web dashboard.
//
// ---------------------------------------------------------------------------
// SHARED SCHEMA — collection `accreditations`
//   businessName, businessType, ownerName, address, contact, email,
//   permitNumber, userId, status (pending|under_review|approved|rejected),
//   requirements (map of checklist items), submittedAt, updatedAt, source
// ===========================================================================

const String kAccreditationCollection = 'accreditations';

const List<String> kBusinessTypes = [
  'Restaurant / Eatery',
  'Hotel / Accommodation',
  'Travel & Tour Operator',
  'Retail / Souvenir Shop',
  'Entertainment / Recreation',
  'Cultural / Heritage Establishment',
  'Other tourism-related business',
];

/// Documents CCAT requires for accreditation.
const List<String> kRequirements = [
  'Mayor\'s / Business Permit',
  'DTI or SEC Registration',
  'BIR Certificate of Registration',
  'Sanitary Permit',
  'Fire Safety Inspection Certificate',
  'Barangay Clearance',
];

enum AccreditationStatus { pending, underReview, approved, rejected }

AccreditationStatus statusFromId(String? id) => switch (id) {
      'under_review' => AccreditationStatus.underReview,
      'approved' => AccreditationStatus.approved,
      'rejected' => AccreditationStatus.rejected,
      _ => AccreditationStatus.pending,
    };

extension AccreditationStatusInfo on AccreditationStatus {
  String get id => switch (this) {
        AccreditationStatus.pending => 'pending',
        AccreditationStatus.underReview => 'under_review',
        AccreditationStatus.approved => 'approved',
        AccreditationStatus.rejected => 'rejected',
      };

  String get label => switch (this) {
        AccreditationStatus.pending => 'Pending',
        AccreditationStatus.underReview => 'Under review',
        AccreditationStatus.approved => 'Accredited',
        AccreditationStatus.rejected => 'Not approved',
      };

  Color get color => switch (this) {
        AccreditationStatus.pending => const Color(0xFF9E9E9E),
        AccreditationStatus.underReview => const Color(0xFFEF6C00),
        AccreditationStatus.approved => const Color(0xFF2E7D32),
        AccreditationStatus.rejected => const Color(0xFFC62828),
      };

  IconData get icon => switch (this) {
        AccreditationStatus.pending => Icons.schedule_rounded,
        AccreditationStatus.underReview => Icons.fact_check_outlined,
        AccreditationStatus.approved => Icons.verified_rounded,
        AccreditationStatus.rejected => Icons.cancel_outlined,
      };
}

// ---------------------------------------------------------------------------
// Landing page: my applications + apply button
// ---------------------------------------------------------------------------
class AccreditationPage extends StatefulWidget {
  const AccreditationPage({super.key});

  @override
  State<AccreditationPage> createState() => _AccreditationPageState();
}

class _AccreditationPageState extends State<AccreditationPage> {
  late Future<List<_Application>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<_Application>> _load() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return [];
    final snap = await FirebaseFirestore.instance
        .collection(kAccreditationCollection)
        .where('userId', isEqualTo: uid)
        .get();

    final list = snap.docs.map((d) {
      final m = d.data();
      return _Application(
        businessName: (m['businessName'] ?? '').toString(),
        businessType: (m['businessType'] ?? '').toString(),
        status: statusFromId(m['status']?.toString()),
        requirements: Map<String, dynamic>.from(m['requirements'] ?? {}),
        submittedAt: m['submittedAt'] is Timestamp
            ? (m['submittedAt'] as Timestamp).toDate()
            : null,
      );
    }).toList();
    // Newest first (sorted client-side so no Firestore index is needed).
    list.sort((a, b) => (b.submittedAt ?? DateTime(2000))
        .compareTo(a.submittedAt ?? DateTime(2000)));
    return list;
  }

  Future<void> _refresh() async {
    setState(() => _future = _load());
    await _future.catchError((_) => <_Application>[]);
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Business Accreditation')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const AccreditationFormPage()),
          );
          _refresh();
        },
        icon: const Icon(Icons.add),
        label: const Text('Apply'),
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: FutureBuilder<List<_Application>>(
          future: _future,
          builder: (context, snap) {
            final apps = snap.data ?? [];
            return ListView(
              padding: const EdgeInsets.all(AppSpacing.l),
              children: [
                Reveal(
                  delayMs: 0,
                  child: Text('Tourism business accreditation',
                      style: text.titleLarge),
                ),
                const SizedBox(height: 4),
                Reveal(
                  delayMs: 40,
                  child: Text(
                    'Apply for CCAT accreditation and track your compliance '
                    'requirements. Accredited businesses are listed in the '
                    'city\'s official tourism directory.',
                    style: text.bodyMedium?.copyWith(color: colors.onSurfaceVariant),
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),

                if (snap.connectionState == ConnectionState.waiting)
                  const Center(child: Padding(
                    padding: EdgeInsets.all(AppSpacing.xxl),
                    child: CircularProgressIndicator(),
                  ))
                else if (apps.isEmpty)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.xl),
                      child: Column(
                        children: [
                          Icon(Icons.storefront_outlined,
                              size: 48, color: colors.outline),
                          const SizedBox(height: AppSpacing.m),
                          Text('No applications yet',
                              style: text.titleMedium),
                          const SizedBox(height: AppSpacing.s),
                          Text(
                            'Tap Apply to submit your tourism business for '
                            'accreditation.',
                            textAlign: TextAlign.center,
                            style: text.bodySmall
                                ?.copyWith(color: colors.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  for (int i = 0; i < apps.length; i++)
                    Reveal(
                      delayMs: 80 + i * 60,
                      child: _ApplicationCard(app: apps[i]),
                    ),
                const SizedBox(height: 80),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Application {
  final String businessName;
  final String businessType;
  final AccreditationStatus status;
  final Map<String, dynamic> requirements;
  final DateTime? submittedAt;

  const _Application({
    required this.businessName,
    required this.businessType,
    required this.status,
    required this.requirements,
    this.submittedAt,
  });
}

class _ApplicationCard extends StatelessWidget {
  const _ApplicationCard({required this.app});
  final _Application app;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final met = kRequirements.where((r) => app.requirements[r] == true).length;

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
                  child: Text(app.businessName,
                      style: text.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700)),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: app.status.color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(app.status.icon, size: 14, color: app.status.color),
                      const SizedBox(width: 5),
                      Text(app.status.label,
                          style: TextStyle(
                            color: app.status.color,
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                          )),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(app.businessType,
                style: text.bodySmall?.copyWith(color: colors.onSurfaceVariant)),
            const SizedBox(height: AppSpacing.m),
            Text('Compliance requirements: $met of ${kRequirements.length}',
                style: text.bodySmall),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: LinearProgressIndicator(
                value: met / kRequirements.length,
                minHeight: 8,
                backgroundColor: colors.surfaceContainerHighest,
                color: AppTheme.brandGold,
              ),
            ),
            const SizedBox(height: AppSpacing.m),
            for (final r in kRequirements)
              Row(
                children: [
                  Icon(
                    app.requirements[r] == true
                        ? Icons.check_circle
                        : Icons.radio_button_unchecked,
                    size: 16,
                    color: app.requirements[r] == true
                        ? AppTheme.brandGold
                        : colors.outlineVariant,
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: Text(r, style: text.bodySmall)),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Application form
// ---------------------------------------------------------------------------
class AccreditationFormPage extends StatefulWidget {
  const AccreditationFormPage({super.key});

  @override
  State<AccreditationFormPage> createState() => _AccreditationFormPageState();
}

class _AccreditationFormPageState extends State<AccreditationFormPage> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _owner = TextEditingController();
  final _address = TextEditingController();
  final _contact = TextEditingController();
  final _permit = TextEditingController();
  String _type = kBusinessTypes.first;
  final Map<String, bool> _reqs = {for (final r in kRequirements) r: false};
  bool _sending = false;

  @override
  void dispose() {
    _name.dispose();
    _owner.dispose();
    _address.dispose();
    _contact.dispose();
    _permit.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _sending = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      await FirebaseFirestore.instance
          .collection(kAccreditationCollection)
          .add({
        'businessName': _name.text.trim(),
        'businessType': _type,
        'ownerName': _owner.text.trim(),
        'address': _address.text.trim(),
        'contact': _contact.text.trim(),
        'permitNumber': _permit.text.trim(),
        'email': user?.email ?? '',
        'userId': user?.uid ?? '',
        'status': AccreditationStatus.pending.id,
        'requirements': _reqs,
        'submittedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'source': 'mobile',
      });

      if (!mounted) return;
      await showDialog(
        context: context,
        builder: (context) => AlertDialog(
          icon: const Icon(Icons.verified_outlined,
              color: AppTheme.brandGold, size: 44),
          title: const Text('Application submitted'),
          content: const Text(
            'Your accreditation application has been sent to the City Cultural '
            'Affairs and Tourism office. You can track its status here in the '
            'app.',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Done'),
            ),
          ],
        ),
      );
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Could not submit. Check your connection.')),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  String? _required(String? v) =>
      (v == null || v.trim().isEmpty) ? 'This field is required' : null;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Apply for accreditation')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.l),
          children: [
            Text('Business details', style: text.titleMedium),
            const SizedBox(height: AppSpacing.m),
            TextFormField(
              controller: _name,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Business name',
                prefixIcon: Icon(Icons.storefront_outlined),
                border: OutlineInputBorder(),
              ),
              validator: _required,
            ),
            const SizedBox(height: AppSpacing.m),
            DropdownButtonFormField<String>(
              initialValue: _type,
              decoration: const InputDecoration(
                labelText: 'Type of business',
                prefixIcon: Icon(Icons.category_outlined),
                border: OutlineInputBorder(),
              ),
              items: [
                for (final t in kBusinessTypes)
                  DropdownMenuItem(value: t, child: Text(t)),
              ],
              onChanged: (v) => setState(() => _type = v ?? _type),
            ),
            const SizedBox(height: AppSpacing.m),
            TextFormField(
              controller: _owner,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Owner / authorised representative',
                prefixIcon: Icon(Icons.person_outline),
                border: OutlineInputBorder(),
              ),
              validator: _required,
            ),
            const SizedBox(height: AppSpacing.m),
            TextFormField(
              controller: _address,
              decoration: const InputDecoration(
                labelText: 'Business address (Mandaluyong)',
                prefixIcon: Icon(Icons.location_on_outlined),
                border: OutlineInputBorder(),
              ),
              validator: _required,
            ),
            const SizedBox(height: AppSpacing.m),
            TextFormField(
              controller: _contact,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'Contact number',
                prefixIcon: Icon(Icons.phone_outlined),
                border: OutlineInputBorder(),
              ),
              validator: _required,
            ),
            const SizedBox(height: AppSpacing.m),
            TextFormField(
              controller: _permit,
              decoration: const InputDecoration(
                labelText: 'Business permit number',
                prefixIcon: Icon(Icons.badge_outlined),
                border: OutlineInputBorder(),
              ),
              validator: _required,
            ),
            const SizedBox(height: AppSpacing.xl),

            Text('Compliance requirements', style: text.titleMedium),
            const SizedBox(height: 4),
            Text(
              'Tick the documents you already have. CCAT will verify them '
              'during the review.',
              style: text.bodySmall,
            ),
            const SizedBox(height: AppSpacing.s),
            for (final r in kRequirements)
              CheckboxListTile(
                value: _reqs[r],
                onChanged: (v) => setState(() => _reqs[r] = v ?? false),
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: Text(r, style: text.bodyMedium),
              ),
            const SizedBox(height: AppSpacing.l),

            FilledButton.icon(
              onPressed: _sending ? null : _submit,
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.m),
              ),
              icon: _sending
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.send_rounded),
              label: Text(_sending ? 'Submitting…' : 'Submit application'),
            ),
          ],
        ),
      ),
    );
  }
}
