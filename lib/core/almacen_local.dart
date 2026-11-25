import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Almacenamiento local por usuario (base del enfoque offline-first, RF-15).
/// Cada clave queda prefijada con el id del usuario para que un dispositivo
/// compartido no mezcle datos entre sesiones.
class AlmacenLocal {
  static const _prefijo = 'gygtrack';

  String _clave(String usuarioId, String nombre) => '$_prefijo.$usuarioId.$nombre';

  Future<Object?> leerJson(String usuarioId, String nombre) async {
    final prefs = await SharedPreferences.getInstance();
    final texto = prefs.getString(_clave(usuarioId, nombre));
    return texto == null ? null : jsonDecode(texto);
  }

  Future<void> guardarJson(String usuarioId, String nombre, Object? valor) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_clave(usuarioId, nombre), jsonEncode(valor));
  }

  /// Borra todo lo guardado para el usuario (cierre de sesión seguro, RF-04).
  Future<void> borrarUsuario(String usuarioId) async {
    final prefs = await SharedPreferences.getInstance();
    final prefijo = '$_prefijo.$usuarioId.';
    for (final clave in prefs.getKeys().where((k) => k.startsWith(prefijo)).toList()) {
      await prefs.remove(clave);
    }
  }
}
