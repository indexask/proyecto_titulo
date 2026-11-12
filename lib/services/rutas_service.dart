import '../core/supabase_client.dart';
import '../models/profile.dart';
import '../models/ruta.dart';

class RutasService {
  static const _select = '*, puntos_ruta(*, cotizaciones(*))';

  Future<List<Ruta>> listar() async {
    final data = await supabase
        .from('rutas')
        .select(_select)
        .order('created_at', ascending: false);
    return (data as List)
        .map((m) => Ruta.fromMap(m as Map<String, dynamic>))
        .toList();
  }

  Future<Ruta> obtener(String id) async {
    final data =
        await supabase.from('rutas').select(_select).eq('id', id).single();
    return Ruta.fromMap(data);
  }

  /// Crea una ruta a partir de varias cotizaciones: llama a la Edge
  /// Function `optimize-ruta` para obtener el orden de visita más eficiente
  /// (menos distancia/tiempo) y guarda la ruta + sus puntos ya ordenados.
  Future<Ruta> crearOptimizada({
    required List<Map<String, dynamic>> cotizaciones, // {id, direccion, lat, lng}
    required String nombre,
    String? choferId,
    required String origenDireccion,
    required double origenLat,
    required double origenLng,
    DateTime? fechaEntrega,
  }) async {
    final res = await supabase.functions.invoke(
      'optimize-ruta',
      body: {
        'origin': {'lat': origenLat, 'lng': origenLng},
        'waypoints': cotizaciones
            .map((c) => {
                  'lat': c['lat'],
                  'lng': c['lng'],
                  'cotizacionId': c['id'],
                })
            .toList(),
      },
    );
    if (res.status != 200) {
      throw Exception('No se pudo optimizar la ruta (${res.status}): ${res.data}');
    }
    final optimizado = res.data as Map<String, dynamic>;
    final ordenIds = (optimizado['order'] as List).cast<String>();

    final rutaData = await supabase
        .from('rutas')
        .insert({
          'nombre': nombre,
          'chofer_id': choferId,
          'fecha_entrega': (fechaEntrega ?? DateTime.now())
              .toIso8601String()
              .split('T')
              .first,
          'origen_direccion': origenDireccion,
          'origen_lat': origenLat,
          'origen_lng': origenLng,
          'distancia_km': optimizado['distanciaKm'],
          'duracion_min': optimizado['duracionMin'],
        })
        .select()
        .single();

    final rutaId = rutaData['id'] as String;
    final porId = {for (final c in cotizaciones) c['id'] as String: c};

    for (var i = 0; i < ordenIds.length; i++) {
      final c = porId[ordenIds[i]]!;
      await supabase.from('puntos_ruta').insert({
        'ruta_id': rutaId,
        'orden': i,
        'direccion': c['direccion'],
        'lat': c['lat'],
        'lng': c['lng'],
        'cotizacion_id': c['id'],
      });
    }

    return obtener(rutaId);
  }

  Future<void> actualizarEstado(String rutaId, RutaEstado estado) {
    return supabase
        .from('rutas')
        .update({'estado': estadoToString(estado)}).eq('id', rutaId);
  }

  Future<List<Profile>> listarChoferes() async {
    final data =
        await supabase.from('profiles').select().eq('role', 'chofer');
    return (data as List)
        .map((m) => Profile.fromMap(m as Map<String, dynamic>))
        .toList();
  }
}
