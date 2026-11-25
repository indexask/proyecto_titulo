import '../../../core/formato.dart';
import '../../../core/supabase_client.dart';
import '../dominio/orden_compra.dart';

/// CRUD de adjudicaciones / órdenes de compra (RF-05, RF-06, RF-09, RF-10)
/// y registro de bultos del despacho (RF-12). Solo Administrador (RLS).
class OrdenesRepositorio {
  static const _select = '*, responsable:usuario(nombre), '
      'detalle_orden(*, producto(nombre, foto_path)), despacho(*)';

  Future<List<OrdenCompra>> listar() async {
    final data = await supabase
        .from('orden_compra')
        .select(_select)
        .order('fecha_comprometida', ascending: true);
    return data.map(OrdenCompra.fromMap).toList();
  }

  Future<OrdenCompra> obtener(String id) async {
    final data = await supabase.from('orden_compra').select(_select).eq('id', id).single();
    return OrdenCompra.fromMap(data);
  }

  /// Crea o actualiza la orden y reemplaza sus líneas. El margen neto lo
  /// recalcula la base de datos al guardar las líneas (RF-07).
  Future<String> guardar({
    String? id,
    String? numeroOc,
    String? numeroCotizacion,
    DateTime? fechaCotizacion,
    required String cliente,
    required String direccionEntrega,
    required double? direccionLat,
    required double? direccionLng,
    required DateTime fechaComprometida,
    required String? responsableId,
    required List<DetalleOrden> detalles,
  }) async {
    final valores = {
      'numero_oc': (numeroOc == null || numeroOc.isEmpty) ? null : numeroOc,
      'numero_cotizacion':
          (numeroCotizacion == null || numeroCotizacion.isEmpty) ? null : numeroCotizacion,
      'fecha_cotizacion': fechaCotizacion == null ? null : fechaIso(fechaCotizacion),
      'cliente': cliente,
      'direccion_entrega': direccionEntrega,
      'direccion_lat': direccionLat,
      'direccion_lng': direccionLng,
      'fecha_comprometida': fechaIso(fechaComprometida),
      'responsable_id': responsableId,
    };

    final String ordenId;
    if (id == null) {
      final fila = await supabase.from('orden_compra').insert(valores).select('id').single();
      ordenId = fila['id'] as String;
    } else {
      await supabase.from('orden_compra').update(valores).eq('id', id);
      await supabase.from('detalle_orden').delete().eq('orden_id', id);
      ordenId = id;
    }

    if (detalles.isNotEmpty) {
      await supabase.from('detalle_orden').insert(detalles.map((d) => d.toInsert(ordenId)).toList());
    }
    return ordenId;
  }

  Future<void> eliminar(String id) => supabase.from('orden_compra').delete().eq('id', id);

  /// RF-12: cantidad de bultos del despacho.
  Future<void> registrarBultos(String despachoId, int cantidad) =>
      supabase.from('despacho').update({'cantidad_bultos': cantidad}).eq('id', despachoId);
}
