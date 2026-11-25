import 'package:supabase_flutter/supabase_flutter.dart';

/// Traduce las excepciones de Supabase a un mensaje legible para el usuario.
String mensajeError(Object error) {
  if (error is AuthException) {
    if (error.message.toLowerCase().contains('invalid login')) {
      return 'Correo o contraseña incorrectos';
    }
    return error.message;
  }
  if (error is PostgrestException) return error.message;
  if (error is FunctionException) {
    final detalles = error.details;
    if (detalles is Map && detalles['error'] != null) {
      return detalles['error'].toString();
    }
    return 'Error del servidor (${error.status})';
  }
  final texto = error.toString();
  return texto.startsWith('Exception: ') ? texto.substring(11) : texto;
}

/// `true` si el error proviene de la falta de conexión (y no de un rechazo
/// del servidor). Se usa para decidir si reintentar más tarde (offline-first).
bool esErrorDeConexion(Object error) {
  if (error is PostgrestException || error is AuthException || error is FunctionException) {
    return false;
  }
  return true;
}
