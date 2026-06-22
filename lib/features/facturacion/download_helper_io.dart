// Platform-specific file download - default (io) implementation
import 'dart:io';
import 'package:url_launcher/url_launcher.dart';

Future<void> downloadFile(String fileName, List<int> bytes) async {
  try {
    final dir = Platform.isAndroid || Platform.isIOS
        ? Directory.systemTemp
        : Directory(_downloadsPath());
    if (!await dir.exists()) await dir.create(recursive: true);
    final file = File('${dir.path}/$fileName');
    await file.writeAsBytes(bytes);
    await launchUrl(Uri.file(file.path), mode: LaunchMode.externalApplication);
  } catch (_) {
    // Fallback silencioso
  }
}

String _downloadsPath() {
  if (Platform.isMacOS || Platform.isLinux) {
    final home = Platform.environment['HOME'] ?? '/tmp';
    return '$home/Downloads';
  }
  if (Platform.isWindows) {
    final home = Platform.environment['USERPROFILE'] ?? 'C:\\';
    return '$home\\Downloads';
  }
  return '/tmp';
}
