import '../../logistico_notificaciones/dominio/estado_despacho.dart';

/// Parada de una ruta lista para dibujarse en el mapa. No contiene datos
/// financieros, por lo que sirve para ambas vistas.
class ParadaRuta {
  final int orden;
  final String despachoId;
  final String cliente;
  final String direccion;
  final double? lat;
  final double? lng;
  final EstadoDespacho estado;

  const ParadaRuta({
    required this.orden,
    required this.despachoId,
    required this.cliente,
    required this.direccion,
    required this.lat,
    required this.lng,
    required this.estado,
  });
}

/// Datos de la ruta comunes a Administrador y Chofer (RF-23).
class Ruta {
  final String id;
  final DateTime fecha;
  final String origenDireccion;
  final double origenLat;
  final double origenLng;
  final num? distanciaKm;
  final int? duracionMin;
  final String? polilinea;
  final List<ParadaRuta> paradas;

  const Ruta({
    required this.id,
    required this.fecha,
    required this.origenDireccion,
    required this.origenLat,
    required this.origenLng,
    required this.paradas,
    this.distanciaKm,
    this.duracionMin,
    this.polilinea,
  });
}

/// Vista completa del Administrador: agrega costos y ahorro (RF-24).
class RutaAdmin extends Ruta {
  final String? choferId;
  final String? choferNombre;
  final bool usaPeajes;
  final num? costoSinOptimizar;
  final num? costoOptimizada;
  final num? ahorro;

  const RutaAdmin({
    required super.id,
    required super.fecha,
    required super.origenDireccion,
    required super.origenLat,
    required super.origenLng,
    required super.paradas,
    super.distanciaKm,
    super.duracionMin,
    super.polilinea,
    this.choferId,
    this.choferNombre,
    this.usaPeajes = false,
    this.costoSinOptimizar,
    this.costoOptimizada,
    this.ahorro,
  });

  factory RutaAdmin.fromMap(Map<String, dynamic> map) {
    final paradas = ((map['ruta_parada'] as List?) ?? const []).map((p) {
      final despacho = p['despacho'] as Map<String, dynamic>;
      final orden = despacho['orden_compra'] as Map<String, dynamic>;
      return ParadaRuta(
        orden: p['orden'] as int,
        despachoId: despacho['id'] as String,
        cliente: orden['cliente'] as String,
        direccion: orden['direccion_entrega'] as String,
        lat: (orden['direccion_lat'] as num?)?.toDouble(),
        lng: (orden['direccion_lng'] as num?)?.toDouble(),
        estado: EstadoDespacho.desdeCodigo(despacho['estado'] as String?),
      );
    }).toList()
      ..sort((a, b) => a.orden.compareTo(b.orden));

    return RutaAdmin(
      id: map['id'] as String,
      fecha: DateTime.parse(map['fecha'] as String),
      origenDireccion: map['origen_direccion'] as String,
      origenLat: (map['origen_lat'] as num).toDouble(),
      origenLng: (map['origen_lng'] as num).toDouble(),
      distanciaKm: map['distancia_km'] as num?,
      duracionMin: map['duracion_min'] as int?,
      polilinea: map['polilinea'] as String?,
      paradas: paradas,
      choferId: map['chofer_id'] as String?,
      choferNombre: (map['chofer'] as Map<String, dynamic>?)?['nombre'] as String?,
      usaPeajes: map['usa_peajes'] as bool? ?? false,
      costoSinOptimizar: map['costo_ruta_sin_optimizar'] as num?,
      costoOptimizada: map['costo_ruta_optimizada'] as num?,
      ahorro: map['ahorro'] as num?,
    );
  }
}

/// Fila de la vista v_ruta_chofer: solo el orden de las paradas; los datos
/// de cada parada se completan con los despachos del Chofer.
class RutaChoferFila {
  final Map<String, dynamic> datos;

  const RutaChoferFila(this.datos);

  String get id => datos['id'] as String;
  DateTime get fecha => DateTime.parse(datos['fecha'] as String);

  List<({String despachoId, int orden})> get paradas =>
      ((datos['paradas'] as List?) ?? const [])
          .map((p) => (despachoId: p['despacho_id'] as String, orden: p['orden'] as int))
          .toList();
}
