import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'local_storage.dart';
import 'supabase_service.dart';

class SubscriptionPlanModel {
  final String id;
  final String name;
  final double price;
  final String priceFormatted;
  final String? badge;
  final int maxMembers;
  final int maxStaff;
  final int maxGyms;
  final List<String> features;
  final bool isRecommended;
  final String? razorpayPlanId;

  const SubscriptionPlanModel({
    required this.id,
    required this.name,
    required this.price,
    required this.priceFormatted,
    this.badge,
    required this.maxMembers,
    required this.maxStaff,
    required this.maxGyms,
    required this.features,
    this.isRecommended = false,
    this.razorpayPlanId,
  });

  factory SubscriptionPlanModel.fromJson(Map<String, dynamic> json) {
    final id = json['id']?.toString() ?? 'starter';
    final name = json['name']?.toString() ?? 'Starter';
    final priceNum = (json['price'] as num?)?.toDouble() ?? (id == 'business' ? 1999.0 : (id == 'pro' ? 999.0 : 699.0));
    final maxMembers = (json['max_members'] as num?)?.toInt() ?? (id == 'business' ? -1 : (id == 'pro' ? 200 : 50));
    final maxStaff = (json['max_staff'] as num?)?.toInt() ?? (id == 'business' ? -1 : (id == 'pro' ? 5 : 1));
    final maxGyms = (json['max_gyms'] as num?)?.toInt() ?? (id == 'business' ? 5 : (id == 'pro' ? 2 : 1));
    
    String? rzpPlanId = json['razorpay_plan_id']?.toString();
    if (rzpPlanId == null || rzpPlanId.isEmpty) {
      if (id == 'starter') rzpPlanId = 'plan_TLBEs2n479kKl6';
      if (id == 'pro') rzpPlanId = 'plan_TLBAK4LFyPSGxf';
      if (id == 'business') rzpPlanId = 'plan_TLBBMMUhI7sBd6';
      if (id == 'test') rzpPlanId = 'plan_TkaKSZ86fTigEG';
    }

    String? badge = json['badge']?.toString();
    if (badge == null || badge.isEmpty) {
      if (id == 'test') badge = '1 Rs Test';
      if (id == 'starter') badge = 'Popular';
      if (id == 'pro') badge = 'Best Value';
      if (id == 'business') badge = 'Ultimate';
    }

    List<String> featuresList = [];
    if (json['features'] != null) {
      if (json['features'] is List) {
        featuresList = (json['features'] as List).map((e) => e.toString()).toList();
      } else if (json['features'] is String) {
        try {
          final parsed = jsonDecode(json['features']);
          if (parsed is List) {
            featuresList = parsed.map((e) => e.toString()).toList();
          }
        } catch (_) {}
      }
    }

    if (featuresList.isEmpty) {
      if (id == 'test') {
        featuresList = [
          'AutoPay Test Verification',
          'Full 1 Month Access',
          '2 Staff Accounts',
          'All Core Features',
        ];
      } else if (id == 'starter') {
        featuresList = [
          maxMembers > 0 ? 'Up to $maxMembers Members' : 'Unlimited Members',
          'Basic Reports',
          'Support (Email)',
          maxStaff > 0 ? '$maxStaff Staff Account' : 'Unlimited Staff',
        ];
      } else if (id == 'pro') {
        featuresList = [
          maxMembers > 0 ? 'Up to $maxMembers Members' : 'Unlimited Members',
          'Advanced Reports',
          'Priority Support',
          maxStaff > 0 ? '$maxStaff Staff Accounts' : 'Unlimited Staff',
          'Custom Branding',
        ];
      } else if (id == 'business') {
        featuresList = [
          'Unlimited Members',
          'Advanced Reports',
          'Priority Support',
          'Unlimited Staff',
          'Custom Branding',
          'API Access',
        ];
      } else {
        featuresList = [
          maxMembers > 0 ? 'Up to $maxMembers Members' : 'Unlimited Members',
          maxStaff > 0 ? '$maxStaff Staff' : 'Unlimited Staff',
          'Full Gym Management',
        ];
      }
    }

    return SubscriptionPlanModel(
      id: id,
      name: name,
      price: priceNum,
      priceFormatted: '₹${priceNum.toInt()}',
      badge: badge,
      maxMembers: maxMembers,
      maxStaff: maxStaff,
      maxGyms: maxGyms,
      features: featuresList,
      isRecommended: id == 'pro',
      razorpayPlanId: rzpPlanId,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'price': price,
    'badge': badge,
    'max_members': maxMembers,
    'max_staff': maxStaff,
    'max_gyms': maxGyms,
    'features': features,
    'is_recommended': isRecommended,
    'razorpay_plan_id': razorpayPlanId,
  };
}

class SubscriptionPlansService {
  static const String _cacheKey = 'gymos_cached_subscription_plans';
  static List<SubscriptionPlanModel>? _memoryCache;

