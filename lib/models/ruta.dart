import 'punto_ruta.dart';

enum RutaEstado { pendiente, enCurso, completada }

RutaEstado estadoFromString(String value) {
  switch (value) {
    case 'en_curso':
      return RutaEstado.enCurso;
    case 'completada':
      return RutaEstado.completada;
    default:
      return RutaEstado.pendiente;
  }
}

String estadoToString(RutaEstado estado) {
  switch (estado) {
    case RutaEstado.enCurso:
      return 'en_curso';
    case RutaEstado.completada:
      return 'completada';
    case RutaEstado.pendiente:
      return 'pendiente';
  }
}

class Ruta {
  final String id;
  final String? choferId;
  final String nombre;
  final RutaEstado estado;
  final DateTime createdAt;
  final DateTime fechaEntrega;
  final String? origenDireccion;
  final double? origenLat;
  final double? origenLng;
  final num? distanciaKm;
  final num? duracionMin;
  final List<PuntoRuta> puntos;

  const Ruta({
    required this.id,
    required this.nombre,
    required this.estado,
    required this.createdAt,
    required this.fechaEntrega,
    this.choferId,
    this.origenDireccion,
    this.origenLat,
    this.origenLng,
    this.distanciaKm,
    this.duracionMin,
    this.puntos = const [],
  });

  factory Ruta.fromMap(Map<String, dynamic> map) {
    final puntosData = map['puntos_ruta'] as List<dynamic>?;
    return Ruta(
      id: map['id'] as String,
      choferId: map['chofer_id'] as String?,
      nombre: map['nombre'] as String,
      estado: estadoFromString(map['estado'] as String? ?? 'pendiente'),
      createdAt: DateTime.parse(map['created_at'] as String),
      fechaEntrega: DateTime.parse(map['fecha_entrega'] as String),
      origenDireccion: map['origen_direccion'] as String?,
      origenLat: (map['origen_lat'] as num?)?.toDouble(),
      origenLng: (map['origen_lng'] as num?)?.toDouble(),
      distanciaKm: map['distancia_km'] as num?,
      duracionMin: map['duracion_min'] as num?,
      puntos: (puntosData ?? [])
          .map((p) => PuntoRuta.fromMap(p as Map<String, dynamic>))
          .toList()
        ..sort((a, b) => a.orden.compareTo(b.orden)),
    );
  }
}
