class AppConfig {
  static const String appName = 'GymOS';
  static const String appVersion = '1.0.0';
  static const int buildNumber = 1;

  // Razorpay Test Key ID
  static const String razorpayKeyId = 'rzp_test_TLEBpLEBBlInG6';

  // Razorpay Subscription Plan IDs
  static const String razorpayStarterPlanId = 'plan_TMW2eKLvuIqViB';
  static const String razorpayProPlanId = 'plan_TMW3EjESnsxvEq';
  static const String razorpayBusinessPlanId = 'plan_TMW3ZHfWH8vXb4';

  static String getRazorpayPlanId(String planId) {
    final cleanId = planId.toLowerCase();
    if (cleanId.contains('starter')) return razorpayStarterPlanId;
    if (cleanId.contains('pro')) return razorpayProPlanId;
    if (cleanId.contains('business')) return razorpayBusinessPlanId;
    return razorpayStarterPlanId;
  }
}
