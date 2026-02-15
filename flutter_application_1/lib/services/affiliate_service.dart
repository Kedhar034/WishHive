import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Call your backend to convert a product URL into an affiliate link.
class AffiliateService {
  // While testing locally (Android emulator):
  static const String _backendUrl = "http://10.0.2.2:3000/convert-link";
  // For real device: use your PC's local IP or deployed HTTPS link

  /// Converts an original product URL into an affiliate link.
  /// Returns the affiliate URL or null if conversion fails.
  static Future<String?> convertToAffiliateLink(String originalUrl) async {
    if (originalUrl.isEmpty) return null;

    try {
      final response = await http.post(
        Uri.parse(_backendUrl),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"original_url": originalUrl}),
      ).timeout(const Duration(seconds: 3));

      if (response.statusCode != 200) {
        debugPrint('Affiliate API returned status: ${response.statusCode}');
        return null;
      }

      final jsonResp = jsonDecode(response.body);

      if (jsonResp is Map<String, dynamic> && jsonResp['success'] == true) {
        final payload = jsonResp['data'];
        if (payload is Map<String, dynamic>) {
          if (payload['shorten_url'] is String) {
            return payload['shorten_url'] as String;
          }
        }
        if (jsonResp['affiliate_url'] is String) {
          return jsonResp['affiliate_url'] as String;
        }
      }

      return null;
    } catch (e) {
      debugPrint("Affiliate conversion error: $e");
      return null;
    }
  }
}
