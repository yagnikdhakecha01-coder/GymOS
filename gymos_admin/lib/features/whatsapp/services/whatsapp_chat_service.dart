import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../../../core/services/supabase_service.dart';

class WhatsAppMessageModel {
  final String id;
  final String? wamid;
  final String phoneNumber;
  final String? senderName;
  final String direction; // 'inbound' | 'outbound'
  final String messageType; // 'text' | 'image' | etc.
  final String messageBody;
  final String status; // 'sent' | 'delivered' | 'read' | 'failed' | 'received'
  final String? errorMessage;
  final DateTime createdAt;

  WhatsAppMessageModel({
    required this.id,
    this.wamid,
    required this.phoneNumber,
    this.senderName,
    required this.direction,
    required this.messageType,
    required this.messageBody,
    required this.status,
    this.errorMessage,
    required this.createdAt,
  });

  bool get isInbound => direction == 'inbound';
  bool get isOutbound => direction == 'outbound';

  factory WhatsAppMessageModel.fromMap(Map<String, dynamic> map) {
    return WhatsAppMessageModel(
      id: map['id']?.toString() ?? '',
      wamid: map['wamid']?.toString(),
      phoneNumber: map['phone_number']?.toString() ?? '',
      senderName: map['sender_name']?.toString(),
      direction: map['direction']?.toString() ?? 'inbound',
      messageType: map['message_type']?.toString() ?? 'text',
      messageBody: map['message_body']?.toString() ?? '',
      status: map['status']?.toString() ?? 'sent',
      errorMessage: map['error_message']?.toString(),
      createdAt: DateTime.tryParse(map['created_at']?.toString() ?? '') ?? DateTime.now(),
    );
  }
}

class WhatsAppConversationSummary {
  final String phoneNumber;
  final String? senderName;
  final String lastMessage;
  final String lastDirection;
  final String lastStatus;
  final DateTime lastMessageAt;
  final int unreadCount;

  WhatsAppConversationSummary({
    required this.phoneNumber,
    this.senderName,
    required this.lastMessage,
    required this.lastDirection,
    required this.lastStatus,
    required this.lastMessageAt,
    this.unreadCount = 0,
  });

  factory WhatsAppConversationSummary.fromMap(Map<String, dynamic> map) {
    return WhatsAppConversationSummary(
      phoneNumber: map['phone_number']?.toString() ?? '',
      senderName: map['sender_name']?.toString(),
      lastMessage: map['last_message']?.toString() ?? '',
      lastDirection: map['last_direction']?.toString() ?? 'inbound',
      lastStatus: map['last_status']?.toString() ?? 'sent',
      lastMessageAt: DateTime.tryParse(map['last_message_at']?.toString() ?? '') ?? DateTime.now(),
      unreadCount: (map['unread_count'] as num?)?.toInt() ?? 0,
    );
  }
}

class WhatsAppChatService {
  static final WhatsAppChatService instance = WhatsAppChatService._();
  WhatsAppChatService._();

  Map<String, String>? _cachedCredentials;

  /// Loads access token & phone number ID from Supabase platform_settings
  Future<Map<String, String>> getCredentials() async {
    if (_cachedCredentials != null) return _cachedCredentials!;

    final client = AdminSupabaseService.client;
    final res = await client
        .from('platform_settings')
        .select('value')
        .eq('key', 'meta_whatsapp_config')
        .maybeSingle();

    String token = '';
    String phoneId = '';
    String wabaId = '';

    if (res != null && res['value'] != null) {
      final val = Map<String, dynamic>.from(res['value']);
      token = val['access_token']?.toString() ?? '';
      phoneId = val['phone_number_id']?.toString() ?? '';
      wabaId = val['business_account_id']?.toString() ?? '';
    }

    _cachedCredentials = {
      'access_token': token.trim(),
      'phone_number_id': phoneId.trim(),
      'waba_id': wabaId.trim(),
    };

    return _cachedCredentials!;
  }

  void clearCredentialsCache() {
    _cachedCredentials = null;
  }

  /// Fetches all conversation summaries
  Future<List<WhatsAppConversationSummary>> fetchConversations() async {
    final client = AdminSupabaseService.client;
    final res = await client
        .from('whatsapp_conversations_view')
        .select('*')
        .order('last_message_at', ascending: false);

    return (res as List)
        .map((row) => WhatsAppConversationSummary.fromMap(Map<String, dynamic>.from(row)))
        .toList();
  }

  /// Fetches all messages for a specific phone number
  Future<List<WhatsAppMessageModel>> fetchMessages(String phoneNumber) async {
    final client = AdminSupabaseService.client;
    final cleanPhone = normalizePhoneNumber(phoneNumber);

    final res = await client
        .from('whatsapp_messages')
        .select('*')
        .eq('phone_number', cleanPhone)
        .order('created_at', ascending: true);

    return (res as List)
        .map((row) => WhatsAppMessageModel.fromMap(Map<String, dynamic>.from(row)))
        .toList();
  }

  /// Normalizes phone number to digits only (e.g., '919876543210')
  static String normalizePhoneNumber(String phone) {
    return phone.replaceAll(RegExp(r'[^0-9]'), '');
  }

  /// Sends an outbound WhatsApp text message via Meta Cloud API and stores in DB
  Future<WhatsAppMessageModel> sendMessage({
    required String toPhoneNumber,
    required String text,
    String? contactName,
  }) async {
    final cleanPhone = normalizePhoneNumber(toPhoneNumber);
    if (cleanPhone.isEmpty) {
      throw Exception('Invalid phone number provided.');
    }
    if (text.trim().isEmpty) {
      throw Exception('Message text cannot be empty.');
    }

    final creds = await getCredentials();
    final token = creds['access_token'] ?? '';
    final phoneId = creds['phone_number_id'] ?? '';

    if (token.isEmpty || phoneId.isEmpty) {
      throw Exception('WhatsApp API credentials not found. Please check Settings > WhatsApp Configuration.');
    }

    // 1. Send via Meta Graph API
    final url = Uri.parse('https://graph.facebook.com/v20.0/$phoneId/messages');
    final payload = {
      'messaging_product': 'whatsapp',
      'recipient_type': 'individual',
      'to': cleanPhone,
      'type': 'text',
      'text': {'preview_url': false, 'body': text.trim()},
    };

    final response = await http.post(
      url,
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode(payload),
    );

    final data = jsonDecode(response.body);

    if (response.statusCode != 200 || data['error'] != null) {
      final errMsg = data['error']?['message'] ?? 'Meta API error: ${response.statusCode}';
      debugPrint('Failed to send WhatsApp message: $errMsg');
      throw Exception(errMsg);
    }

    final String? wamid = data['messages']?[0]?['id']?.toString();

    // 2. Insert into whatsapp_messages table
    final client = AdminSupabaseService.client;
    final row = {
      'wamid': wamid,
      'phone_number': cleanPhone,
      'sender_name': contactName ?? 'GymOS Admin',
      'direction': 'outbound',
      'message_type': 'text',
      'message_body': text.trim(),
      'status': 'sent',
      'meta_payload': data,
      'created_at': DateTime.now().toIso8601String(),
    };

    final inserted = await client
        .from('whatsapp_messages')
        .insert(row)
        .select()
        .single();

    return WhatsAppMessageModel.fromMap(Map<String, dynamic>.from(inserted));
  }
}
