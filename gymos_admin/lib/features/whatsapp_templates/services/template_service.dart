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

  /// Get list of variable place-holders like ['1', '2'] from bodyText
  List<String> get bodyVariableKeys {
    final matches = RegExp(r'\{\{(\d+)\}\}').allMatches(bodyText);
    final keys = <String>{};
    for (final m in matches) {
      final key = m.group(1);
      if (key != null) keys.add(key);
    }
    final sorted = keys.toList();
    sorted.sort((a, b) => (int.tryParse(a) ?? 0).compareTo(int.tryParse(b) ?? 0));
    return sorted;
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
    String phoneId = '';

    if (res != null && res['value'] != null) {
      final val = Map<String, dynamic>.from(res['value']);
      token = val['access_token']?.toString() ?? '';
      wabaId = val['business_account_id']?.toString() ?? '';
      phoneId = val['phone_number_id']?.toString() ?? '';
    }

    _cachedCredentials = {
      'access_token': token.trim(),
      'waba_id': wabaId.trim(),
      'phone_number_id': phoneId.trim(),
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

  /// Send an approved template message to a phone number via Meta Cloud API
  Future<Map<String, dynamic>> sendTemplateMessage({
    required String toPhoneNumber,
    required String templateName,
    required String languageCode,
    List<String> bodyVariables = const [],
    String? contactName,
  }) async {
    final cleanPhone = toPhoneNumber.replaceAll(RegExp(r'[^0-9]'), '');
    if (cleanPhone.isEmpty) {
      throw Exception('Invalid phone number provided.');
    }

    final creds = await _getCredentials();
    final token = creds['access_token'] ?? '';
    final phoneId = creds['phone_number_id'] ?? '';

    if (token.isEmpty || phoneId.isEmpty) {
      throw Exception(
          'WhatsApp API credentials or Phone Number ID not configured. Please check Settings > WhatsApp Configuration.');
    }

    final List<Map<String, dynamic>> components = [];
    if (bodyVariables.isNotEmpty) {
      components.add({
        'type': 'body',
        'parameters': bodyVariables
            .map((val) => {'type': 'text', 'text': val.trim()})
            .toList(),
      });
    }

    final Map<String, dynamic> templateObj = {
      'name': templateName,
      'language': {'code': languageCode},
    };
    if (components.isNotEmpty) {
      templateObj['components'] = components;
    }

    final payload = {
      'messaging_product': 'whatsapp',
      'recipient_type': 'individual',
      'to': cleanPhone,
      'type': 'template',
      'template': templateObj,
    };

    final url = Uri.parse('https://graph.facebook.com/v20.0/$phoneId/messages');
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
      final errMsg =
          data['error']?['message'] ?? 'Meta API error: ${response.statusCode}';
      final details = data['error']?['error_data']?['details'] ?? '';
      final code = data['error']?['code']?.toString() ?? '';
      throw Exception(
          '$errMsg${details.isNotEmpty ? ' ($details)' : ''}${code.isNotEmpty ? ' [Error Code: $code]' : ''}');
    }

    final String? wamid = data['messages']?[0]?['id']?.toString();

    // Store in whatsapp_messages table so it immediately shows in chat
    try {
      final client = AdminSupabaseService.client;
      await client.from('whatsapp_messages').insert({
        'wamid': wamid,
        'phone_number': cleanPhone,
        'sender_name': contactName ?? 'GymOS Admin',
        'direction': 'outbound',
        'message_type': 'template',
        'message_body': '[Meta Template: $templateName]',
        'status': 'sent',
        'meta_payload': data,
        'created_at': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      debugPrint('Warning: Could not save template message to database: $e');
    }

    return {
      'success': true,
      'wamid': wamid,
      'data': data,
    };
  }

  /// Get current WhatsApp Invitation configuration from platform_settings
  Future<Map<String, dynamic>> getInvitationSettings() async {
    try {
      final client = AdminSupabaseService.client;
      final res = await client
          .from('platform_settings')
          .select('value')
          .eq('key', 'whatsapp_invitation_settings')
          .maybeSingle();

      if (res != null && res['value'] != null) {
        return Map<String, dynamic>.from(res['value']);
      }
    } catch (e) {
      debugPrint('Error fetching whatsapp_invitation_settings: $e');
    }
    // Default safe configuration (auto_send_enabled: false)
    return {
      'auto_send_enabled': false,
      'template_name': '',
      'template_language': 'en_US',
      'param_mapping': {
        '1': 'gym_name',
        '2': 'name',
        '3': 'invitation_code',
        '4': 'phone',
      },
    };
  }

  /// Save WhatsApp Invitation configuration to platform_settings
  Future<void> saveInvitationSettings(Map<String, dynamic> settings) async {
    final client = AdminSupabaseService.client;
    await client.from('platform_settings').upsert({
      'key': 'whatsapp_invitation_settings',
      'value': settings,
      'updated_at': DateTime.now().toIso8601String(),
    });
  }

  /// Dispatches a mapped WhatsApp invitation template to a contact
  Future<Map<String, dynamic>> sendInvitationTemplate({
    required String toPhoneNumber,
    required String gymName,
    required String contactName,
    required String invitationCode,
    Map<String, dynamic>? customSettings,
  }) async {
    final settings = customSettings ?? await getInvitationSettings();
    final templateName = settings['template_name']?.toString() ?? '';
    final templateLanguage = settings['template_language']?.toString() ?? 'en_US';
    final paramMapping = settings['param_mapping'] != null
        ? Map<String, dynamic>.from(settings['param_mapping'])
        : <String, dynamic>{};

    if (templateName.isEmpty) {
      throw Exception(
          'WhatsApp invitation template is not configured. Please select a template in WA Templates > Invitation Settings.');
    }

    // Sort variable keys: 1, 2, 3...
    final sortedKeys = paramMapping.keys.toList()
      ..sort((a, b) => (int.tryParse(a) ?? 0).compareTo(int.tryParse(b) ?? 0));

    final List<String> bodyVariables = [];
    for (final k in sortedKeys) {
      final field = paramMapping[k]?.toString() ?? '';
      switch (field) {
        case 'gym_name':
          bodyVariables.add(gymName);
          break;
        case 'name':
        case 'member_name':
        case 'staff_name':
          bodyVariables.add(contactName);
          break;
        case 'invitation_code':
        case 'code':
          bodyVariables.add(invitationCode);
          break;
        case 'phone':
        case 'registered_mobile':
          bodyVariables.add(toPhoneNumber);
          break;
        default:
          bodyVariables.add(field.isNotEmpty ? field : '-');
      }
    }

    return await sendTemplateMessage(
      toPhoneNumber: toPhoneNumber,
      templateName: templateName,
      languageCode: templateLanguage,
      bodyVariables: bodyVariables,
      contactName: contactName,
    );
  }
}

