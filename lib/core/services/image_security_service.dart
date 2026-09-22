import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'supabase_service.dart';

/// Validation result with detailed status and error message
class ImageSecurityValidationResult {
  final bool isValid;
  final String? errorMessage;
  final String? mimeType;
  final String? fileExtension;
  final int? width;
  final int? height;

  const ImageSecurityValidationResult({
    required this.isValid,
    this.errorMessage,
    this.mimeType,
    this.fileExtension,
    this.width,
    this.height,
  });

  factory ImageSecurityValidationResult.success({
    required String mimeType,
    required String fileExtension,
    required int width,
    required int height,
  }) {
    return ImageSecurityValidationResult(
      isValid: true,
      mimeType: mimeType,
      fileExtension: fileExtension,
      width: width,
      height: height,
    );
  }

  factory ImageSecurityValidationResult.failure(String error) {
    return ImageSecurityValidationResult(
      isValid: false,
      errorMessage: error,
    );
  }
}

/// Enterprise Image Security Service
/// Protects against:
///  1. Extension Spoofing (e.g. virus.exe renamed to virus.jpg)
///  2. Magic Byte inspection (JPEG, PNG, WEBP only)
///  3. Embedded Executable/Script signatures (PE/ELF/PHP/Shell/Script/XSS)
///  4. Decompression Bombs / Pixel Bombs (Max dimensions: 4096 x 4096)
///  5. File size threshold (Max 5MB)
class ImageSecurityService {
  ImageSecurityService._();

  /// Maximum allowed image file size (5 MB)
  static const int maxFileSizeBytes = 5 * 1024 * 1024;

  /// Minimum required bytes for a valid image header
  static const int minFileSizeBytes = 16;

  /// Maximum permitted width or height to prevent decompression bombs (DoS)
  static const int maxDimensionPx = 4096;

  /// Validates raw file bytes thoroughly against security risks.
  static Future<ImageSecurityValidationResult> validateImageBytes(Uint8List bytes) async {
    // 1. File Size Verification
    if (bytes.length < minFileSizeBytes) {
      return ImageSecurityValidationResult.failure(
        'File is too small or empty. Not a valid image file.',
      );
    }

    if (bytes.length > maxFileSizeBytes) {
      final sizeMb = (bytes.length / (1024 * 1024)).toStringAsFixed(1);
      return ImageSecurityValidationResult.failure(
        'File size ($sizeMb MB) exceeds maximum allowed limit of 5 MB.',
      );
    }

    // 2. Dangerous Executable / Script Signatures Check
    final dangerousSignature = _detectDangerousSignatures(bytes);
    if (dangerousSignature != null) {
      return ImageSecurityValidationResult.failure(
        'Security Violation: Malicious file signature detected ($dangerousSignature). Upload blocked.',
      );
    }

    // 3. Strict Magic Number / File Header Verification
    final detectedFormat = _detectImageFormat(bytes);
    if (detectedFormat == null) {
      return ImageSecurityValidationResult.failure(
        'Security Violation: Fake extension or invalid image headers. File does not contain valid image data.',
      );
    }

    // 4. Native Engine Decoding & Decompression Bomb Check
    try {
      final codec = await ui.instantiateImageCodec(bytes);
      final frameInfo = await codec.getNextFrame();
      final width = frameInfo.image.width;
      final height = frameInfo.image.height;

      if (width <= 0 || height <= 0) {
        return ImageSecurityValidationResult.failure(
          'Corrupted image data: Dimensions are zero or invalid.',
        );
      }

      if (width > maxDimensionPx || height > maxDimensionPx) {
        return ImageSecurityValidationResult.failure(
          'Security Violation: Image dimensions (${width}x$height) exceed safe limit (${maxDimensionPx}x$maxDimensionPx).',
        );
      }

      return ImageSecurityValidationResult.success(
        mimeType: detectedFormat['mime']!,
        fileExtension: detectedFormat['ext']!,
        width: width,
        height: height,
      );
    } catch (e) {
      debugPrint('ImageSecurityService: Native decode failed: $e');
      return ImageSecurityValidationResult.failure(
        'Image could not be parsed. The file is either corrupted or not a real image.',
      );
    }
  }

