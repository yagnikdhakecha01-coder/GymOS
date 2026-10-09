import 'package:shared_preferences/shared_preferences.dart';
import 'supabase_service.dart';

/// Handles in-app Play Store review logic:
/// - SharedPrefs flag for "has_reviewed"
/// - Supabase analytics logging (fire-and-forget, no PII)
/// - Role-based SEO-friendly review suggestion corpus
class AppReviewService {
  static const _reviewedKey = 'gymos_has_reviewed';

  // ── Play Store URL ──────────────────────────────────────────────
  static const String playStoreUrl =
      'https://play.google.com/store/apps/details?id=com.gymos.fitness.app.v1';
  static const String playStoreFallbackUrl =
      'https://play.google.com/store/apps/developer?id=GymOS';

  // ── SharedPrefs: reviewed flag ──────────────────────────────────

  /// Returns true if user has already submitted a review.
  static Future<bool> hasReviewed() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_reviewedKey) ?? false;
  }

  /// Marks the user as having submitted a review.
  static Future<void> markReviewed() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_reviewedKey, true);
  }

  // ── Supabase Analytics (fire-and-forget, no PII) ────────────────

  /// Logs a review event to Supabase.
  /// Silently fails on any error — never blocks the UI.
  static Future<void> logReviewEvent({
    required String role,
    required int stars,
    required bool submitted,
    String? gymId,
  }) async {
    if (!SupabaseService.isInitialized) return;
    try {
      await SupabaseService.client.from('app_review_events').insert({
        'gym_id': gymId,
        'role': role,
        'stars': stars,
        'submitted': submitted,
      });
    } catch (_) {
      // Silent fail — analytics never blocks UX
    }
  }

  // ── Role-Based SEO Corpus ───────────────────────────────────────

  /// Returns a short, SEO-friendly, pre-filled review suggestion
  /// based on the user's role and selected star count.
  ///
  /// Key format: '${role}_${stars}' (e.g. 'owner_5', 'member_4')
  /// Defaults to 'owner_5' text if key not found.
  static String getSuggestedReview(String role, int stars) {
    final key = '${role.toLowerCase()}_$stars';
    return _corpus[key] ?? _corpus['owner_5']!;
  }

  static const Map<String, String> _corpus = {
    // Owner
    'owner_5':
        'Best gym management app! GymOS handles members, attendance, salary, and finance all in one place. A must-have for every gym owner.',
    'owner_4':
        'GymOS is a solid gym management tool. Member renewals, staff attendance, and revenue tracking work great.',
    'owner_3':
        'Good gym management app. GymOS covers member and attendance basics well. Would love more features.',

    // Staff / Trainer
    'staff_5':
        'GymOS makes gym staff work easy. QR check-in, client tracking, and attendance — all smooth. Love it!',
    'staff_4':
        'Great app for gym trainers. GymOS client management and attendance tracking works really well.',
    'staff_3':
        'GymOS is useful for gym staff. Attendance and member check-ins work fine.',

    // Receptionist — same as staff
    'receptionist_5':
        'GymOS makes gym staff work easy. QR check-in, client tracking, and attendance — all smooth. Love it!',
    'receptionist_4':
        'Great app for gym trainers. GymOS client management and attendance tracking works really well.',
    'receptionist_3':
        'GymOS is useful for gym staff. Attendance and member check-ins work fine.',

    // Member
    'member_5':
        'Love GymOS! My attendance streak, diet plan, workout, and fitness goals — everything in one app. So motivating!',
    'member_4':
        'GymOS is great for gym members. Diet plan, workout tracker, and QR check-in are super convenient.',
    'member_3':
        'Useful gym app. GymOS attendance and diet tracking works well. More features would be nice.',
  };
}
