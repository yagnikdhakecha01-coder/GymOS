import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'package:flutter/foundation.dart';
import '../config/app_config.dart';
import '../config/env.dart';
import 'supabase_service.dart';

@JS('openRazorpayModal')
external void _openRazorpayModal(
  JSString optionsJson,
  JSFunction onSuccess,
  JSFunction onFailure,
  JSFunction onDismiss,
);

class RazorpayPaymentResult {
  final bool success;
  final String? paymentId;
  final String? orderId;
  final String? signature;
  final String? errorMessage;
  final bool dismissed;

  RazorpayPaymentResult({
    required this.success,
    this.paymentId,
    this.orderId,
    this.signature,
    this.errorMessage,
    this.dismissed = false,
  });
}

class PlanUpgradePreviewResult {
  final bool success;
  final String? subscriptionId;
  final String? oldPlanId;
  final String? newPlanId;
  final String? newPlanName;
  final double newPlanPrice;
  final double oldPlanPrice;
  final int remainingDays;
  final double unusedCredit;
  final double payableAmount;
  final String? oldSubId;
  final String? keyId;
  final String? errorMessage;

  PlanUpgradePreviewResult({
    required this.success,
    this.subscriptionId,
    this.oldPlanId,
    this.newPlanId,
    this.newPlanName,
    this.newPlanPrice = 0.0,
    this.oldPlanPrice = 0.0,
    this.remainingDays = 0,
    this.unusedCredit = 0.0,
    this.payableAmount = 0.0,
    this.oldSubId,
    this.keyId,
    this.errorMessage,
  });
}

class WebRazorpayService {
  /// Resolves active Razorpay Key ID (from Env or AppConfig)
  static String get activeKeyId {
    if (Env.razorpayKeyId.isNotEmpty) {
      return Env.razorpayKeyId;
    }
    return AppConfig.razorpayKeyId;
  }

  /// Calculates proration and prepares new recurring AutoPay subscription for upgrade
  static Future<PlanUpgradePreviewResult> getUpgradePreview({
    required String gymId,
    required String newPlanId,
    String? ownerId,
  }) async {
    try {
      if (SupabaseService.isInitialized) {
        final fnRes = await SupabaseService.client.functions.invoke(
          'upgrade-subscription',
          body: {
            'gym_id': gymId,
            'new_plan_id': newPlanId,
            if (ownerId != null) 'owner_id': ownerId,
          },
        );

        if (fnRes.status == 200 && fnRes.data != null) {
          final data = fnRes.data is Map 
              ? (fnRes.data as Map) 
              : jsonDecode(fnRes.data.toString());
          if (data['success'] == true) {
            return PlanUpgradePreviewResult(
              success: true,
              subscriptionId: data['subscription_id']?.toString(),
              oldPlanId: data['old_plan_id']?.toString(),
              newPlanId: data['new_plan_id']?.toString(),
              newPlanName: data['new_plan_name']?.toString(),
              newPlanPrice: (data['new_plan_price'] as num?)?.toDouble() ?? 0.0,
              oldPlanPrice: (data['old_plan_price'] as num?)?.toDouble() ?? 0.0,
              remainingDays: (data['remaining_days'] as num?)?.toInt() ?? 0,
              unusedCredit: (data['unused_credit'] as num?)?.toDouble() ?? 0.0,
              payableAmount: (data['payable_amount'] as num?)?.toDouble() ?? 0.0,
              oldSubId: data['old_sub_id']?.toString(),
              keyId: data['key_id']?.toString(),
            );
          }
        }
      }
      return PlanUpgradePreviewResult(
        success: false,
        errorMessage: 'Unable to calculate upgrade preview',
      );
    } catch (e) {
      return PlanUpgradePreviewResult(
        success: false,
        errorMessage: e.toString(),
      );
    }
  }

