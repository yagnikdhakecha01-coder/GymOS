import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'supabase_service.dart';

/// Google Drive integration for automated backup uploads.
/// Supports both Access Token and Refresh Token (Permanent Auto-Renewal).
class GoogleDriveService {
  static String? _accessToken;
  static String? _refreshToken;
  static String? _clientId;
  static String? _clientSecret;
  static String? _folderId;
  static bool _isConnected = false;

  static bool get isConnected => _isConnected && (_accessToken != null || _refreshToken != null);
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
        _refreshToken = config['refresh_token'] as String?;
        _clientId = config['client_id'] as String?;
        _clientSecret = config['client_secret'] as String?;
        _folderId = config['folder_id'] as String?;
        _isConnected = (_accessToken != null && _accessToken!.isNotEmpty) ||
            (_refreshToken != null && _refreshToken!.isNotEmpty);
      }
    } catch (e) {
      debugPrint('Error loading Drive credentials: $e');
    }
  }

  /// Save Drive credentials to platform_settings (Permanent Storage)
  static Future<void> saveCredentials({
    required String accessToken,
    String? refreshToken,
    String? clientId,
    String? clientSecret,
    String? folderId,
  }) async {
    _accessToken = accessToken;
    _refreshToken = refreshToken;
    _clientId = clientId;
    _clientSecret = clientSecret;
    _folderId = folderId;
    _isConnected = accessToken.isNotEmpty || (refreshToken != null && refreshToken.isNotEmpty);

    try {
      if (!AdminSupabaseService.isInitialized) return;
      await AdminSupabaseService.client.from('platform_settings').upsert({
        'key': 'google_drive_config',
        'value': {
          'access_token': accessToken,
          'refresh_token': refreshToken ?? '',
          'client_id': clientId ?? '',
          'client_secret': clientSecret ?? '',
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
    _refreshToken = null;
    _clientId = null;
    _clientSecret = null;
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

  /// Get a valid access token (auto-refreshes using refresh_token if needed)
  static Future<String?> getValidAccessToken() async {
    // 1. If we have a refresh token, try refreshing first or on 401
    if (_accessToken != null) {
      // Test if current access token is still alive
      final isAlive = await testConnection();
      if (isAlive) return _accessToken;
    }

    // 2. If access token expired and we have a refresh token, auto-renew
    if (_refreshToken != null && _refreshToken!.isNotEmpty) {
      final renewed = await _refreshAccessToken();
      if (renewed) return _accessToken;
    }

    return _accessToken;
  }

  /// Auto-refresh token from Google OAuth endpoint
  static Future<bool> _refreshAccessToken() async {
    if (_refreshToken == null || _refreshToken!.isEmpty) return false;

    try {
      final body = {
        'grant_type': 'refresh_token',
        'refresh_token': _refreshToken!,
      };

      if (_clientId != null && _clientId!.isNotEmpty) {
        body['client_id'] = _clientId!;
      }
      if (_clientSecret != null && _clientSecret!.isNotEmpty) {
        body['client_secret'] = _clientSecret!;
      }

      final response = await http.post(
        Uri.parse('https://oauth2.googleapis.com/token'),
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: body,
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final newAccessToken = data['access_token'] as String?;
        if (newAccessToken != null && newAccessToken.isNotEmpty) {
          _accessToken = newAccessToken;
          // Update in DB
          if (AdminSupabaseService.isInitialized) {
            await saveCredentials(
              accessToken: newAccessToken,
              refreshToken: _refreshToken,
              clientId: _clientId,
              clientSecret: _clientSecret,
              folderId: _folderId,
            );
          }
          return true;
        }
      }
    } catch (e) {
      debugPrint('Error auto-refreshing Drive token: $e');
    }
    return false;
  }

  /// Test if connection works
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
    final token = await getValidAccessToken();
    if (token == null) return null;
    try {
      final response = await http.get(
        Uri.parse('https://www.googleapis.com/drive/v3/about?fields=user'),
        headers: {'Authorization': 'Bearer $token'},
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
    final token = await getValidAccessToken();
    if (token == null) return null;

    try {
      final metadata = {
        'name': fileName,
        'mimeType': 'application/json',
      };

      if (_folderId != null && _folderId!.isNotEmpty) {
        metadata['parents'] = _folderId!;
      }

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
          'Authorization': 'Bearer $token',
          'Content-Type': 'multipart/related; boundary=$boundary',
        },
        body: body.toString(),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = jsonDecode(response.body);
        final fileId = data['id'] as String?;
        final webLink = data['webViewLink'] as String?;

        if (fileId != null) {
          try {
            await http.post(
              Uri.parse('https://www.googleapis.com/drive/v3/files/$fileId/permissions'),
              headers: {
                'Authorization': 'Bearer $token',
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
    final token = await getValidAccessToken();
    if (token == null) return [];
    try {
      String query = "name contains 'gymos_backup' and mimeType='application/json'";
      if (_folderId != null && _folderId!.isNotEmpty) {
        query += " and '$_folderId' in parents";
      }
      query += " and trashed=false";

      final response = await http.get(
        Uri.parse('https://www.googleapis.com/drive/v3/files?q=${Uri.encodeComponent(query)}&fields=files(id,name,size,createdTime,webViewLink)&orderBy=createdTime desc&pageSize=50'),
        headers: {'Authorization': 'Bearer $token'},
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
