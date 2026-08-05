/// Gym status values used across the admin panel
class GymStatus {
  static const String trial = 'trial';
  static const String active = 'active';
  static const String gracePeriod = 'grace_period';
  static const String suspended = 'suspended';
  static const String disabled = 'disabled';

  static const List<String> all = [trial, active, gracePeriod, suspended, disabled];

  static String displayName(String status) {
    switch (status) {
      case trial: return 'Trial';
      case active: return 'Active';
      case gracePeriod: return 'Grace Period';
      case suspended: return 'Suspended';
      case disabled: return 'Disabled';
      default: return status;
    }
  }
}

/// Platform plan names
class PlatformPlan {
  static const String freeTrial = 'free_trial';
  static const String starter = 'starter';
  static const String pro = 'pro';
  static const String business = 'business';

  static String displayName(String plan) {
    switch (plan) {
      case freeTrial: return 'Free Trial';
      case starter: return 'Starter';
      case pro: return 'Pro';
      case business: return 'Business';
      default: return plan;
    }
  }
}

/// Disabled reasons
class DisabledReason {
  static const String fraud = 'Fraud';
  static const String abuse = 'Abuse';
  static const String fakeAccount = 'Fake Account';
  static const String termsViolation = 'Terms Violation';
  static const String other = 'Other';

  static const List<String> all = [fraud, abuse, fakeAccount, termsViolation, other];
}

/// Feature flag keys
class FeatureFlags {
  static const String qrAttendance = 'qr_attendance';
  static const String manualAttendance = 'manual_attendance';
  static const String ptModule = 'pt_module';
  static const String aiDiet = 'ai_diet';
  static const String aiWorkout = 'ai_workout';
  static const String finance = 'finance';
  static const String memberApp = 'member_app';
  static const String staffApp = 'staff_app';
  static const String beaconAttendance = 'beacon_attendance';
  static const String notifications = 'notifications';

  static const List<String> all = [
    qrAttendance, manualAttendance, ptModule, aiDiet, aiWorkout,
    finance, memberApp, staffApp, beaconAttendance, notifications,
  ];

  static String displayName(String flag) {
    switch (flag) {
      case qrAttendance: return 'QR Attendance';
      case manualAttendance: return 'Manual Attendance';
      case ptModule: return 'PT Module';
      case aiDiet: return 'AI Diet';
      case aiWorkout: return 'AI Workout';
      case finance: return 'Finance';
      case memberApp: return 'Member App';
      case staffApp: return 'Staff App';
      case beaconAttendance: return 'Beacon Attendance';
      case notifications: return 'Notifications';
      default: return flag;
    }
  }

  static String description(String flag) {
    switch (flag) {
      case qrAttendance: return 'Allow gyms to use QR code scanning for attendance';
      case manualAttendance: return 'Allow manual attendance marking by staff';
      case ptModule: return 'Enable Personal Training session management';
      case aiDiet: return 'AI-powered diet plan generation';
      case aiWorkout: return 'AI-powered workout plan generation';
      case finance: return 'Finance and transaction tracking module';
      case memberApp: return 'Member mobile app access';
      case staffApp: return 'Staff mobile app access';
      case beaconAttendance: return 'Bluetooth beacon-based attendance';
      case notifications: return 'Push notification system';
      default: return '';
    }
  }
}

/// Notification target types
class NotificationTarget {
  static const String allGyms = 'all_gyms';
  static const String trialGyms = 'trial_gyms';
  static const String activeGyms = 'active_gyms';
  static const String selectedGyms = 'selected_gyms';

  static String displayName(String target) {
    switch (target) {
      case allGyms: return 'All Gyms';
      case trialGyms: return 'Trial Gyms';
      case activeGyms: return 'Active Gyms';
      case selectedGyms: return 'Selected Gyms';
      default: return target;
    }
  }
}

/// Notification types
class NotificationType {
  static const String push = 'push';
  static const String banner = 'banner';
  static const String popup = 'popup';
  static const String maintenance = 'maintenance';
  static const String offer = 'offer';
}

/// Support ticket priorities
class TicketPriority {
  static const String low = 'low';
  static const String medium = 'medium';
  static const String high = 'high';
  static const String urgent = 'urgent';
}

/// Support ticket statuses
class TicketStatus {
  static const String open = 'open';
  static const String inProgress = 'in_progress';
  static const String resolved = 'resolved';
  static const String closed = 'closed';
}
