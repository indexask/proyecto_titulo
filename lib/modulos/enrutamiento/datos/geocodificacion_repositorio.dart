import '../../../core/supabase_client.dart';

typedef DireccionGeocodificada = ({String direccion, double lat, double lng});

/// Geocodificación de direcciones con Google Places API, a través de la Edge
/// Function `geocodificar` (la clave de Google queda en el servidor).
class GeocodificacionRepositorio {
  Future<DireccionGeocodificada> geocodificar(String direccion) async {
    final res = await supabase.functions.invoke('geocodificar', body: {'direccion': direccion});
    final data = res.data as Map<String, dynamic>;
    return (
      direccion: data['direccion'] as String,
      lat: (data['lat'] as num).toDouble(),
      lng: (data['lng'] as num).toDouble(),
    );
  }
}
