class Cotizacion {
  final String id;
  final String titulo;
  final String? cliente;
  final num? monto;
  final String? archivoUrl;
  final String adminId;
  final DateTime createdAt;
  final String? numeroCotizacion;
  final DateTime? fechaCotizacion;
  final String? direccionEntrega;
  final double? direccionLat;
  final double? direccionLng;
  final String? descripcion;
  final num? unidades;
  final num? precioUnidad;
  final String? fotoUrl;

  const Cotizacion({
    required this.id,
    required this.titulo,
    required this.adminId,
    required this.createdAt,
    this.cliente,
    this.monto,
    this.archivoUrl,
    this.numeroCotizacion,
    this.fechaCotizacion,
    this.direccionEntrega,
    this.direccionLat,
    this.direccionLng,
    this.descripcion,
    this.unidades,
    this.precioUnidad,
    this.fotoUrl,
  });

  factory Cotizacion.fromMap(Map<String, dynamic> map) {
    return Cotizacion(
      id: map['id'] as String,
      titulo: map['titulo'] as String,
      cliente: map['cliente'] as String?,
      monto: map['monto'] as num?,
      archivoUrl: map['archivo_url'] as String?,
      adminId: map['admin_id'] as String,
      createdAt: DateTime.parse(map['created_at'] as String),
      numeroCotizacion: map['numero_cotizacion'] as String?,
      fechaCotizacion: map['fecha_cotizacion'] != null
          ? DateTime.parse(map['fecha_cotizacion'] as String)
          : null,
      direccionEntrega: map['direccion_entrega'] as String?,
      direccionLat: (map['direccion_lat'] as num?)?.toDouble(),
      direccionLng: (map['direccion_lng'] as num?)?.toDouble(),
      descripcion: map['descripcion'] as String?,
      unidades: map['unidades'] as num?,
      precioUnidad: map['precio_unidad'] as num?,
      fotoUrl: map['foto_url'] as String?,
    );
  }
}