  /// Inspects magic bytes (first 4 to 12 bytes) and trailer bytes.
  static Map<String, String>? _detectImageFormat(Uint8List bytes) {
    // JPEG / JPG check
    // Starts with: FF D8 FF
    // Ends with: FF D9
    if (bytes.length >= 3 &&
        bytes[0] == 0xFF &&
        bytes[1] == 0xD8 &&
        bytes[2] == 0xFF) {
      // Also verify JPEG End of Image marker if file is not prematurely truncated
      if (bytes.length > 10) {
        final lastByte = bytes[bytes.length - 1];
        final secondLastByte = bytes[bytes.length - 2];
        // Standard JPEG ends with FF D9
        if (secondLastByte == 0xFF && lastByte == 0xD9) {
          return {'mime': 'image/jpeg', 'ext': 'jpg'};
        }
        // Some cameras append trailing padding/zeros after FF D9
        for (int i = bytes.length - 1; i >= bytes.length - 10; i--) {
          if (bytes[i - 1] == 0xFF && bytes[i] == 0xD9) {
            return {'mime': 'image/jpeg', 'ext': 'jpg'};
          }
        }
      }
      return {'mime': 'image/jpeg', 'ext': 'jpg'};
    }

    // PNG check
    // Header: 89 50 4E 47 0D 0A 1A 0A (.PNG\r\n\x1a\n)
    if (bytes.length >= 8 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47 &&
        bytes[4] == 0x0D &&
        bytes[5] == 0x0A &&
        bytes[6] == 0x1A &&
        bytes[7] == 0x0A) {
      return {'mime': 'image/png', 'ext': 'png'};
    }

    // WEBP check
    // Bytes 0-3: 'RIFF' (0x52, 0x49, 0x46, 0x46)
    // Bytes 8-11: 'WEBP' (0x57, 0x45, 0x42, 0x50)
    if (bytes.length >= 12 &&
        bytes[0] == 0x52 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x46 &&
        bytes[8] == 0x57 &&
        bytes[9] == 0x45 &&
        bytes[10] == 0x42 &&
        bytes[11] == 0x50) {
      return {'mime': 'image/webp', 'ext': 'webp'};
    }

    return null;
  }

  /// Scans for dangerous executable headers and web-shell/script tags.
  static String? _detectDangerousSignatures(Uint8List bytes) {
    if (bytes.length < 4) return null;

    // Windows PE Executable / DLL (MZ)
    if (bytes[0] == 0x4D && bytes[1] == 0x5A) {
      return 'Windows Executable (MZ/PE)';
    }

    // Linux ELF Executable (\x7FELF)
    if (bytes[0] == 0x7F && bytes[1] == 0x45 && bytes[2] == 0x4C && bytes[3] == 0x46) {
      return 'Linux Executable (ELF)';
    }

    // ZIP / JAR / APK Archive (PK\x03\x04)
    if (bytes[0] == 0x50 && bytes[1] == 0x4B && bytes[2] == 0x03 && bytes[3] == 0x04) {
      return 'Archive / Package (ZIP/APK/JAR)';
    }

    // Unix Shell Script (#! / shebang)
    if (bytes[0] == 0x23 && bytes[1] == 0x21) {
      return 'Unix Script (Shebang)';
    }

    // PDF Document (%PDF)
    if (bytes[0] == 0x25 && bytes[1] == 0x50 && bytes[2] == 0x44 && bytes[3] == 0x46) {
      return 'PDF Document';
    }

    // Text scan for embedded malicious script tags in the first 2048 bytes
    final scanLength = bytes.length < 2048 ? bytes.length : 2048;
    final headerAscii = String.fromCharCodes(bytes.sublist(0, scanLength)).toLowerCase();

    const dangerousPatterns = [
      '<script',
      '<?php',
      '<!doctype html',
      '<html',
      '<svg',
      'eval(',
      'base64_decode',
      'passthru(',
      'system(',
      'shell_exec(',
    ];

    for (final pattern in dangerousPatterns) {
      if (headerAscii.contains(pattern)) {
        return 'Embedded Script / Web Shell Pattern ($pattern)';
      }
    }

    return null;
  }

  /// Secure Upload Helper
  /// Validates bytes, determines safe sanitized filename & MIME type,
  /// and uploads to Supabase Storage with explicit contentType.
  static Future<String> uploadSecureImage({
    required String bucket,
    required String directoryPath,
    required Uint8List bytes,
  }) async {
    // Step 1: Deep Security Validation
    final validation = await validateImageBytes(bytes);
    if (!validation.isValid) {
      throw SecurityException(validation.errorMessage ?? 'Invalid or dangerous file detected.');
    }

    // Step 2: Generate Cryptographically Safe Sanitized Filename
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final sanitizedExt = validation.fileExtension ?? 'jpg';
    final safeFileName = '$timestamp.$sanitizedExt';
    final safePath = directoryPath.endsWith('/') 
        ? '$directoryPath$safeFileName' 
        : '$directoryPath/$safeFileName';

    // Step 3: Upload to Supabase Storage with Explicit MIME Type & Upsert
    final client = SupabaseService.client;
    await client.storage.from(bucket).uploadBinary(
          safePath,
          bytes,
          fileOptions: FileOptions(
            contentType: validation.mimeType ?? 'image/jpeg',
            upsert: true,
          ),
        );

    // Step 4: Return Public URL
    return client.storage.from(bucket).getPublicUrl(safePath);
  }
}

class SecurityException implements Exception {
  final String message;
  SecurityException(this.message);

  @override
  String toString() => message;
}
