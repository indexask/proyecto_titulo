import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../core/mapas/mapas_disponibles.dart';
import '../../../core/polilinea.dart';
import '../../logistico_notificaciones/dominio/estado_despacho.dart';
import '../../logistico_notificaciones/presentacion/widgets_despacho.dart';
import '../datos/ubicacion_repositorio.dart';
import '../dominio/ruta.dart';

/// Mapa geolocalizado de la ruta optimizada + lista de paradas en orden
/// (RF-23). Solo visualización: el Chofer no puede editar la ruta.
/// No muestra datos financieros; el panel del Administrador agrega los
/// costos con [encabezado].
///
/// Con [ubicacionEnVivo], muestra la posición del Chofer en tiempo real, la
/// próxima parada y la distancia hasta ella.
class VistaRuta extends StatefulWidget {
  final Ruta ruta;
  final Widget? encabezado;
  final void Function(ParadaRuta parada)? onParadaTap;
  final bool ubicacionEnVivo;

  const VistaRuta({
    super.key,
    required this.ruta,
    this.encabezado,
    this.onParadaTap,
    this.ubicacionEnVivo = false,
  });

  @override
  State<VistaRuta> createState() => _VistaRutaState();
}

class _VistaRutaState extends State<VistaRuta> {
  final _ubicacion = UbicacionRepositorio();
  GoogleMapController? _mapa;
  StreamSubscription<Position>? _suscripcion;
  Position? _posicion;
  EstadoUbicacion? _estado;
  bool _seguir = false;

  Ruta get ruta => widget.ruta;

  @override
  void initState() {
    super.initState();
    if (widget.ubicacionEnVivo) _activarUbicacion();
  }

  @override
  void dispose() {
    _suscripcion?.cancel();
    super.dispose();
  }

  Future<void> _activarUbicacion() async {
    final estado = await _ubicacion.solicitarPermiso();
    if (!mounted) return;
    setState(() => _estado = estado);
    if (estado != EstadoUbicacion.activa) return;
    await _suscripcion?.cancel();
    _suscripcion = _ubicacion.posiciones().listen((p) {
      if (!mounted) return;
      setState(() => _posicion = p);
      if (_seguir) _mapa?.animateCamera(CameraUpdate.newLatLng(LatLng(p.latitude, p.longitude)));
    }, onError: (_) {
      if (mounted) setState(() => _estado = EstadoUbicacion.gpsApagado);
    });
  }

  void _centrarEnMi() {
    final p = _posicion;
    if (p == null) return;
    setState(() => _seguir = true);
    _mapa?.animateCamera(CameraUpdate.newLatLngZoom(LatLng(p.latitude, p.longitude), 15));
  }

