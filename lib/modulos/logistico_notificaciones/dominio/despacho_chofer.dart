import 'estado_despacho.dart';

/// Producto y cantidad a cargar (sin precios).
typedef ItemCarga = ({String producto, int cantidad});

/// Despacho tal como lo ve el Chofer (vista v_despacho_chofer, RF-13).
/// Por diseño NO contiene costos, precios, márgenes ni ahorro (RF-03).
class DespachoChofer {
  final String despachoId;
  final String ordenId;
  final EstadoDespacho estado;
  final int? cantidadBultos;
  final DateTime? fechaHoraEntrega;
  final String? numeroOc;
  final String cliente;
  final String direccionEntrega;
  final double? direccionLat;
  final double? direccionLng;
  final DateTime fechaComprometida;
  final List<ItemCarga> productos;

  /// `true` si el estado mostrado aún no se ha sincronizado con el servidor.
  final bool pendienteDeSincronizar;

  const DespachoChofer({
    required this.despachoId,
    required this.ordenId,
    required this.estado,
    required this.cliente,
    required this.direccionEntrega,
    required this.fechaComprometida,
    this.cantidadBultos,
    this.fechaHoraEntrega,
    this.numeroOc,
    this.direccionLat,
    this.direccionLng,
    this.productos = const [],
    this.pendienteDeSincronizar = false,
  });

  DespachoChofer conEstado(EstadoDespacho nuevo, DateTime momento) => DespachoChofer(
        despachoId: despachoId,
        ordenId: ordenId,
        estado: nuevo,
        cantidadBultos: cantidadBultos,
        fechaHoraEntrega: nuevo == EstadoDespacho.entregado ? momento : fechaHoraEntrega,
        numeroOc: numeroOc,
        cliente: cliente,
        direccionEntrega: direccionEntrega,
        direccionLat: direccionLat,
        direccionLng: direccionLng,
        fechaComprometida: fechaComprometida,
        productos: productos,
        pendienteDeSincronizar: true,
      );

  factory DespachoChofer.fromMap(Map<String, dynamic> map) => DespachoChofer(
        despachoId: map['despacho_id'] as String,
        ordenId: map['orden_id'] as String,
        estado: EstadoDespacho.desdeCodigo(map['estado'] as String?),
        cantidadBultos: map['cantidad_bultos'] as int?,
        fechaHoraEntrega: map['fecha_hora_entrega'] == null
            ? null
            : DateTime.parse(map['fecha_hora_entrega'] as String),
        numeroOc: map['numero_oc'] as String?,
        cliente: map['cliente'] as String,
        direccionEntrega: map['direccion_entrega'] as String,
        direccionLat: (map['direccion_lat'] as num?)?.toDouble(),
        direccionLng: (map['direccion_lng'] as num?)?.toDouble(),
        fechaComprometida: DateTime.parse(map['fecha_comprometida'] as String),
        productos: ((map['productos'] as List?) ?? const [])
            .map((p) => (producto: p['producto'] as String, cantidad: p['cantidad'] as int))
            .toList(),
      );
}

/// Cambio de estado hecho en el dispositivo y aún no confirmado por el
/// servidor (cola offline, RF-15).
class CambioPendiente {
  final String id;
  final String despachoId;
  final EstadoDespacho estado;
  final DateTime ocurridoEn;

  const CambioPendiente({
    required this.id,
    required this.despachoId,
    required this.estado,
    required this.ocurridoEn,
  });

  factory CambioPendiente.fromMap(Map<String, dynamic> map) => CambioPendiente(
        id: map['id'] as String,
        despachoId: map['despacho_id'] as String,
        estado: EstadoDespacho.desdeCodigo(map['estado'] as String),
        ocurridoEn: DateTime.parse(map['ocurrido_en'] as String),
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'despacho_id': despachoId,
        'estado': estado.codigo,
        'ocurrido_en': ocurridoEn.toUtc().toIso8601String(),
      };
}
