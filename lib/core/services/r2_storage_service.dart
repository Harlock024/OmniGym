import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'worker_auth.dart';

import 'package:http_parser/http_parser.dart';

class R2StorageService {
  static const _workerBase = String.fromEnvironment(
    'WORKER_BASE_URL',
    defaultValue: 'https://omni-gym.hadith024.workers.dev',
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
      ..headers.addAll(await workerHeaders())
      ..files.add(
        http.MultipartFile.fromBytes(
          'file',
          bytes,
          filename: key.split('/').last,
          contentType: MediaType.parse(contentType),
        ),
      )
      ..fields['key'] = key;

    request.headers.remove('Content-Type');
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
      headers: await workerHeaders(),
      body: jsonEncode({'key': key}),
    );
    if (response.statusCode != 200) {
      throw Exception('R2 delete failed (${response.statusCode})');
    }
  }
}
