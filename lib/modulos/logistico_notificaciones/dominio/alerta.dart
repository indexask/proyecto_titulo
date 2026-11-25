/// Tipos de alerta del motor de notificaciones (RF-17, RF-18).
enum TipoAlerta {
  preventiva('preventiva', 'Preventiva (3 días)'),
  diaCero('dia_cero', 'Día Cero');

  final String codigo;
  final String etiqueta;

  const TipoAlerta(this.codigo, this.etiqueta);

  static TipoAlerta desdeCodigo(String? codigo) =>
      values.firstWhere((t) => t.codigo == codigo, orElse: () => preventiva);
}

/// Alerta emitida (RF-20).
class Alerta {
  final String id;
  final String ordenId;
  final TipoAlerta tipo;
  final DateTime fechaEmision;
  final String cliente;
  final String? numeroOc;
  final DateTime fechaComprometida;

  const Alerta({
    required this.id,
    required this.ordenId,
    required this.tipo,
    required this.fechaEmision,
    required this.cliente,
    required this.fechaComprometida,
    this.numeroOc,
  });

  /// Acepta tanto la vista del Chofer (columnas planas) como la consulta del
  /// Administrador (orden_compra embebida).
  factory Alerta.fromMap(Map<String, dynamic> map) {
    final orden = (map['orden_compra'] as Map<String, dynamic>?) ?? map;
    return Alerta(
      id: map['id'] as String,
      ordenId: map['orden_id'] as String,
      tipo: TipoAlerta.desdeCodigo(map['tipo'] as String?),
      fechaEmision: DateTime.parse(map['fecha_emision'] as String),
      cliente: orden['cliente'] as String,
      numeroOc: orden['numero_oc'] as String?,
      fechaComprometida: DateTime.parse(orden['fecha_comprometida'] as String),
    );
  }
}
