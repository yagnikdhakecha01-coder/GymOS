import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'supabase_service.dart';

/// Google Drive integration for backup uploads.
/// Uses a manually-provided OAuth2 access token or service account token.
/// Super Admin configures this via Settings → Google Drive.
class GoogleDriveService {
  static String? _accessToken;
  static String? _folderId;
  static bool _isConnected = false;

  static bool get isConnected => _isConnected && _accessToken != null;
  static String? get folderId => _folderId;

  /// Load saved Drive credentials from platform_settings
  static Future<void> loadCredentials() async {
    try {
      if (!AdminSupabaseService.isInitialized) return;
      final result = await AdminSupabaseService.client
          .from('platform_settings')
          .select()
          .eq('key', 'google_drive_config')
          .maybeSingle();

      if (result != null && result['value'] != null) {
        final config = result['value'] as Map<String, dynamic>;
        _accessToken = config['access_token'] as String?;
        _folderId = config['folder_id'] as String?;
        _isConnected = _accessToken != null && _accessToken!.isNotEmpty;
      }
    } catch (e) {
      debugPrint('Error loading Drive credentials: $e');
    }
  }

  /// Save Drive credentials to platform_settings
  static Future<void> saveCredentials({
    required String accessToken,
    String? folderId,
  }) async {
    _accessToken = accessToken;
    _folderId = folderId;
    _isConnected = accessToken.isNotEmpty;

    try {
      if (!AdminSupabaseService.isInitialized) return;
      await AdminSupabaseService.client.from('platform_settings').upsert({
        'key': 'google_drive_config',
        'value': {
          'access_token': accessToken,
          'folder_id': folderId ?? '',
          'connected_at': DateTime.now().toIso8601String(),
        },
        'updated_at': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      debugPrint('Error saving Drive credentials: $e');
    }
  }

  /// Disconnect Google Drive
  static Future<void> disconnect() async {
    _accessToken = null;
    _folderId = null;
    _isConnected = false;

    try {
      if (!AdminSupabaseService.isInitialized) return;
      await AdminSupabaseService.client
          .from('platform_settings')
          .delete()
          .eq('key', 'google_drive_config');
    } catch (e) {
      debugPrint('Error disconnecting Drive: $e');
    }
  }

  /// Test if the current token is valid
  static Future<bool> testConnection() async {
    if (_accessToken == null) return false;
    try {
      final response = await http.get(
        Uri.parse('https://www.googleapis.com/drive/v3/about?fields=user'),
        headers: {'Authorization': 'Bearer $_accessToken'},
      );
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  /// Get connected user info
  static Future<Map<String, dynamic>?> getUserInfo() async {
    if (_accessToken == null) return null;
    try {
      final response = await http.get(
        Uri.parse('https://www.googleapis.com/drive/v3/about?fields=user'),
        headers: {'Authorization': 'Bearer $_accessToken'},
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['user'] as Map<String, dynamic>?;
      }
    } catch (e) {
      debugPrint('Error fetching Drive user info: $e');
    }
    return null;
  }

  /// Upload backup JSON to Google Drive
  static Future<String?> uploadBackup({
    required String backupJson,
    required String fileName,
  }) async {
    if (_accessToken == null) return null;

    try {
      // Create file metadata
      final metadata = {
        'name': fileName,
        'mimeType': 'application/json',
      };

      // If folder ID is set, upload to that folder
      if (_folderId != null && _folderId!.isNotEmpty) {
        metadata['parents'] = _folderId!;
      }

      // Use multipart upload
      final metadataBytes = utf8.encode(jsonEncode(metadata));
      final contentBytes = utf8.encode(backupJson);

      final boundary = '===gymos_backup_boundary===';
      final body = StringBuffer();
      body.write('--$boundary\r\n');
      body.write('Content-Type: application/json; charset=UTF-8\r\n\r\n');
      body.write(jsonEncode(metadata));
      body.write('\r\n--$boundary\r\n');
      body.write('Content-Type: application/json\r\n\r\n');
      body.write(backupJson);
      body.write('\r\n--$boundary--');

      final response = await http.post(
        Uri.parse('https://www.googleapis.com/upload/drive/v3/files?uploadType=multipart&fields=id,webViewLink'),
        headers: {
          'Authorization': 'Bearer $_accessToken',
          'Content-Type': 'multipart/related; boundary=$boundary',
        },
        body: body.toString(),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = jsonDecode(response.body);
        final fileId = data['id'] as String?;
        final webLink = data['webViewLink'] as String?;

        // Make file readable via link
        if (fileId != null) {
          try {
            await http.post(
              Uri.parse('https://www.googleapis.com/drive/v3/files/$fileId/permissions'),
              headers: {
                'Authorization': 'Bearer $_accessToken',
                'Content-Type': 'application/json',
              },
              body: jsonEncode({
                'role': 'reader',
                'type': 'anyone',
              }),
            );
          } catch (_) {}
        }

        return webLink ?? 'https://drive.google.com/file/d/$fileId/view';
      } else {
        debugPrint('Drive upload failed: ${response.statusCode} ${response.body}');
        return null;
      }
    } catch (e) {
      debugPrint('Error uploading to Drive: $e');
      return null;
    }
  }

  /// List backup files from Drive folder
  static Future<List<Map<String, dynamic>>> listBackups() async {
    if (_accessToken == null) return [];
    try {
      String query = "name contains 'gymos_backup' and mimeType='application/json'";
      if (_folderId != null && _folderId!.isNotEmpty) {
        query += " and '$_folderId' in parents";
      }
      query += " and trashed=false";

      final response = await http.get(
        Uri.parse('https://www.googleapis.com/drive/v3/files?q=${Uri.encodeComponent(query)}&fields=files(id,name,size,createdTime,webViewLink)&orderBy=createdTime desc&pageSize=50'),
        headers: {'Authorization': 'Bearer $_accessToken'},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return List<Map<String, dynamic>>.from(data['files'] ?? []);
      }
    } catch (e) {
      debugPrint('Error listing Drive backups: $e');
    }
    return [];
  }
}
