import 'package:in_app_review/in_app_review.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';

class ReviewService {
  static const String _sessionCountKey = 'session_count';
  static const String _lastReviewRequestKey = 'last_review_request';
  static const int _sessionsBeforeReview = 5;

  static Future<void> incrementSessionCount() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final currentCount = prefs.getInt(_sessionCountKey) ?? 0;
      await prefs.setInt(_sessionCountKey, currentCount + 1);
    } catch (e) {
      debugPrint('Failed to increment session count: $e');
    }
  }

  static Future<void> maybeRequestReview() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final count = prefs.getInt(_sessionCountKey) ?? 0;
      
      // Don't ask too often. Set count to -10 when asked so it takes 15 more sessions to ask again.
      if (count >= _sessionsBeforeReview) {
        final InAppReview inAppReview = InAppReview.instance;
        
        if (await inAppReview.isAvailable()) {
          // Additional check for debug/development
          if (!kDebugMode) {
             await inAppReview.requestReview();
          } else {
             debugPrint('In-app review requested (simulated in debug mode)');
          }
          await prefs.setInt(_sessionCountKey, -10); // Reset count but offset it
          await prefs.setInt(_lastReviewRequestKey, DateTime.now().millisecondsSinceEpoch);
        }
      }
    } catch (e) {
      debugPrint('Failed to request in-app review: $e');
    }
  }
}
