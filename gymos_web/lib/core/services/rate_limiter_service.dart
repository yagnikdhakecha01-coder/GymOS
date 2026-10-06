
/// In-memory and client-enforced rate limiter for sensitive authentication actions.
/// Ensures compliance with security standards:
/// - Login: Maximum 5 failed attempts per 60 seconds. Lockout for 60 seconds if exceeded.
/// - Password Reset: Maximum 3 attempts per hour (3600 seconds).
class RateLimiterService {
  static final RateLimiterService _instance = RateLimiterService._internal();
  factory RateLimiterService() => _instance;
  RateLimiterService._internal();

  // Login rate limiter state
  static const int maxLoginAttempts = 5;
  static const Duration loginWindow = Duration(minutes: 1);
  static const Duration loginLockout = Duration(minutes: 1);

  final List<DateTime> _loginAttempts = [];
  DateTime? _loginLockoutUntil;

  // Password reset rate limiter state
  static const int maxResetAttempts = 3;
  static const Duration resetWindow = Duration(hours: 1);
  final List<DateTime> _resetAttempts = [];

  /// Check if a login attempt is permitted.
  /// Returns null if permitted, or the remaining lockout duration if throttled.
  Duration? checkLoginRateLimit() {
    final now = DateTime.now();

    // Check if currently locked out
    if (_loginLockoutUntil != null) {
      if (now.isBefore(_loginLockoutUntil!)) {
        return _loginLockoutUntil!.difference(now);
      } else {
        // Lockout expired, reset
        _loginLockoutUntil = null;
        _loginAttempts.clear();
      }
    }

    // Filter attempts to only those within the sliding window
    _loginAttempts.removeWhere((timestamp) => now.difference(timestamp) > loginWindow);

    if (_loginAttempts.length >= maxLoginAttempts) {
      _loginLockoutUntil = now.add(loginLockout);
      return loginLockout;
    }

    return null;
  }

  /// Record a failed login attempt
  void recordFailedLogin() {
    final now = DateTime.now();
    _loginAttempts.add(now);

    // If reached threshold, initiate lockout
    if (_loginAttempts.length >= maxLoginAttempts) {
      _loginLockoutUntil = now.add(loginLockout);
    }
  }

  /// Reset login rate limit on successful authentication
  void resetLoginAttempts() {
    _loginAttempts.clear();
    _loginLockoutUntil = null;
  }

  /// Check if a password reset attempt is permitted.
  /// Returns null if permitted, or remaining duration to wait if throttled.
  Duration? checkPasswordResetRateLimit() {
    final now = DateTime.now();
    _resetAttempts.removeWhere((timestamp) => now.difference(timestamp) > resetWindow);

    if (_resetAttempts.length >= maxResetAttempts) {
      final oldest = _resetAttempts.first;
      final unlockTime = oldest.add(resetWindow);
      if (now.isBefore(unlockTime)) {
        return unlockTime.difference(now);
      }
    }
    return null;
  }

  /// Record a password reset attempt
  void recordPasswordResetAttempt() {
    final now = DateTime.now();
    _resetAttempts.add(now);
  }
}
