import '../../../core/supabase_client.dart';
import '../dominio/usuario.dart';

/// Listado de usuarios para asignar responsables y choferes (solo Administrador).
class UsuariosRepositorio {
  Future<List<Usuario>> listar({Rol? rol}) async {
    var consulta = supabase.from('usuario').select('id, nombre, rol');
    if (rol != null) consulta = consulta.eq('rol', rol.name);
    final data = await consulta.order('nombre');
    return data.map(Usuario.fromMap).toList();
  }
}