  /// Opens the Razorpay Checkout modal in Flutter Web via window.openRazorpayModal JS bridge.
  static Future<RazorpayPaymentResult> openCheckout({
    String? keyId,
    required double amount,
    required String planName,
    required String gymId,
    required String planId,
    String? ownerId,
    String? customerName,
    String? customerEmail,
    String? customerPhone,
    String? customSubscriptionId,
    bool isUpgrade = false,
    String? oldPlanId,
    String? oldSubId,
    double unusedCredit = 0.0,
  }) async {
    final completer = Completer<RazorpayPaymentResult>();

    String finalKey = (keyId != null && keyId.isNotEmpty) ? keyId : activeKeyId;
    int finalAmountInPaise = (amount * 100).round();
    String? createdOrderId;
    String? createdSubscriptionId = customSubscriptionId;

    // 1. If customSubscriptionId not provided, create subscription on server side
    if (createdSubscriptionId == null || createdSubscriptionId.isEmpty) {
      try {
        if (SupabaseService.isInitialized) {
          final fnRes = await SupabaseService.client.functions.invoke(
            'create-subscription',
            body: {
              'gym_id': gymId,
              'plan_id': planId,
              if (ownerId != null) 'owner_id': ownerId,
            },
          );

          if (fnRes.status == 200 && fnRes.data != null) {
            final data = fnRes.data is Map 
                ? (fnRes.data as Map) 
                : jsonDecode(fnRes.data.toString());
            if (data['subscription_id'] != null) {
              createdSubscriptionId = data['subscription_id'].toString();
            }
            if (data['order_id'] != null) {
              createdOrderId = data['order_id'].toString();
            }
            if (data['key_id'] != null && data['key_id'].toString().isNotEmpty) {
              finalKey = data['key_id'].toString();
            }
            if (data['amount'] != null) {
              finalAmountInPaise = (data['amount'] as num).toInt();
            }
          }
        }
      } catch (e) {
        debugPrint('create-subscription function invocation error: $e');
      }
    }

    final options = <String, dynamic>{
      'key': finalKey,
      if (createdSubscriptionId != null && createdSubscriptionId.isNotEmpty)
        'subscription_id': createdSubscriptionId
      else if (createdOrderId != null && createdOrderId.isNotEmpty)
        'order_id': createdOrderId,
      if (createdSubscriptionId == null || createdSubscriptionId.isEmpty)
        'amount': finalAmountInPaise,
      'currency': 'INR',
      'name': 'GymOS',
      'description': isUpgrade 
          ? '$planName Upgrade AutoPay Subscription' 
          : '$planName Plan AutoPay Subscription',
      'recurring': true,
      'prefill': {
        'name': customerName ?? 'Gym Owner',
        if (customerEmail != null && customerEmail.isNotEmpty) 'email': customerEmail,
        if (customerPhone != null && customerPhone.isNotEmpty) 'contact': customerPhone,
      },
      'notes': {
        'gym_id': gymId,
        'plan_id': planId,
        if (isUpgrade) 'is_upgrade': 'true',
        if (oldPlanId != null) 'old_plan_id': oldPlanId,
        if (oldSubId != null) 'old_sub_id': oldSubId,
        if (unusedCredit > 0) 'unused_credit': unusedCredit.toString(),
        if (ownerId != null) 'owner_id': ownerId,
      },
      'theme': {
        'color': '#6C4EFF',
      },
    };

    try {
      final optionsJson = jsonEncode(options);

      final onSuccess = ((JSString resultStr) {
        final str = resultStr.toDart;
        try {
          final data = jsonDecode(str);
          if (!completer.isCompleted) {
            completer.complete(RazorpayPaymentResult(
              success: true,
              paymentId: data['razorpay_payment_id']?.toString(),
              orderId: data['razorpay_subscription_id']?.toString() ?? data['razorpay_order_id']?.toString() ?? createdSubscriptionId ?? createdOrderId,
              signature: data['razorpay_signature']?.toString(),
            ));
          }
        } catch (_) {
          if (!completer.isCompleted) {
            completer.complete(RazorpayPaymentResult(
              success: true,
              paymentId: str,
              orderId: createdSubscriptionId ?? createdOrderId,
            ));
          }
        }
      }).toJS;

      final onFailure = ((JSString errStr) {
        if (!completer.isCompleted) {
          completer.complete(RazorpayPaymentResult(
            success: false,
            errorMessage: errStr.toDart,
          ));
        }
      }).toJS;

      final onDismiss = (() {
        if (!completer.isCompleted) {
          completer.complete(RazorpayPaymentResult(
            success: false,
            dismissed: true,
            errorMessage: 'Payment cancelled',
          ));
        }
      }).toJS;

      _openRazorpayModal(
        optionsJson.toJS,
        onSuccess,
        onFailure,
        onDismiss,
      );
    } catch (e) {
      if (!completer.isCompleted) {
        completer.complete(RazorpayPaymentResult(
          success: false,
          errorMessage: 'Could not launch Razorpay checkout modal: $e',
        ));
      }
    }

    return completer.future;
  }
}
