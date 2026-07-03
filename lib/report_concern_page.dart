import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'theme.dart'; // design tokens (AppTheme.success)

/// A form where residents report a concern to the city.
///
/// Demonstrates the core building blocks of a Flutter form:
///  - a [Form] with a [GlobalKey] to validate/reset all fields at once
///  - [TextFormField] with `validator`s
///  - [DropdownButtonFormField] for fixed choices
///  - submitting only when validation passes
class ReportConcernPage extends StatefulWidget {
  const ReportConcernPage({super.key});

  @override
  State<ReportConcernPage> createState() => _ReportConcernPageState();
}

class _ReportConcernPageState extends State<ReportConcernPage> {
  // The key lets us validate and reset every field in the form together.
  final _formKey = GlobalKey<FormState>();

  // Controllers hold the text the user types so we can read/clear it.
  final _nameController = TextEditingController();
  final _contactController = TextEditingController();
  final _descriptionController = TextEditingController();

  // Currently selected dropdown values (null until the user picks one).
  String? _barangay;
  String? _category;

  // The 27 barangays of Mandaluyong.
  static const _barangays = <String>[
    'Addition Hills', 'Bagong Silang', 'Barangka Drive', 'Barangka Ibaba',
    'Barangka Ilaya', 'Barangka Itaas', 'Buayang Bato', 'Burol', 'Daang Bakal',
    'Hagdang Bato Itaas', 'Hagdang Bato Libis', 'Harapin Ang Bukas',
    'Highway Hills', 'Hulo', 'Mabini-J. Rizal', 'Malamig', 'Mauway', 'Namayan',
    'New Zañiga', 'Old Zañiga', 'Pag-asa', 'Plainview', 'Pleasant Hills',
    'Poblacion', 'San Jose', 'Vergara', 'Wack-Wack Greenhills',
  ];

  // The kinds of concern a resident can report.
  static const _categories = <String>[
    'Road / Pavement', 'Garbage Collection', 'Streetlight', 'Flooding / Drainage',
    'Noise', 'Stray Animals', 'Other',
  ];

  @override
  void dispose() {
    // Always clean up controllers to avoid memory leaks.
    _nameController.dispose();
    _contactController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  // Known barangay emails. Most Mandaluyong barangays don't publish an email,
  // so anything not listed here routes to the City Barangay Operations Center
  // (which handles barangay affairs) — the message still names the barangay.
  // Add real per-barangay emails here as you obtain them.
  static const String _bocEmail = 'boc@mandaluyong.gov.ph';
  static const Map<String, String> _barangayEmails = {
    'Poblacion': 'office@barangaypoblacion.com',
  };

  String _emailFor(String barangay) => _barangayEmails[barangay] ?? _bocEmail;

  Future<void> _submit() async {
    // Run every field's validator. Returns true only if all pass.
    if (!_formKey.currentState!.validate()) return;

    final email = _emailFor(_barangay!);
    final subject = '[Be@Mandaluyong] $_category concern - Barangay $_barangay';
    final body = 'Name: ${_nameController.text.trim()}\n'
        'Contact: ${_contactController.text.trim()}\n'
        'Barangay: $_barangay\n'
        'Type of concern: $_category\n\n'
        'Concern:\n${_descriptionController.text.trim()}\n\n'
        '— Sent via the Be@Mandaluyong app';

    // mailto: opens the user's email app with everything pre-filled.
    final uri = Uri(
      scheme: 'mailto',
      path: email,
      query: 'subject=${Uri.encodeComponent(subject)}'
          '&body=${Uri.encodeComponent(body)}',
    );

    final ok = await launchUrl(uri);
    if (!mounted) return;

    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Opening your email app to send to $email')),
      );
    } else {
      // No email app available — show the address so they can still reach out.
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          icon: Icon(Icons.mail_outline,
              color: AppTheme.successFor(Theme.of(context).brightness),
              size: 44),
          title: const Text('No email app found'),
          content: Text('Please email your concern to:\n\n$email'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    }
  }

  void _resetForm() {
    _formKey.currentState!.reset();
    _nameController.clear();
    _contactController.clear();
    _descriptionController.clear();
    setState(() {
      _barangay = null;
      _category = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Report a Concern'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.l),
          children: [
            const Text(
              'Tell us what needs attention in your area. '
              'Fields marked * are required.',
            ),
            const SizedBox(height: AppSpacing.m),
            // Routing note
            Container(
              padding: const EdgeInsets.all(AppSpacing.m),
              decoration: BoxDecoration(
                color: colors.tertiaryContainer,
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              child: Row(
                children: [
                  Icon(Icons.mark_email_unread_outlined,
                      size: 18, color: colors.onTertiaryContainer),
                  const SizedBox(width: AppSpacing.s),
                  Expanded(
                    child: Text(
                      'When you submit, your email app opens with the concern '
                      'pre-filled, addressed to your barangay (or the City '
                      'Barangay Operations Center). Just tap send.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: colors.onTertiaryContainer,
                          ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.xl),

            // Full name
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Full name *',
                prefixIcon: Icon(Icons.person_outline),
                border: OutlineInputBorder(),
              ),
              textInputAction: TextInputAction.next,
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Please enter your name';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),

            // Contact (email or phone)
            TextFormField(
              controller: _contactController,
              decoration: const InputDecoration(
                labelText: 'Email or phone *',
                prefixIcon: Icon(Icons.contact_mail_outlined),
                border: OutlineInputBorder(),
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Please enter a way to reach you';
                }
                if (value.trim().length < 7) {
                  return 'That contact looks too short';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),

            // Barangay dropdown
            DropdownButtonFormField<String>(
              initialValue: _barangay,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Barangay *',
                prefixIcon: Icon(Icons.location_on_outlined),
                border: OutlineInputBorder(),
              ),
              items: _barangays
                  .map((b) => DropdownMenuItem(value: b, child: Text(b)))
                  .toList(),
              onChanged: (value) => setState(() => _barangay = value),
              validator: (value) => value == null ? 'Please choose a barangay' : null,
            ),
            const SizedBox(height: 16),

            // Category dropdown
            DropdownButtonFormField<String>(
              initialValue: _category,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Type of concern *',
                prefixIcon: Icon(Icons.category_outlined),
                border: OutlineInputBorder(),
              ),
              items: _categories
                  .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                  .toList(),
              onChanged: (value) => setState(() => _category = value),
              validator: (value) => value == null ? 'Please choose a type' : null,
            ),
            const SizedBox(height: 16),

            // Description (multiline)
            TextFormField(
              controller: _descriptionController,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'Description *',
                hintText: 'Describe the concern and exact location…',
                alignLabelWithHint: true,
                border: OutlineInputBorder(),
              ),
              validator: (value) {
                if (value == null || value.trim().length < 10) {
                  return 'Please add at least a short description';
                }
                return null;
              },
            ),
            const SizedBox(height: 24),

            // Submit — opens the email app addressed to the barangay
            FilledButton.icon(
              onPressed: _submit,
              icon: const Icon(Icons.email_outlined),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              label: const Text('Send to barangay'),
            ),
            const SizedBox(height: 12),

            // Clear
            OutlinedButton(
              onPressed: _resetForm,
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: const Text('Clear form'),
            ),
          ],
        ),
      ),
    );
  }
}
