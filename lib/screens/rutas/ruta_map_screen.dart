import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:intl/intl.dart';

import '../../models/ruta.dart';
import '../../providers/rutas_provider.dart';
import '../../widgets/async_view.dart';

const _santiago = LatLng(-33.4489, -70.6693);

class RutaMapScreen extends ConsumerWidget {
  final String rutaId;

  const RutaMapScreen({super.key, required this.rutaId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rutaAsync = ref.watch(rutaDetailProvider(rutaId));

    return Scaffold(
      appBar: AppBar(title: Text(rutaAsync.value?.nombre ?? 'Ruta')),
      body: AsyncStateView(
        loading: rutaAsync.isLoading,
        error: rutaAsync.error,
        onRetry: () => ref.invalidate(rutaDetailProvider(rutaId)),
        child: Builder(builder: (_) {
          final ruta = rutaAsync.value;
          if (ruta == null) return const SizedBox.shrink();
          return _MapBody(ruta: ruta);
        }),
      ),
    );
  }
}

class _MapBody extends ConsumerWidget {
  final Ruta ruta;

  const _MapBody({required this.ruta});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currency = NumberFormat.currency(locale: 'es_CL', symbol: '\$');
    final tieneOrigen = ruta.origenLat != null && ruta.origenLng != null;

    final markers = <Marker>{
      if (tieneOrigen)
        Marker(
          markerId: const MarkerId('origen'),
          position: LatLng(ruta.origenLat!, ruta.origenLng!),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
          infoWindow: InfoWindow(
            title: 'Punto de partida',
            snippet: ruta.origenDireccion,
          ),
        ),
      for (var i = 0; i < ruta.puntos.length; i++)
        Marker(
          markerId: MarkerId(ruta.puntos[i].id),
          position: LatLng(ruta.puntos[i].lat, ruta.puntos[i].lng),
          infoWindow: InfoWindow(
            title: '${i + 1}. ${ruta.puntos[i].cotizacion?.cliente ?? ruta.puntos[i].direccion}',
            snippet: ruta.puntos[i].cotizacion != null
                ? '${ruta.puntos[i].cotizacion!.descripcion ?? ''} · '
                    '${ruta.puntos[i].cotizacion!.monto != null ? currency.format(ruta.puntos[i].cotizacion!.monto) : ''}'
                : ruta.puntos[i].direccion,
          ),
        ),
    };

    final recorrido = <LatLng>[
      if (tieneOrigen) LatLng(ruta.origenLat!, ruta.origenLng!),
      ...ruta.puntos.map((p) => LatLng(p.lat, p.lng)),
      if (tieneOrigen) LatLng(ruta.origenLat!, ruta.origenLng!),
    ];

    final polylines = recorrido.length > 1
        ? {
            Polyline(
              polylineId: const PolylineId('recorrido'),
              points: recorrido,
              color: Colors.blue,
              width: 4,
            ),
          }
        : <Polyline>{};

    final centro = tieneOrigen
        ? LatLng(ruta.origenLat!, ruta.origenLng!)
        : (ruta.puntos.isNotEmpty
            ? LatLng(ruta.puntos.first.lat, ruta.puntos.first.lng)
            : _santiago);

    return Column(
      children: [
        if (ruta.distanciaKm != null || ruta.duracionMin != null)
          Container(
            width: double.infinity,
            color: Theme.of(context).colorScheme.secondaryContainer,
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Text(
              '${ruta.distanciaKm ?? '—'} km · ${ruta.duracionMin ?? '—'} min (ruta optimizada)',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        Expanded(
          child: GoogleMap(
            initialCameraPosition: CameraPosition(target: centro, zoom: 12),
            markers: markers,
            polylines: polylines,
          ),
        ),
        _EstadoBar(ruta: ruta),
      ],
    );
  }
}

class _EstadoBar extends ConsumerWidget {
  final Ruta ruta;

  const _EstadoBar({required this.ruta});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _botonEstado(ref, RutaEstado.enCurso, 'En curso'),
            _botonEstado(ref, RutaEstado.completada, 'Completada'),
          ],
        ),
      ),
    );
  }

  Widget _botonEstado(WidgetRef ref, RutaEstado estado, String label) {
    final activo = ruta.estado == estado;
    return FilledButton.tonal(
      onPressed: activo
          ? null
          : () async {
              await ref.read(rutasServiceProvider).actualizarEstado(ruta.id, estado);
              ref.invalidate(rutaDetailProvider(ruta.id));
              ref.invalidate(misRutasProvider);
            },
      child: Text(label),
    );
  }
}