  static List<SubscriptionPlanModel> getDefaultPlans() {
    return const [
      SubscriptionPlanModel(
        id: 'test',
        name: 'Test Plan (1 Rs)',
        price: 1.0,
        priceFormatted: '₹1',
        badge: '1 Rs / 1 Month',
        maxMembers: 50,
        maxStaff: 2,
        maxGyms: 1,
        features: [
          'AutoPay Test Verification',
          'Full 1 Month Access',
          '2 Staff Accounts',
          'All Core Features',
        ],
        isRecommended: false,
        razorpayPlanId: 'plan_TkaKSZ86fTigEG',
      ),
      SubscriptionPlanModel(
        id: 'starter',
        name: 'Starter',
        price: 699.0,
        priceFormatted: '₹699',
        badge: 'Popular',
        maxMembers: 100,
        maxStaff: 5,
        maxGyms: 1,
        features: [
          'Up to 100 Members',
          'Basic Reports',
          'Support (Email)',
          '5 Staff Accounts',
        ],
        isRecommended: false,
        razorpayPlanId: 'plan_TLBEs2n479kKl6',
      ),
      SubscriptionPlanModel(
        id: 'pro',
        name: 'Pro',
        price: 999.0,
        priceFormatted: '₹999',
        badge: 'Best Value',
        maxMembers: 1000,
        maxStaff: 5,
        maxGyms: 1,
        features: [
          'Up to 1000 Members',
          'Advanced Reports',
          'Priority Support',
          '5 Staff Accounts',
          'Custom Branding',
        ],
        isRecommended: true,
        razorpayPlanId: 'plan_TLBAK4LFyPSGxf',
      ),
      SubscriptionPlanModel(
        id: 'business',
        name: 'Business',
        price: 1999.0,
        priceFormatted: '₹1999',
        badge: 'Ultimate',
        maxMembers: 5000,
        maxStaff: 25,
        maxGyms: 3,
        features: [
          'Unlimited Members',
          'Advanced Reports',
          'Priority Support',
          'Unlimited Staff',
          'Custom Branding',
          'API Access',
        ],
        isRecommended: false,
        razorpayPlanId: 'plan_TLBBMMUhI7sBd6',
      ),
    ];
  }

  /// Instant synchronous retrieval from Memory -> LocalStorage -> Default Fallback
  static List<SubscriptionPlanModel> getPlans(LocalStorageService? storage) {
    if (_memoryCache != null && _memoryCache!.isNotEmpty) {
      return _memoryCache!;
    }

    if (storage != null) {
      final cachedStr = storage.getString(_cacheKey);
      if (cachedStr != null && cachedStr.isNotEmpty) {
        try {
          final List<dynamic> decoded = jsonDecode(cachedStr);
          final plans = decoded.map((e) => SubscriptionPlanModel.fromJson(Map<String, dynamic>.from(e))).toList();
          if (plans.isNotEmpty) {
            _memoryCache = plans;
            return plans;
          }
        } catch (_) {}
      }
    }

    _memoryCache = getDefaultPlans();
    return _memoryCache!;
  }

  /// Background sync from Supabase `subscription_plans` table
  static Future<List<SubscriptionPlanModel>> fetchAndCachePlans(LocalStorageService? storage) async {
    try {
      if (!SupabaseService.isInitialized) {
        return getPlans(storage);
      }

      final response = await SupabaseService.client
          .from('subscription_plans')
          .select('*')
          .neq('id', 'free_trial')
          .order('price', ascending: true);

      if (response.isNotEmpty) {
        final plans = response.map((r) => SubscriptionPlanModel.fromJson(Map<String, dynamic>.from(r))).toList();
        if (plans.isNotEmpty) {
          _memoryCache = plans;
          if (storage != null) {
            final jsonStr = jsonEncode(plans.map((p) => p.toJson()).toList());
            await storage.setString(_cacheKey, jsonStr);
          }
          return plans;
        }
      }
    } catch (e) {
      debugPrint('Error fetching subscription plans from Supabase: $e');
    }
    return getPlans(storage);
  }
}
