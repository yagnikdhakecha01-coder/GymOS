import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'supabase_service.dart';

class DriveUploadResult {
  final bool success;
  final String? driveUrl;
  final String? fileId;
  final String? folderId;
  final String? error;
  final String? details;

  DriveUploadResult({
    required this.success,
    this.driveUrl,
    this.fileId,
    this.folderId,
    this.error,
    this.details,
  });
}

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
  static String? get currentAccessToken => _accessToken;
  static String? get currentRefreshToken => _refreshToken;

  /// Helper to clean folder ID from raw string or full URL
  static String? _cleanFolderId(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    String id = raw.trim();
    if (id.contains('/folders/')) {
      id = id.split('/folders/').last.split('?').first.split('/').first.trim();
    }
    return id.isNotEmpty ? id : null;
  }

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
        _folderId = _cleanFolderId(config['folder_id'] as String?);
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
    _folderId = _cleanFolderId(folderId);
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
          'folder_id': _folderId ?? '',
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
    if (_accessToken != null && _accessToken!.isNotEmpty) {
      final isAlive = await testConnection();
      if (isAlive) return _accessToken;
    }

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

  /// Finds or creates a dedicated 'GYM OS BACKUP' folder inside Google Drive
  static Future<String?> getOrCreateBackupFolder(String token) async {
    // 1. If user provided a specific folder ID, test if accessible
    if (_folderId != null && _folderId!.isNotEmpty) {
      try {
        final testRes = await http.get(
          Uri.parse('https://www.googleapis.com/drive/v3/files/$_folderId?fields=id,name,trashed'),
          headers: {'Authorization': 'Bearer $token'},
        );
        if (testRes.statusCode == 200) {
          final data = jsonDecode(testRes.body);
          if (data['trashed'] != true) {
            return _folderId;
          }
        }
      } catch (_) {}
    }

    // 2. Search if 'GYM OS BACKUP' folder already exists
    try {
      final searchRes = await http.get(
        Uri.parse('https://www.googleapis.com/drive/v3/files?q=${Uri.encodeComponent("name = 'GYM OS BACKUP' and mimeType = 'application/vnd.google-apps.folder' and trashed = false")}&fields=files(id,name)'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (searchRes.statusCode == 200) {
        final searchData = jsonDecode(searchRes.body);
        final files = searchData['files'] as List?;
        if (files != null && files.isNotEmpty) {
          final existingId = files.first['id'] as String?;
          if (existingId != null) {
            _folderId = existingId;
            return existingId;
          }
        }
      }
    } catch (_) {}

    // 3. Automatically create 'GYM OS BACKUP' folder in Google Drive
    try {
      final createFolderRes = await http.post(
        Uri.parse('https://www.googleapis.com/drive/v3/files?fields=id,name'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json; charset=UTF-8',
        },
        body: jsonEncode({
          'name': 'GYM OS BACKUP',
          'mimeType': 'application/vnd.google-apps.folder',
        }),
      );

      if (createFolderRes.statusCode == 200 || createFolderRes.statusCode == 201) {
        final folderData = jsonDecode(createFolderRes.body);
        final createdId = folderData['id'] as String?;
        if (createdId != null) {
          _folderId = createdId;
          // save into platform settings
          if (AdminSupabaseService.isInitialized) {
            await saveCredentials(
              accessToken: _accessToken ?? token,
              refreshToken: _refreshToken,
              clientId: _clientId,
              clientSecret: _clientSecret,
              folderId: createdId,
            );
          }
          return createdId;
        }
      }
    } catch (e) {
      debugPrint('Error creating backup folder: $e');
    }

    return _folderId;
  }

  /// Run complete step-by-step diagnostic test
  static Future<List<String>> runDiagnostics() async {
    final List<String> logs = [];
    final nowStr = () => DateTime.now().toIso8601String().substring(11, 19);

    logs.add('[${nowStr()}] 🔍 Starting Google Drive Diagnostic Suite...');

    // Step 1: Check token presence
    if (_accessToken == null && _refreshToken == null) {
      logs.add('[${nowStr()}] ❌ FAILED: No token configured. Please enter Access Token or Refresh Token.');
      return logs;
    }

    logs.add('[${nowStr()}] 🔑 Checking Access Token...');
    final token = await getValidAccessToken();
    if (token == null || token.isEmpty) {
      logs.add('[${nowStr()}] ❌ FAILED: Unable to obtain valid Access Token. Refresh token exchange failed.');
      return logs;
    }
    logs.add('[${nowStr()}] ✅ Token obtained (${token.substring(0, 10)}...)');

    // Step 2: Test User Info API
    logs.add('[${nowStr()}] 👤 Testing User Profile API...');
    try {
      final userRes = await http.get(
        Uri.parse('https://www.googleapis.com/drive/v3/about?fields=user,storageQuota'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (userRes.statusCode == 200) {
        final data = jsonDecode(userRes.body);
        final email = data['user']?['emailAddress'] ?? 'Unknown';
        final displayName = data['user']?['displayName'] ?? '';
        logs.add('[${nowStr()}] ✅ Authenticated as: $displayName ($email) [HTTP 200 OK]');
      } else {
        logs.add('[${nowStr()}] ❌ User API Error (${userRes.statusCode}): ${userRes.body}');
        return logs;
      }
    } catch (e) {
      logs.add('[${nowStr()}] ❌ Network error checking user: $e');
      return logs;
    }

    // Step 3: Check / Ensure 'GYM OS BACKUP' Folder
    logs.add('[${nowStr()}] 📁 Locating / Ensuring "GYM OS BACKUP" Folder in your Drive...');
    final activeFolderId = await getOrCreateBackupFolder(token);
    if (activeFolderId != null && activeFolderId.isNotEmpty) {
      logs.add('[${nowStr()}] ✅ Target Folder Ready: "GYM OS BACKUP" (ID: $activeFolderId)');
    } else {
      logs.add('[${nowStr()}] ⚠️ Notice: Folder creation fallback to Root');
    }

    // Step 4: Test Upload a test ping file directly into the folder
    logs.add('[${nowStr()}] 📤 Testing Upload into "GYM OS BACKUP" folder...');
    try {
      final pingResult = await uploadBackup(
        backupJson: jsonEncode({
          'test': true,
          'system': 'GymOS Enterprise Drive Diagnostic',
          'folder_target': 'GYM OS BACKUP',
          'timestamp': DateTime.now().toIso8601String(),
        }),
        fileName: 'gymos_diagnostic_ping.json',
      );

      if (pingResult.success) {
        logs.add('[${nowStr()}] 🎉 SUCCESS: Test file uploaded inside "GYM OS BACKUP" folder!');
        logs.add('[${nowStr()}] 🔗 File Link: ${pingResult.driveUrl}');
      } else {
        logs.add('[${nowStr()}] ❌ UPLOAD FAILED: ${pingResult.error}');
        if (pingResult.details != null) {
          logs.add('[${nowStr()}] 📋 Details: ${pingResult.details}');
        }
      }
    } catch (e) {
      logs.add('[${nowStr()}] ❌ Upload exception: $e');
    }

    return logs;
  }

  /// Upload backup JSON into 'GYM OS BACKUP' folder
  static Future<DriveUploadResult> uploadBackup({
    required String backupJson,
    required String fileName,
  }) async {
    final token = await getValidAccessToken();
    if (token == null) {
      return DriveUploadResult(
        success: false,
        error: 'No valid access token. Please enter token or reconnect Drive.',
      );
    }

    // Ensure we have the target folder ID (auto-create if needed)
    final targetFolder = await getOrCreateBackupFolder(token);

    // Upload directly into the folder
    DriveUploadResult res = await _executeTwoStepUpload(
      token: token,
      backupJson: backupJson,
      fileName: fileName,
      targetFolderId: targetFolder,
    );

    // If specific folder failed, fallback to root
    if (!res.success && targetFolder != null && targetFolder.isNotEmpty) {
      debugPrint('Folder upload failed (${res.error}), trying root...');
      res = await _executeTwoStepUpload(
        token: token,
        backupJson: backupJson,
        fileName: fileName,
        targetFolderId: null,
      );
    }

    return res;
  }

  /// 2-Step Official Google Drive Upload
  static Future<DriveUploadResult> _executeTwoStepUpload({
    required String token,
    required String backupJson,
    required String fileName,
    String? targetFolderId,
  }) async {
    try {
      // Step 1: Create File Metadata
      final Map<String, dynamic> metadata = {
        'name': fileName,
        'mimeType': 'application/json',
      };
      if (targetFolderId != null && targetFolderId.isNotEmpty) {
        metadata['parents'] = [targetFolderId];
      }

      final createRes = await http.post(
        Uri.parse('https://www.googleapis.com/drive/v3/files?fields=id,webViewLink,name,parents'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json; charset=UTF-8',
        },
        body: jsonEncode(metadata),
      );

      if (createRes.statusCode != 200 && createRes.statusCode != 201) {
        final errBody = createRes.body;
        debugPrint('Step 1 Metadata Creation Failed: ${createRes.statusCode} $errBody');
        return DriveUploadResult(
          success: false,
          error: 'Metadata Creation Failed (HTTP ${createRes.statusCode})',
          details: errBody,
        );
      }

      final createData = jsonDecode(createRes.body);
      final fileId = createData['id'] as String?;
      final webViewLink = createData['webViewLink'] as String?;

      if (fileId == null) {
        return DriveUploadResult(
          success: false,
          error: 'No File ID returned from Google Drive',
          details: createRes.body,
        );
      }

      // Step 2: Upload Content
      final uploadRes = await http.patch(
        Uri.parse('https://www.googleapis.com/upload/drive/v3/files/$fileId?uploadType=media'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json; charset=UTF-8',
        },
        body: backupJson,
      );

      if (uploadRes.statusCode != 200 && uploadRes.statusCode != 201) {
        final uploadErr = uploadRes.body;
        debugPrint('Step 2 Content Upload Failed: ${uploadRes.statusCode} $uploadErr');
        return DriveUploadResult(
          success: false,
          fileId: fileId,
          error: 'Content Upload Failed (HTTP ${uploadRes.statusCode})',
          details: uploadErr,
        );
      }

      debugPrint('✅ Google Drive Upload Success into folder $targetFolderId! File ID: $fileId');

      // Make link accessible
      try {
        await http.post(
          Uri.parse('https://www.googleapis.com/drive/v3/files/$fileId/permissions'),
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({'role': 'reader', 'type': 'anyone'}),
        );
      } catch (_) {}

      final finalUrl = webViewLink ?? 'https://drive.google.com/file/d/$fileId/view';
      return DriveUploadResult(
        success: true,
        driveUrl: finalUrl,
        fileId: fileId,
        folderId: targetFolderId,
      );
    } catch (e) {
      debugPrint('Exception in 2-step Drive upload: $e');
      return DriveUploadResult(
        success: false,
        error: 'Network/Exception: $e',
      );
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
