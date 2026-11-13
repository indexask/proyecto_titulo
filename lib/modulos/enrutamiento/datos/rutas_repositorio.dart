import '../../../core/almacen_local.dart';
import '../../../core/errores.dart';
import '../../../core/formato.dart';
import '../../../core/supabase_client.dart';
import '../dominio/ruta.dart';

/// Rutas de reparto (RF-21 a RF-24).
class RutasRepositorio {
  final AlmacenLocal _local;

  RutasRepositorio(this._local);

  static const _selectAdmin = '*, chofer:usuario(nombre), '
      'ruta_parada(orden, despacho(id, estado, orden_compra(cliente, direccion_entrega, direccion_lat, direccion_lng)))';

  // --- Administrador -------------------------------------------------------

  Future<List<RutaAdmin>> listar() async {
    final data = await supabase.from('ruta').select(_selectAdmin).order('fecha', ascending: false);
    return data.map(RutaAdmin.fromMap).toList();
  }

  Future<RutaAdmin> obtener(String id) async {
    final data = await supabase.from('ruta').select(_selectAdmin).eq('id', id).single();
    return RutaAdmin.fromMap(data);
  }

  /// Compila las direcciones de los despachos elegidos y pide a la Edge
  /// Function `optimizar-ruta` la ruta óptima (Routes API). Primero se visita
  /// lo que vence en la jornada; después se optimiza por distancia/costo.
  /// Devuelve el id y las advertencias (p. ej. plazos ya vencidos).
  /// Con varios choferes, el servidor reparte los despachos en un lote por
  /// chofer (VRP) y crea una ruta para cada uno. Devuelve los ids creados.
  Future<({List<String> ids, List<String> advertencias})> crearOptimizada({
    required DateTime fecha,
    required List<String> choferIds,
    required String origenDireccion,
    required double origenLat,
    required double origenLng,
    required List<String> despachoIds,
    String horaSalida = '09:00',
  }) async {
    final res = await supabase.functions.invoke('optimizar-ruta', body: {
      'fecha': fechaIso(fecha),
      'horaSalida': horaSalida,
      'choferIds': choferIds,
      'origen': {'direccion': origenDireccion, 'lat': origenLat, 'lng': origenLng},
      'despachoIds': despachoIds,
    });
    final data = res.data as Map<String, dynamic>;
    final rutas = (data['rutas'] as List?) ?? [if (data['rutaId'] != null) {'rutaId': data['rutaId']}];
    return (
      ids: [for (final r in rutas) (r as Map<String, dynamic>)['rutaId'] as String],
      advertencias: ((data['advertencias'] as List?) ?? const []).cast<String>(),
    );
  }

  /// Asigna (o quita, con null) el Chofer de una ruta ya creada. La vista
  /// v_ruta_chofer filtra por ruta.chofer_id, así que el cambio basta para
  /// que la ruta aparezca en "Mi jornada" del Chofer.
  Future<void> asignarChofer(String rutaId, String? choferId) =>
      supabase.from('ruta').update({'chofer_id': choferId}).eq('id', rutaId);

  /// Aplica otra de las alternativas calculadas (trazado, orden de paradas,
  /// km, tiempo, TAG y costo) según el criterio elegido. Atómico en la base
  /// (RPC elegir_alternativa_ruta); se rechaza si la ruta ya comenzó.
  Future<void> elegirAlternativa({
    required String rutaId,
    required AlternativaRuta alternativa,
    required CriterioRuta criterio,
    String? motivo,
  }) async {
    await supabase.rpc('elegir_alternativa_ruta', params: {
        'p_ruta_id': rutaId,
        'p_alternativa': alternativa.codigo,
        'p_criterio': criterio.codigo,
        'p_motivo': motivo,
      });
  }

  Future<void> eliminar(String id) => supabase.from('ruta').delete().eq('id', id);

  // --- Chofer (vista sin costos ni ahorro) ---------------------------------

  /// Rutas asignadas al Chofer. Se guardan en el dispositivo para poder
  /// consultarlas sin conexión.
  Future<List<RutaChoferFila>> listarDelChofer(String usuarioId) async {
    try {
      final data = await supabase.from('v_ruta_chofer').select().order('fecha', ascending: false);
      await _local.guardarJson(usuarioId, 'rutas', data);
      return data.map(RutaChoferFila.new).toList();
    } catch (e) {
      if (!esErrorDeConexion(e)) rethrow;
      final cache = await _local.leerJson(usuarioId, 'rutas');
      if (cache is List) {
        return cache.map((m) => RutaChoferFila(m as Map<String, dynamic>)).toList();
      }
      rethrow;
    }
  }
}
