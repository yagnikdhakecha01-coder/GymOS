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

class WebRazorpayService {
  /// Resolves active Razorpay Key ID (from Env or AppConfig)
  static String get activeKeyId {
    if (Env.razorpayKeyId.isNotEmpty) {
      return Env.razorpayKeyId;
    }
    return AppConfig.razorpayKeyId;
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
  }) async {
    final completer = Completer<RazorpayPaymentResult>();

    String finalKey = (keyId != null && keyId.isNotEmpty) ? keyId : activeKeyId;
    int finalAmountInPaise = (amount * 100).round();
    String? createdOrderId;

    // 1. Create order on server side via Supabase Edge Function to get valid order_id
    try {
      if (SupabaseService.isInitialized) {
        final fnRes = await SupabaseService.client.functions.invoke(
          'create-subscription',
          body: {
            'gym_id': gymId,
            'plan_id': planId,
            ?ownerId != null ? 'owner_id': ownerId : null,
          }..removeWhere((k, v) => v == null),
        );

        if (fnRes.status == 200 && fnRes.data != null) {
          final data = fnRes.data is Map 
              ? (fnRes.data as Map) 
              : jsonDecode(fnRes.data.toString());
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

    final options = {
      'key': finalKey,
      if (createdOrderId != null && createdOrderId.isNotEmpty) 'order_id': createdOrderId,
      'amount': finalAmountInPaise,
      'currency': 'INR',
      'name': 'GymOS',
      'description': '$planName Plan Subscription',
      'prefill': {
        'name': customerName ?? 'Gym Owner',
        if (customerEmail != null && customerEmail.isNotEmpty) 'email': customerEmail,
        if (customerPhone != null && customerPhone.isNotEmpty) 'contact': customerPhone,
      },
      'notes': {
        'gym_id': gymId,
        'plan_id': planId,
        ...?ownerId != null ? {'owner_id': ownerId} : null,
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
              orderId: data['razorpay_order_id']?.toString() ?? createdOrderId,
              signature: data['razorpay_signature']?.toString(),
            ));
          }
        } catch (_) {
          if (!completer.isCompleted) {
            completer.complete(RazorpayPaymentResult(
              success: true,
              paymentId: str,
              orderId: createdOrderId,
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
