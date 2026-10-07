import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../../../core/services/supabase_service.dart';

/// Represents a single WhatsApp message template from Meta
class WhatsAppTemplate {
  final String id;
  final String name;
  final String language;
  final String status; // APPROVED, PENDING, REJECTED, PAUSED, DISABLED
  final String category; // MARKETING, UTILITY, AUTHENTICATION
  final List<TemplateComponent> components;
  final String? rejectedReason;
  final DateTime? lastUpdated;

  WhatsAppTemplate({
    required this.id,
    required this.name,
    required this.language,
    required this.status,
    required this.category,
    this.components = const [],
    this.rejectedReason,
    this.lastUpdated,
  });

  factory WhatsAppTemplate.fromMeta(Map<String, dynamic> json) {
    final components = (json['components'] as List<dynamic>?)
            ?.map((c) => TemplateComponent.fromJson(Map<String, dynamic>.from(c)))
            .toList() ??
        [];

    return WhatsAppTemplate(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      language: json['language']?.toString() ?? 'en_US',
      status: json['status']?.toString() ?? 'UNKNOWN',
      category: json['category']?.toString() ?? 'UTILITY',
      components: components,
      rejectedReason: json['rejected_reason']?.toString(),
      lastUpdated: json['last_updated_time'] != null
          ? DateTime.tryParse(json['last_updated_time'].toString())
          : null,
    );
  }

  /// Get the HEADER component text (if any)
  String? get headerText {
    final header = components.where((c) => c.type == 'HEADER').firstOrNull;
    return header?.text;
  }

  /// Get the BODY component text
  String get bodyText {
    final body = components.where((c) => c.type == 'BODY').firstOrNull;
    return body?.text ?? '';
  }

  /// Get the FOOTER component text (if any)
  String? get footerText {
    final footer = components.where((c) => c.type == 'FOOTER').firstOrNull;
    return footer?.text;
  }

  /// Get button components
  List<TemplateComponent> get buttons =>
      components.where((c) => c.type == 'BUTTONS').toList();
}

/// Represents a component of a WhatsApp template (HEADER, BODY, FOOTER, BUTTONS)
class TemplateComponent {
  final String type; // HEADER, BODY, FOOTER, BUTTONS
  final String? format; // TEXT, IMAGE, VIDEO, DOCUMENT (for HEADER)
  final String? text;
  final List<TemplateButton>? buttons;

  TemplateComponent({
    required this.type,
    this.format,
    this.text,
    this.buttons,
  });

  factory TemplateComponent.fromJson(Map<String, dynamic> json) {
    List<TemplateButton>? buttons;
    if (json['buttons'] != null) {
      buttons = (json['buttons'] as List<dynamic>)
          .map((b) => TemplateButton.fromJson(Map<String, dynamic>.from(b)))
          .toList();
    }

    return TemplateComponent(
      type: json['type']?.toString() ?? '',
      format: json['format']?.toString(),
      text: json['text']?.toString(),
      buttons: buttons,
    );
  }
}

/// Represents a button in a template
class TemplateButton {
  final String type; // QUICK_REPLY, URL, PHONE_NUMBER
  final String text;
  final String? url;
  final String? phoneNumber;

  TemplateButton({
    required this.type,
    required this.text,
    this.url,
    this.phoneNumber,
  });

  factory TemplateButton.fromJson(Map<String, dynamic> json) {
    return TemplateButton(
      type: json['type']?.toString() ?? '',
      text: json['text']?.toString() ?? '',
      url: json['url']?.toString(),
      phoneNumber: json['phone_number']?.toString(),
    );
  }
}

/// Service to interact with Meta WhatsApp Business API for template management
class WhatsAppTemplateService {
  static final WhatsAppTemplateService instance = WhatsAppTemplateService._();
  WhatsAppTemplateService._();

  Map<String, String>? _cachedCredentials;

  /// Load credentials from Supabase platform_settings
  Future<Map<String, String>> _getCredentials() async {
    if (_cachedCredentials != null) return _cachedCredentials!;

    final client = AdminSupabaseService.client;
    final res = await client
        .from('platform_settings')
        .select('value')
        .eq('key', 'meta_whatsapp_config')
        .maybeSingle();

    String token = '';
    String wabaId = '';

    if (res != null && res['value'] != null) {
      final val = Map<String, dynamic>.from(res['value']);
      token = val['access_token']?.toString() ?? '';
      wabaId = val['business_account_id']?.toString() ?? '';
    }

    _cachedCredentials = {
      'access_token': token.trim(),
      'waba_id': wabaId.trim(),
    };
    return _cachedCredentials!;
  }

  void clearCache() => _cachedCredentials = null;

