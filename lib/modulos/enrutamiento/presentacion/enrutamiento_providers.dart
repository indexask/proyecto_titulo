import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../administracion_seguridad/presentacion/auth_providers.dart';
import '../../logistico_notificaciones/presentacion/logistico_providers.dart';
import '../datos/geocodificacion_repositorio.dart';
import '../datos/rutas_repositorio.dart';
import '../dominio/ruta.dart';

final rutasRepositorioProvider =
    Provider<RutasRepositorio>((ref) => RutasRepositorio(ref.watch(almacenLocalProvider)));

final geocodificacionRepositorioProvider =
    Provider<GeocodificacionRepositorio>((ref) => GeocodificacionRepositorio());

// --- Administrador ----------------------------------------------------------

final rutasAdminProvider = FutureProvider.autoDispose<List<RutaAdmin>>((ref) {
  return ref.watch(rutasRepositorioProvider).listar();
});

final rutaAdminProvider = FutureProvider.autoDispose.family<RutaAdmin, String>((ref, id) {
  return ref.watch(rutasRepositorioProvider).obtener(id);
});

// --- Chofer -----------------------------------------------------------------

/// Rutas del Chofer: el orden de paradas viene de v_ruta_chofer y los datos
/// de cada parada, de sus despachos (ya disponibles sin conexión).
final rutasChoferProvider = FutureProvider.autoDispose<List<Ruta>>((ref) async {
  final usuarioId = ref.watch(usuarioIdProvider);
  if (usuarioId == null) return [];
  final filas = await ref.watch(rutasRepositorioProvider).listarDelChofer(usuarioId);
  final despachos = (await ref.watch(despachosChoferProvider.future)).despachos;
  final porId = {for (final d in despachos) d.despachoId: d};

  return filas.map((fila) {
    final datos = fila.datos;
    final paradas = <ParadaRuta>[
      for (final p in fila.paradas)
        if (porId[p.despachoId] case final d?)
          ParadaRuta(
            orden: p.orden,
            despachoId: d.despachoId,
            cliente: d.cliente,
            direccion: d.direccionEntrega,
            lat: d.direccionLat,
            lng: d.direccionLng,
            estado: d.estado,
          ),
    ]..sort((a, b) => a.orden.compareTo(b.orden));

    return Ruta(
      id: fila.id,
      fecha: fila.fecha,
      origenDireccion: datos['origen_direccion'] as String,
      origenLat: (datos['origen_lat'] as num).toDouble(),
      origenLng: (datos['origen_lng'] as num).toDouble(),
      distanciaKm: datos['distancia_km'] as num?,
      duracionMin: datos['duracion_min'] as int?,
      polilinea: datos['polilinea'] as String?,
      usaPeajes: datos['usa_peajes'] as bool? ?? false,
      paradas: paradas,
    );
  }).toList();
});
