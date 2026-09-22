import 'env.dart';

class AppConfig {
  static const String appName = 'GymOS';
  static const String appVersion = '1.0.2';
  static const int buildNumber = 19;


  // Razorpay Key ID (configurable via build environment)
  static String get razorpayKeyId => Env.razorpayKeyId;

  // Razorpay Subscription Plan IDs (configurable via build environment)
  static const String razorpayStarterPlanId = String.fromEnvironment(
    'RAZORPAY_STARTER_PLAN_ID',
  );
  static const String razorpayProPlanId = String.fromEnvironment(
    'RAZORPAY_PRO_PLAN_ID',
  );
  static const String razorpayBusinessPlanId = String.fromEnvironment(
    'RAZORPAY_BUSINESS_PLAN_ID',
  );

  static String getRazorpayPlanId(String planId) {
    final cleanId = planId.toLowerCase();
    if (cleanId.contains('starter')) return razorpayStarterPlanId;
    if (cleanId.contains('pro')) return razorpayProPlanId;
    if (cleanId.contains('business')) return razorpayBusinessPlanId;
    return razorpayStarterPlanId;
  }
}
