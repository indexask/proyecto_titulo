import 'cotizacion.dart';

class PuntoRuta {
  final String id;
  final String rutaId;
  final int orden;
  final String direccion;
  final double lat;
  final double lng;
  final String? notas;
  final String? cotizacionId;
  final Cotizacion? cotizacion;

  const PuntoRuta({
    required this.id,
    required this.rutaId,
    required this.orden,
    required this.direccion,
    required this.lat,
    required this.lng,
    this.notas,
    this.cotizacionId,
    this.cotizacion,
  });

  factory PuntoRuta.fromMap(Map<String, dynamic> map) {
    final cotizacionData = map['cotizaciones'] as Map<String, dynamic>?;
    return PuntoRuta(
      id: map['id'] as String,
      rutaId: map['ruta_id'] as String,
      orden: map['orden'] as int,
      direccion: map['direccion'] as String,
      lat: (map['lat'] as num).toDouble(),
      lng: (map['lng'] as num).toDouble(),
      notas: map['notas'] as String?,
      cotizacionId: map['cotizacion_id'] as String?,
      cotizacion:
          cotizacionData != null ? Cotizacion.fromMap(cotizacionData) : null,
    );
  }
}
