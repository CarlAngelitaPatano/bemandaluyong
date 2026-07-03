import 'dart:convert';
import 'package:http/http.dart' as http;

/// Sends emails through EmailJS (https://www.emailjs.com).
///
/// The Public Key is safe to ship in the app — that's how EmailJS is designed.
class EmailService {
  static const _serviceId = 'service_qjrawao';
  static const _templateId = 'template_s3eobbk';
  static const _publicKey = 'GzDZBtlr1-aIUVpm0';

  static final Uri _endpoint =
      Uri.parse('https://api.emailjs.com/api/v1.0/email/send');

  /// Sends the trail certificate email.
  /// Returns `null` on success, or an error message string on failure.
  static Future<String?> sendCertificate({
    required String toEmail,
    required String toName,
    required int churchCount,
    required String completionDate,
  }) async {
    try {
      final response = await http.post(
        _endpoint,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'service_id': _serviceId,
          'template_id': _templateId,
          'user_id': _publicKey,
          'template_params': {
            'to_email': toEmail,
            'to_name': toName,
            'church_count': '$churchCount',
            'completion_date': completionDate,
          },
        }),
      );
      if (response.statusCode == 200) return null;
      return 'Could not send email (code ${response.statusCode}).';
    } catch (e) {
      return 'Could not send email. Check your internet connection.';
    }
  }
}
