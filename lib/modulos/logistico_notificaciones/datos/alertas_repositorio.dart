import '../../../core/almacen_local.dart';
import '../../../core/errores.dart';
import '../../../core/supabase_client.dart';
import '../dominio/alerta.dart';

/// Registro de alertas emitidas por el motor de notificaciones (RF-20).
class AlertasRepositorio {
  final AlmacenLocal _local;

  AlertasRepositorio(this._local);

  /// Todas las alertas (Administrador).
  Future<List<Alerta>> listarTodas() async {
    final data = await supabase
        .from('alerta')
        .select('*, orden_compra(cliente, numero_oc, fecha_comprometida)')
        .order('fecha_emision', ascending: false);
    return data.map(Alerta.fromMap).toList();
  }

  /// Alertas de las órdenes de las que el Chofer es responsable. Se guardan
  /// en el dispositivo para consultarlas sin conexión.
  Future<List<Alerta>> listarDelChofer(String usuarioId) async {
    try {
      final data =
          await supabase.from('v_alerta_chofer').select().order('fecha_emision', ascending: false);
      await _local.guardarJson(usuarioId, 'alertas', data);
      return data.map(Alerta.fromMap).toList();
    } catch (e) {
      if (!esErrorDeConexion(e)) rethrow;
      final cache = await _local.leerJson(usuarioId, 'alertas');
      if (cache is List) return cache.map((m) => Alerta.fromMap(m as Map<String, dynamic>)).toList();
      rethrow;
    }
  }
}
