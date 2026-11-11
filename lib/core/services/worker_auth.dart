import 'package:firebase_auth/firebase_auth.dart';

/// Backend authorization uses the signed-in Firebase identity, never a bundled secret.
Future<Map<String, String>> workerHeaders() async {
  final token = await FirebaseAuth.instance.currentUser?.getIdToken();
  if (token == null) throw StateError('Inicia sesión para continuar.');
  return {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'};
}