  /// Fetch all message templates from Meta
  Future<List<WhatsAppTemplate>> fetchTemplates() async {
    final creds = await _getCredentials();
    final token = creds['access_token'] ?? '';
    final wabaId = creds['waba_id'] ?? '';

    if (token.isEmpty || wabaId.isEmpty) {
      throw Exception(
          'WhatsApp API credentials not configured. Go to Settings → WhatsApp Configuration.');
    }

    final List<WhatsAppTemplate> allTemplates = [];
    String? nextUrl;
    var url = Uri.parse(
        'https://graph.facebook.com/v20.0/$wabaId/message_templates?limit=100&fields=id,name,language,status,category,components,rejected_reason,last_updated_time');

    do {
      final response = await http.get(
        nextUrl != null ? Uri.parse(nextUrl) : url,
        headers: {'Authorization': 'Bearer $token'},
      );

      final data = jsonDecode(response.body);

      if (response.statusCode != 200 || data['error'] != null) {
        final errMsg = data['error']?['message'] ??
            'Meta API error: ${response.statusCode}';
        throw Exception(errMsg);
      }

      final templates = (data['data'] as List<dynamic>?)
              ?.map((t) =>
                  WhatsAppTemplate.fromMeta(Map<String, dynamic>.from(t)))
              .toList() ??
          [];
      allTemplates.addAll(templates);

      // Handle pagination
      nextUrl = data['paging']?['next']?.toString();
    } while (nextUrl != null);

    return allTemplates;
  }

  /// Create a new message template
  Future<WhatsAppTemplate> createTemplate({
    required String name,
    required String language,
    required String category,
    String? headerText,
    required String bodyText,
    String? footerText,
    List<Map<String, String>>? buttons,
  }) async {
    final creds = await _getCredentials();
    final token = creds['access_token'] ?? '';
    final wabaId = creds['waba_id'] ?? '';

    if (token.isEmpty || wabaId.isEmpty) {
      throw Exception('WhatsApp API credentials not configured.');
    }

    // Build components
    final List<Map<String, dynamic>> components = [];

    if (headerText != null && headerText.trim().isNotEmpty) {
      components.add({
        'type': 'HEADER',
        'format': 'TEXT',
        'text': headerText.trim(),
      });
    }

    components.add({
      'type': 'BODY',
      'text': bodyText.trim(),
    });

    if (footerText != null && footerText.trim().isNotEmpty) {
      components.add({
        'type': 'FOOTER',
        'text': footerText.trim(),
      });
    }

    if (buttons != null && buttons.isNotEmpty) {
      final List<Map<String, dynamic>> btnList = buttons.map((b) {
        final Map<String, dynamic> btn = {
          'type': b['type'] ?? 'QUICK_REPLY',
          'text': b['text'] ?? '',
        };
        if (b['type'] == 'URL' && b['url'] != null) {
          btn['url'] = b['url']!;
        }
        if (b['type'] == 'PHONE_NUMBER' && b['phone_number'] != null) {
          btn['phone_number'] = b['phone_number']!;
        }
        return btn;
      }).toList();

      components.add({
        'type': 'BUTTONS',
        'buttons': btnList,
      });
    }

    final url = Uri.parse(
        'https://graph.facebook.com/v20.0/$wabaId/message_templates');

    final payload = {
      'name': name.trim().toLowerCase().replaceAll(RegExp(r'\s+'), '_'),
      'language': language,
      'category': category,
      'components': components,
    };

    debugPrint('Creating template: ${jsonEncode(payload)}');

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
      final errMsg = data['error']?['message'] ??
          'Failed to create template: ${response.statusCode}';
      final errCode = data['error']?['code']?.toString() ?? '';
      final errSubCode = data['error']?['error_subcode']?.toString() ?? '';
      throw Exception(
          '$errMsg${errCode.isNotEmpty ? ' (Code: $errCode)' : ''}${errSubCode.isNotEmpty ? ' [SubCode: $errSubCode]' : ''}');
    }

    // Return a basic template object with the new ID
    return WhatsAppTemplate(
      id: data['id']?.toString() ?? '',
      name: name.trim().toLowerCase().replaceAll(RegExp(r'\s+'), '_'),
      language: language,
      status: 'PENDING',
      category: category,
      components: components
          .map((c) => TemplateComponent.fromJson(c))
          .toList(),
    );
  }

  /// Delete a message template
  Future<void> deleteTemplate({
    required String name,
  }) async {
    final creds = await _getCredentials();
    final token = creds['access_token'] ?? '';
    final wabaId = creds['waba_id'] ?? '';

    if (token.isEmpty || wabaId.isEmpty) {
      throw Exception('WhatsApp API credentials not configured.');
    }

    final url = Uri.parse(
        'https://graph.facebook.com/v20.0/$wabaId/message_templates?name=$name');

    final response = await http.delete(
      url,
      headers: {'Authorization': 'Bearer $token'},
    );

    final data = jsonDecode(response.body);

    if (response.statusCode != 200 || data['error'] != null) {
      final errMsg = data['error']?['message'] ??
          'Failed to delete template: ${response.statusCode}';
      throw Exception(errMsg);
    }
  }
}
