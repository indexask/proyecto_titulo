import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../core/polilinea.dart';
import '../../logistico_notificaciones/presentacion/widgets_despacho.dart';
import '../dominio/ruta.dart';

/// Mapa geolocalizado de la ruta optimizada + lista de paradas en orden
/// (RF-23). Solo visualización: el Chofer no puede editar la ruta.
/// No muestra datos financieros; el panel del Administrador agrega los
/// costos con [encabezado].
class VistaRuta extends StatelessWidget {
  final Ruta ruta;
  final Widget? encabezado;
  final void Function(ParadaRuta parada)? onParadaTap;

  const VistaRuta({super.key, required this.ruta, this.encabezado, this.onParadaTap});

  @override
  Widget build(BuildContext context) {
    final origen = LatLng(ruta.origenLat, ruta.origenLng);
    final paradasConUbicacion = ruta.paradas.where((p) => p.lat != null && p.lng != null).toList();

    final marcadores = <Marker>{
      Marker(
        markerId: const MarkerId('origen'),
        position: origen,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
        infoWindow: InfoWindow(title: 'Bodega (salida)', snippet: ruta.origenDireccion),
      ),
      for (final p in paradasConUbicacion)
        Marker(
          markerId: MarkerId(p.despachoId),
          position: LatLng(p.lat!, p.lng!),
          icon: BitmapDescriptor.defaultMarkerWithHue(switch (p.estado.codigo) {
            'entregado' => BitmapDescriptor.hueAzure,
            'en_ruta' => BitmapDescriptor.hueOrange,
            _ => BitmapDescriptor.hueRed,
          }),
          infoWindow: InfoWindow(title: '${p.orden + 1}. ${p.cliente}', snippet: p.direccion),
        ),
    };

    final trazado = (ruta.polilinea?.isNotEmpty ?? false)
        ? decodificarPolilinea(ruta.polilinea!).map((c) => LatLng(c.$1, c.$2)).toList()
        : [origen, ...paradasConUbicacion.map((p) => LatLng(p.lat!, p.lng!)), origen];

    final todos = [origen, ...marcadores.map((m) => m.position), ...trazado];

    return Column(
      children: [
        ?encabezado,
        Expanded(
          flex: 3,
          child: GoogleMap(
            initialCameraPosition: CameraPosition(target: origen, zoom: 11),
            markers: marcadores,
            polylines: {
              Polyline(
                polylineId: const PolylineId('ruta'),
                points: trazado,
                color: Theme.of(context).colorScheme.primary,
                width: 5,
              ),
            },
            onMapCreated: (controlador) async {
              await Future<void>.delayed(const Duration(milliseconds: 300));
              try {
                await controlador.animateCamera(CameraUpdate.newLatLngBounds(_limites(todos), 48));
              } catch (_) {
                // El mapa aún no tiene tamaño; se mantiene la cámara inicial.
              }
            },
          ),
        ),
        Expanded(
          flex: 2,
          child: ListView(
            padding: const EdgeInsets.symmetric(vertical: 4),
            children: [
              ListTile(
                dense: true,
                leading: const CircleAvatar(child: Icon(Icons.warehouse, size: 18)),
                title: const Text('Salida desde bodega'),
                subtitle: Text(ruta.origenDireccion),
              ),
              for (final p in ruta.paradas)
                ListTile(
                  dense: true,
                  leading: CircleAvatar(child: Text('${p.orden + 1}')),
                  title: Text(p.cliente),
                  subtitle: Text(p.direccion),
                  trailing: ChipEstado(p.estado),
                  onTap: onParadaTap == null ? null : () => onParadaTap!(p),
                ),
            ],
          ),
        ),
      ],
    );
  }

  static LatLngBounds _limites(List<LatLng> puntos) {
    var sur = puntos.first.latitude, norte = sur;
    var oeste = puntos.first.longitude, este = oeste;
    for (final p in puntos) {
      if (p.latitude < sur) sur = p.latitude;
      if (p.latitude > norte) norte = p.latitude;
      if (p.longitude < oeste) oeste = p.longitude;
      if (p.longitude > este) este = p.longitude;
    }
    return LatLngBounds(southwest: LatLng(sur, oeste), northeast: LatLng(norte, este));
  }
}
