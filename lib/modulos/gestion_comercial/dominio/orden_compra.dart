import '../../logistico_notificaciones/dominio/estado_despacho.dart';
import 'rentabilidad.dart';

/// Línea de una orden de compra (RF-05, RF-06). Guarda el costo y el precio
/// adjudicado de esa licitación.
class DetalleOrden implements LineaConMargen {
  final String? id;
  final String productoId;
  final String productoNombre;
  final String? productoFotoPath;
  @override
  final int cantidad;
  @override
  final num costoCompra;
  @override
  final num precioVenta;

  const DetalleOrden({
    this.id,
    required this.productoId,
    required this.productoNombre,
    this.productoFotoPath,
    required this.cantidad,
    required this.costoCompra,
    required this.precioVenta,
  });

  num get margen => margenDeLinea(this);

  factory DetalleOrden.fromMap(Map<String, dynamic> map) => DetalleOrden(
        id: map['id'] as String?,
        productoId: map['producto_id'] as String,
        productoNombre: (map['producto'] as Map<String, dynamic>?)?['nombre'] as String? ?? '—',
        productoFotoPath: (map['producto'] as Map<String, dynamic>?)?['foto_path'] as String?,
        cantidad: map['cantidad'] as int,
        costoCompra: map['costo_compra'] as num,
        precioVenta: map['precio_venta'] as num,
      );

  Map<String, dynamic> toInsert(String ordenId) => {
        'orden_id': ordenId,
        'producto_id': productoId,
        'cantidad': cantidad,
        'costo_compra': costoCompra,
        'precio_venta': precioVenta,
      };
}

/// Datos del despacho vistos desde el panel del Administrador.
class DespachoResumen {
  final String id;
  final EstadoDespacho estado;
  final int? cantidadBultos;
  final DateTime? fechaHoraEntrega;
  final bool confirmadoEnApp;

  const DespachoResumen({
    required this.id,
    required this.estado,
    this.cantidadBultos,
    this.fechaHoraEntrega,
    this.confirmadoEnApp = false,
  });

  factory DespachoResumen.fromMap(Map<String, dynamic> map) => DespachoResumen(
        id: map['id'] as String,
        estado: EstadoDespacho.desdeCodigo(map['estado'] as String?),
        cantidadBultos: map['cantidad_bultos'] as int?,
        fechaHoraEntrega: map['fecha_hora_entrega'] == null
            ? null
            : DateTime.parse(map['fecha_hora_entrega'] as String),
        confirmadoEnApp: map['confirmado_en_app'] as bool? ?? false,
      );
}

/// Adjudicación / orden de compra de Mercado Público (RF-05, RF-09, RF-10).
class OrdenCompra {
  final String id;
  final String? numeroOc;
  final String? numeroCotizacion;
  final DateTime? fechaCotizacion;
  final String cliente;
  final String direccionEntrega;
  final double? direccionLat;
  final double? direccionLng;
  final DateTime fechaComprometida;
  final DateTime? fechaHoraEntrega;
  final num margenNeto;
  final String? responsableId;
  final String? responsableNombre;
  final DateTime createdAt;
  final List<DetalleOrden> detalles;
  final DespachoResumen? despacho;

  const OrdenCompra({
    required this.id,
    required this.cliente,
    required this.direccionEntrega,
    required this.fechaComprometida,
    required this.margenNeto,
    required this.createdAt,
    this.numeroOc,
    this.numeroCotizacion,
    this.fechaCotizacion,
    this.direccionLat,
    this.direccionLng,
    this.fechaHoraEntrega,
    this.responsableId,
    this.responsableNombre,
    this.detalles = const [],
    this.despacho,
  });

  num get ventaTotal => calcularVentaTotal(detalles);

  String get titulo {
    final codigo = (numeroOc?.isNotEmpty ?? false) ? numeroOc : numeroCotizacion;
    return codigo == null || codigo.isEmpty ? cliente : '$codigo · $cliente';
  }

  bool get geocodificada => direccionLat != null && direccionLng != null;

  /// Días que faltan para el plazo (negativo si está vencida).
  int diasParaVencer(DateTime hoy) => fechaComprometida.difference(hoy).inDays;

  factory OrdenCompra.fromMap(Map<String, dynamic> map) {
    final despacho = map['despacho'];
    final despachoMap = despacho is List
        ? (despacho.isEmpty ? null : despacho.first as Map<String, dynamic>)
        : despacho as Map<String, dynamic>?;
    return OrdenCompra(
      id: map['id'] as String,
      numeroOc: map['numero_oc'] as String?,
      numeroCotizacion: map['numero_cotizacion'] as String?,
      fechaCotizacion: map['fecha_cotizacion'] == null
          ? null
          : DateTime.parse(map['fecha_cotizacion'] as String),
      cliente: map['cliente'] as String,
      direccionEntrega: map['direccion_entrega'] as String,
      direccionLat: (map['direccion_lat'] as num?)?.toDouble(),
      direccionLng: (map['direccion_lng'] as num?)?.toDouble(),
      fechaComprometida: DateTime.parse(map['fecha_comprometida'] as String),
      fechaHoraEntrega: map['fecha_hora_entrega'] == null
          ? null
          : DateTime.parse(map['fecha_hora_entrega'] as String),
      margenNeto: map['margen_neto'] as num? ?? 0,
      responsableId: map['responsable_id'] as String?,
      responsableNombre: (map['responsable'] as Map<String, dynamic>?)?['nombre'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
      detalles: ((map['detalle_orden'] as List?) ?? const [])
          .map((d) => DetalleOrden.fromMap(d as Map<String, dynamic>))
          .toList(),
      despacho: despachoMap == null ? null : DespachoResumen.fromMap(despachoMap),
    );
  }
}
