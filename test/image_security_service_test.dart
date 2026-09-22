import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:gymos/core/services/image_security_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ImageSecurityService Virus & Malware Protection Tests', () {
    test('Should REJECT Windows Executable (.exe) disguised as .jpg', () async {
      // Windows PE executable header begins with "MZ" (0x4D, 0x5A)
      final fakeExeBytes = Uint8List.fromList([
        0x4D, 0x5A, 0x90, 0x00, 0x03, 0x00, 0x00, 0x00,
        ...List.filled(200, 0x90), // NOP sled simulation
      ]);

      final result = await ImageSecurityService.validateImageBytes(fakeExeBytes);
      expect(result.isValid, isFalse);
      expect(result.errorMessage, contains('Malicious file signature detected (Windows Executable'));
      print('✅ TEST PASSED: Fake .exe disguised as .jpg successfully BLOCKED!');
    });

    test('Should REJECT Linux Executable (ELF) disguised as .jpg', () async {
      // ELF header: 0x7F 'E' 'L' 'F'
      final fakeElfBytes = Uint8List.fromList([
        0x7F, 0x45, 0x4C, 0x46, 0x02, 0x01, 0x01, 0x00,
        ...List.filled(200, 0x00),
      ]);

      final result = await ImageSecurityService.validateImageBytes(fakeElfBytes);
      expect(result.isValid, isFalse);
      expect(result.errorMessage, contains('Linux Executable (ELF)'));
      print('✅ TEST PASSED: Fake Linux binary disguised as .jpg successfully BLOCKED!');
    });

    test('Should REJECT Web Shell / PHP Script disguised as .jpg', () async {
      // PHP web shell disguised as image
      final phpShell = utf8.encode('<?php system(\$_GET["cmd"]); ?>' + ('A' * 200));
      final fakePhpBytes = Uint8List.fromList(phpShell);

      final result = await ImageSecurityService.validateImageBytes(fakePhpBytes);
      expect(result.isValid, isFalse);
      expect(result.errorMessage, contains('Embedded Script / Web Shell Pattern (<?php)'));
      print('✅ TEST PASSED: PHP Web Shell disguised as .jpg successfully BLOCKED!');
    });

    test('Should REJECT HTML / JavaScript XSS file disguised as .jpg', () async {
      final xssPayload = utf8.encode('<html><script>alert("hacked")</script></html>' + ('B' * 200));
      final fakeHtmlBytes = Uint8List.fromList(xssPayload);

      final result = await ImageSecurityService.validateImageBytes(fakeHtmlBytes);
      expect(result.isValid, isFalse);
      expect(result.errorMessage, contains('Embedded Script / Web Shell Pattern (<script)'));
      print('✅ TEST PASSED: XSS script disguised as .jpg successfully BLOCKED!');
    });

    test('Should REJECT Random text file renamed to .jpg', () async {
      final randomText = utf8.encode('This is just a normal text file with a fake .jpg extension.' + ('C' * 200));
      final fakeJpgBytes = Uint8List.fromList(randomText);

      final result = await ImageSecurityService.validateImageBytes(fakeJpgBytes);
      expect(result.isValid, isFalse);
      expect(result.errorMessage, contains('Fake extension or invalid image headers'));
      print('✅ TEST PASSED: Random text file renamed to .jpg successfully BLOCKED!');
    });

    test('Should REJECT files larger than 5 MB (DoS / Memory Protection)', () async {
      // Allocate 6 MB byte array
      final oversizedBytes = Uint8List(6 * 1024 * 1024);
      // Valid JPEG header at start
      oversizedBytes[0] = 0xFF;
      oversizedBytes[1] = 0xD8;
      oversizedBytes[2] = 0xFF;

      final result = await ImageSecurityService.validateImageBytes(oversizedBytes);
      expect(result.isValid, isFalse);
      expect(result.errorMessage, contains('exceeds maximum allowed limit of 5 MB'));
      print('✅ TEST PASSED: Oversized file bomb (>5MB) successfully BLOCKED!');
    });

    test('Should REJECT tiny / empty files (< 16 bytes)', () async {
      final tinyBytes = Uint8List.fromList([0xFF, 0xD8, 0xFF]);

      final result = await ImageSecurityService.validateImageBytes(tinyBytes);
      expect(result.isValid, isFalse);
      expect(result.errorMessage, contains('File is too small or empty'));
      print('✅ TEST PASSED: Tiny / empty file successfully BLOCKED!');
    });

    test('Should ACCEPT 1x1 valid PNG image bytes', () async {
      // Minimal valid 1x1 PNG bytes (68 bytes + padding to exceed 100 bytes minimum)
      final validPngBase = [
        0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, // PNG Header
        0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52, // IHDR chunk
        0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, // 1x1 px
        0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89,
        0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41, 0x54, // IDAT chunk
        0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00, 0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4,
        0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, // IEND chunk
        0xAE, 0x42, 0x60, 0x82,
      ];
      // Create valid PNG bytes
      final validPng = Uint8List.fromList(validPngBase);

      final result = await ImageSecurityService.validateImageBytes(validPng);
      // It passes magic number and decodes as 1x1
      expect(result.isValid, isTrue);
      expect(result.mimeType, equals('image/png'));
      expect(result.width, equals(1));
      expect(result.height, equals(1));
      print('✅ TEST PASSED: Authentic PNG correctly validated and accepted!');
    });
  });
}