  @override
  Widget build(BuildContext context) {
    final origen = LatLng(ruta.origenLat, ruta.origenLng);
    final paradasConUbicacion = ruta.paradas.where((p) => p.lat != null && p.lng != null).toList();
    final yo = _posicion == null ? null : LatLng(_posicion!.latitude, _posicion!.longitude);

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
          icon: BitmapDescriptor.defaultMarkerWithHue(switch (p.estado) {
            EstadoDespacho.entregado => BitmapDescriptor.hueAzure,
            EstadoDespacho.enRuta => BitmapDescriptor.hueOrange,
            EstadoDespacho.pendiente => BitmapDescriptor.hueRed,
          }),
          infoWindow: InfoWindow(title: '${p.orden + 1}. ${p.cliente}', snippet: p.direccion),
        ),
      if (yo != null)
        Marker(
          markerId: const MarkerId('yo'),
          position: yo,
          zIndexInt: 10,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueViolet),
          infoWindow: const InfoWindow(title: 'Tu ubicación'),
        ),
    };

    final trazado = (ruta.polilinea?.isNotEmpty ?? false)
        ? decodificarPolilinea(ruta.polilinea!).map((c) => LatLng(c.$1, c.$2)).toList()
        : [origen, ...paradasConUbicacion.map((p) => LatLng(p.lat!, p.lng!)), origen];

    final todos = [origen, ...paradasConUbicacion.map((p) => LatLng(p.lat!, p.lng!)), ...trazado];
    final colores = Theme.of(context).colorScheme;

    return Column(
      children: [
        ?widget.encabezado,
        if (widget.ubicacionEnVivo) _panelUbicacion(context),
        Expanded(
          flex: 3,
          child: !mapasDisponibles
              ? const _MapaNoDisponible()
              : Stack(
            children: [
              GoogleMap(
                initialCameraPosition: CameraPosition(target: origen, zoom: 11),
                markers: marcadores,
                circles: {
                  if (yo != null && _posicion!.accuracy > 0)
                    Circle(
                      circleId: const CircleId('precision'),
                      center: yo,
                      radius: _posicion!.accuracy,
                      fillColor: colores.primary.withValues(alpha: 0.12),
                      strokeColor: colores.primary.withValues(alpha: 0.4),
                      strokeWidth: 1,
                    ),
                },
                polylines: {
                  Polyline(
                    polylineId: const PolylineId('ruta'),
                    points: trazado,
                    color: colores.primary,
                    width: 5,
                  ),
                },
                myLocationButtonEnabled: false,
                // Si el Chofer mueve el mapa con el dedo, deja de seguirlo.
                onCameraMoveStarted: () {
                  if (_seguir) setState(() => _seguir = false);
                },
                onMapCreated: (controlador) async {
                  _mapa = controlador;
                  await Future<void>.delayed(const Duration(milliseconds: 300));
                  try {
                    await controlador.animateCamera(CameraUpdate.newLatLngBounds(_limites(todos), 48));
                  } catch (_) {
                    // El mapa aún no tiene tamaño; se mantiene la cámara inicial.
                  }
                },
              ),
              if (widget.ubicacionEnVivo && yo != null)
                Positioned(
                  right: 12,
                  bottom: 12,
                  child: FloatingActionButton.small(
                    heroTag: 'centrar-en-mi',
                    tooltip: _seguir ? 'Siguiendo tu ubicación' : 'Centrar en mi ubicación',
                    backgroundColor: _seguir ? colores.primary : null,
                    foregroundColor: _seguir ? colores.onPrimary : null,
                    onPressed: _centrarEnMi,
                    child: const Icon(Icons.my_location),
                  ),
                ),
            ],
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
                  onTap: () {
                    if (p.lat != null && p.lng != null) {
                      setState(() => _seguir = false);
                      _mapa?.animateCamera(CameraUpdate.newLatLngZoom(LatLng(p.lat!, p.lng!), 15));
                    }
                    widget.onParadaTap?.call(p);
                  },
                ),
            ],
          ),
        ),
      ],
    );
  }

  /// Próxima parada y distancia, o aviso si la ubicación no está disponible.
  Widget _panelUbicacion(BuildContext context) {
    final colores = Theme.of(context).colorScheme;
    final proxima = ruta.proximaParada;

    if (_estado != null && _estado != EstadoUbicacion.activa) {
      final (texto, accion, onTap) = switch (_estado!) {
        EstadoUbicacion.gpsApagado => ('Activa el GPS para verte en el mapa', 'Reintentar', _activarUbicacion),
        EstadoUbicacion.permisoBloqueado => (
            'Permite el acceso a la ubicación en los ajustes',
            'Ajustes',
            () async {
              await _ubicacion.abrirAjustes();
            }
          ),
        _ => ('Permite el acceso a tu ubicación para verte en el mapa', 'Permitir', _activarUbicacion),
      };
      return Material(
        color: colores.errorContainer,
        child: ListTile(
          dense: true,
          leading: const Icon(Icons.location_off),
          title: Text(texto),
          trailing: TextButton(onPressed: onTap, child: Text(accion)),
        ),
      );
    }

    String? distancia;
    if (_posicion != null && proxima?.lat != null && proxima?.lng != null) {
      final m = _ubicacion.distanciaMetros(_posicion!.latitude, _posicion!.longitude, proxima!.lat!, proxima.lng!);
      distancia = m < 1000 ? '${m.round()} m' : '${(m / 1000).toStringAsFixed(1)} km';
    }

    return Material(
      color: colores.primaryContainer,
      child: ListTile(
        dense: true,
        leading: Icon(proxima == null ? Icons.flag : Icons.navigation),
        title: Text(proxima == null
            ? 'Todas las entregas de esta ruta están completas'
            : 'Próxima parada: ${proxima.orden + 1}. ${proxima.cliente}'),
        subtitle: proxima == null
            ? null
            : Text(distancia == null
                ? (_posicion == null ? 'Obteniendo tu ubicación…' : proxima.direccion)
                : 'A $distancia en línea recta · ${proxima.direccion}'),
      ),
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

/// Reemplazo del mapa cuando la Maps JavaScript API no está cargada (web
/// sin clave): la ruta y las paradas igual se muestran en la lista.
class _MapaNoDisponible extends StatelessWidget {
  const _MapaNoDisponible();

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return ColoredBox(
      color: tema.colorScheme.surfaceContainerHighest,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.map_outlined, size: 48, color: tema.colorScheme.outline),
              const SizedBox(height: 8),
              Text('Mapa no disponible', style: tema.textTheme.titleMedium),
              const SizedBox(height: 4),
              const Text(
                'Falta la clave de Google Maps JavaScript API para el panel web '
                '(web/maps_config.js). La ruta y sus paradas se muestran abajo.',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
