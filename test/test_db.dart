import 'dart:convert';
import 'dart:io';

void main() async {
  print('Loading .env file...');
  final envFile = File('.env');
  if (!envFile.existsSync()) {
    print('Error: .env file not found!');
    exit(1);
  }

  final lines = envFile.readAsLinesSync();
  String url = '';
  String anonKey = '';

  for (var line in lines) {
    if (line.trim().isEmpty || line.startsWith('#')) continue;
    final parts = line.split('=');
    if (parts.length >= 2) {
      final key = parts[0].trim();
      var value = parts.sublist(1).join('=').trim();
      if (value.startsWith('"') && value.endsWith('"')) {
        value = value.substring(1, value.length - 1);
      }
      if (key == 'SUPABASE_URL') url = value;
      if (key == 'SUPABASE_ANON_KEY') anonKey = value;
    }
  }

  print('URL configured: ${url.isNotEmpty ? "✓ (Set)" : "✗ (Missing)"}');
  print('Anon Key configured: ${anonKey.isNotEmpty ? "✓ (Set)" : "✗ (Missing)"}');

  if (url.isEmpty || anonKey.isEmpty) {
    print('Error: URL or Anon Key is empty in .env');
    exit(1);
  }

  final client = HttpClient();
  try {
    print('Querying gyms...');
    final gymsUri = Uri.parse('$url/rest/v1/gyms?select=*&limit=1');
    final request = await client.getUrl(gymsUri);
    request.headers.add('apikey', anonKey);
    request.headers.add('Authorization', 'Bearer $anonKey');

    final response = await request.close();
    final body = await response.transform(utf8.decoder).join();
    print('GYMS Query Status: ${response.statusCode}');
    print('GYMS Query Response: $body');

    print('Querying profiles...');
    final profilesUri = Uri.parse('$url/rest/v1/profiles?select=*&limit=1');
    final request2 = await client.getUrl(profilesUri);
    request2.headers.add('apikey', anonKey);
    request2.headers.add('Authorization', 'Bearer $anonKey');

    final response2 = await request2.close();
    final body2 = await response2.transform(utf8.decoder).join();
    print('PROFILES Query Status: ${response2.statusCode}');
    print('PROFILES Query Response: $body2');

  } catch (e) {
    print('HTTP Request failed: $e');
  } finally {
    client.close();
  }
  exit(0);
}
