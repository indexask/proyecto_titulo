import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/almacen_local.dart';
import '../../../core/errores.dart';
import '../../../core/supabase_client.dart';
import '../dominio/usuario.dart';

/// Autenticación con Supabase Auth (RF-01, RF-04) y lectura del rol (RF-02).
class AuthRepositorio {
  final AlmacenLocal _local;

  AuthRepositorio(this._local);

  Stream<AuthState> get cambiosDeSesion => supabase.auth.onAuthStateChange;

  String? get usuarioIdActual => supabase.auth.currentUser?.id;

  Future<void> iniciarSesion({required String correo, required String contrasena}) {
    return supabase.auth.signInWithPassword(email: correo, password: contrasena);
  }

  /// Cierre de sesión seguro: invalida la sesión en Supabase y borra los
  /// datos guardados en el dispositivo para ese usuario.
  Future<void> cerrarSesion() async {
    final id = usuarioIdActual;
    try {
      await supabase.auth.signOut();
    } finally {
      if (id != null) await _local.borrarUsuario(id);
    }
  }

  /// Obtiene el usuario y su rol. Si no hay conexión usa la última copia
  /// guardada, para que el Chofer pueda abrir la app sin internet (RF-15).
  Future<Usuario> obtenerUsuario(String id) async {
    try {
      final data = await supabase.from('usuario').select('id, nombre, rol').eq('id', id).single();
      final usuario = Usuario.fromMap(data);
      await _local.guardarJson(id, 'usuario', usuario.toMap());
      return usuario;
    } catch (e) {
      if (!esErrorDeConexion(e)) rethrow;
      final cache = await _local.leerJson(id, 'usuario');
      if (cache is Map<String, dynamic>) return Usuario.fromMap(cache);
      rethrow;
    }
  }
}
