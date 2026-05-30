import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

class R2StorageService {
  static const _workerBase = 'https://omni-gym.hadith024.workers.dev';

  // Configura via --dart-define=R2_UPLOAD_SECRET=xxx al correr/buildear
  static const _secret = String.fromEnvironment(
    'R2_UPLOAD_SECRET',
    defaultValue: 'omni-r2-2025-dev',
  );

  /// Sube [bytes] al bucket R2 bajo la ruta [key].
  /// Devuelve la URL pública del archivo.
  static Future<String> upload({
    required Uint8List bytes,
    required String key,
    required String contentType,
  }) async {
    final uri = Uri.parse('$_workerBase/upload');
    final request = http.MultipartRequest('POST', uri)
      ..headers['Authorization'] = 'Bearer $_secret'
      ..files.add(
        http.MultipartFile.fromBytes(
          'file',
          bytes,
          filename: key.split('/').last,
          contentType: MediaType.parse(contentType),
        ),
      )
      ..fields['key'] = key;

    final streamed = await request.send();
    final body = await streamed.stream.bytesToString();

    if (streamed.statusCode != 200) {
      throw Exception('R2 upload failed (${streamed.statusCode}): $body');
    }

    final data = jsonDecode(body) as Map<String, dynamic>;
    return data['url'] as String;
  }

  /// Elimina el archivo en [key] del bucket.
  static Future<void> delete(String key) async {
    final uri = Uri.parse('$_workerBase/delete');
    final response = await http.delete(
      uri,
      headers: {
        'Authorization': 'Bearer $_secret',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'key': key}),
    );
    if (response.statusCode != 200) {
      throw Exception('R2 delete failed (${response.statusCode})');
    }
  }
}
