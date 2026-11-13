import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../core/mapas/mapas_disponibles.dart';
import '../../../core/polilinea.dart';
import '../../logistico_notificaciones/presentacion/widgets_despacho.dart';
import '../datos/ubicacion_repositorio.dart';
import '../dominio/ruta.dart';
import 'iconos_mapa.dart';

/// Qué muestra la cámara del mapa.
enum ModoCamara {
  /// Toda la ruta (bodega y paradas).
  rutaCompleta,

  /// El tramo actual: la ubicación del Chofer y la próxima parada. Se
  /// actualiza solo al moverse y al pasar a la siguiente parada.
  tramo,

  /// Centrado en el Chofer, siguiéndolo.
  seguirme,
}

/// Mapa geolocalizado de la ruta optimizada + lista de paradas en orden
/// (RF-23). Solo visualización: el Chofer no puede editar la ruta.
/// No muestra datos financieros; el panel del Administrador agrega los
/// costos con [encabezado].
///
/// Con [ubicacionEnVivo], muestra la posición del Chofer en tiempo real, la
/// próxima parada y la distancia hasta ella. Con [enRuta], la cámara enfoca
/// el tramo actual (ubicación → próxima parada).
class VistaRuta extends StatefulWidget {
  final Ruta ruta;
  final Widget? encabezado;
  final void Function(ParadaRuta parada)? onParadaTap;
  final bool ubicacionEnVivo;
  final bool enRuta;

  const VistaRuta({
    super.key,
    required this.ruta,
    this.encabezado,
    this.onParadaTap,
    this.ubicacionEnVivo = false,
    this.enRuta = false,
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
  IconosMapa? _iconos;
  late ModoCamara _modo = widget.enRuta ? ModoCamara.tramo : ModoCamara.rutaCompleta;

  // En web, Google Maps puede quedar gris tras cambiar de tamaño, al volver a
  // la pestaña o al actualizarse los datos. Se "refresca" en esos casos.
  Size? _tamanoMapa;
  Timer? _refresco;
  late final AppLifecycleListener _ciclo;

  Ruta get ruta => widget.ruta;
  LatLng get _origen => LatLng(ruta.origenLat, ruta.origenLng);
  LatLng? get _yo => _posicion == null ? null : LatLng(_posicion!.latitude, _posicion!.longitude);

  List<LatLng> get _trazado => (ruta.polilinea?.isNotEmpty ?? false)
      ? decodificarPolilinea(ruta.polilinea!).map((c) => LatLng(c.$1, c.$2)).toList()
      : [_origen, ..._puntosParadas, _origen];

  List<LatLng> get _puntosParadas => [
    for (final p in ruta.paradas)
      if (p.lat != null && p.lng != null) LatLng(p.lat!, p.lng!),
  ];

  @override
  void initState() {
    super.initState();
    _ciclo = AppLifecycleListener(onResume: _programarRefresco, onShow: _programarRefresco);
    _prepararIconos();
    if (widget.ubicacionEnVivo) _activarUbicacion();
  }

  /// Agrupa varios pedidos de refresco seguidos en uno solo.
  void _programarRefresco() {
    _refresco?.cancel();
    _refresco = Timer(const Duration(milliseconds: 350), _refrescarMapa);
  }

  /// Reaplica la cámara y la desplaza un píxel ida y vuelta: obliga a Google
  /// Maps a redibujar con el tamaño actual.
  Future<void> _refrescarMapa() async {
    final mapa = _mapa;
    if (!mounted || mapa == null) return;
    await _aplicarCamara();
    try {
      await mapa.moveCamera(CameraUpdate.scrollBy(1, 0));
      await mapa.moveCamera(CameraUpdate.scrollBy(-1, 0));
    } catch (_) {
      // Mapa sin tamaño todavía; el próximo cambio lo vuelve a intentar.
    }
  }

  @override
  void didUpdateWidget(VistaRuta anterior) {
    super.didUpdateWidget(anterior);
    final antes = anterior.ruta.paradas.map((p) => p.estado).toList();
    final ahora = ruta.paradas.map((p) => p.estado).toList();
    final cambioEstados =
        antes.length != ahora.length || [for (var i = 0; i < antes.length; i++) antes[i] != ahora[i]].any((x) => x);
    if (cambioEstados) _prepararIconos();

    // Al iniciar la ruta, o al pasar a la siguiente parada, se enfoca el tramo.
    if (widget.enRuta && !anterior.enRuta) _modo = ModoCamara.tramo;
    if (anterior.ruta.proximaParada?.despachoId != ruta.proximaParada?.despachoId && _modo == ModoCamara.tramo) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _aplicarCamara(animar: true));
    }
    // Cualquier cambio de datos: se asegura que el mapa quede dibujado.
    _programarRefresco();
  }

  @override
  void dispose() {
    _refresco?.cancel();
    _ciclo.dispose();
    _suscripcion?.cancel();
    super.dispose();
  }

  Future<void> _prepararIconos() async {
    final iconos = await IconosMapa.crear(ruta.paradas.map((p) => (numero: p.orden + 1, estado: p.estado)));
    if (mounted) setState(() => _iconos = iconos);
  }

  Future<void> _activarUbicacion() async {
    final estado = await _ubicacion.solicitarPermiso();
    if (!mounted) return;
    setState(() => _estado = estado);
    if (estado != EstadoUbicacion.activa) return;
    await _suscripcion?.cancel();
    var primera = true;
    _suscripcion = _ubicacion.posiciones().listen(
      (p) {
        if (!mounted) return;
        setState(() => _posicion = p);
        if (_modo != ModoCamara.rutaCompleta) _aplicarCamara(animar: !primera);
        primera = false;
      },
      onError: (_) {
        if (mounted) setState(() => _estado = EstadoUbicacion.gpsApagado);
      },
    );
  }

  /// Mueve la cámara según el modo actual.
  Future<void> _aplicarCamara({bool animar = false}) async {
    final mapa = _mapa;
    if (mapa == null) return;
    final yo = _yo;
    final proxima = ruta.proximaParada;

    CameraUpdate? destino;
    switch (_modo) {
      case ModoCamara.seguirme:
        if (yo != null) destino = CameraUpdate.newLatLngZoom(yo, 16);
      case ModoCamara.tramo:
        if (yo != null && proxima?.lat != null && proxima?.lng != null) {
          destino = CameraUpdate.newLatLngBounds(_limites([yo, LatLng(proxima!.lat!, proxima.lng!)]), 80);
        } else if (proxima?.lat != null) {
          destino = CameraUpdate.newLatLngZoom(LatLng(proxima!.lat!, proxima.lng!), 14);
        } else {
          destino = CameraUpdate.newLatLngBounds(_limites([_origen, ..._puntosParadas, ..._trazado]), 48);
        }
      case ModoCamara.rutaCompleta:
        destino = CameraUpdate.newLatLngBounds(_limites([_origen, ..._puntosParadas, ..._trazado, ?yo]), 48);
    }
    if (destino == null) return;
    try {
      animar ? await mapa.animateCamera(destino) : await mapa.moveCamera(destino);
    } catch (_) {
      // El mapa aún no tiene tamaño; el siguiente intento lo corrige.
    }
  }

  /// Al crear el mapa: en web, Google Maps a veces queda gris hasta que la
  /// cámara se mueve, así que se aplica la cámara varias veces y se hace un
  /// pequeño desplazamiento final para forzar el dibujo.
  Future<void> _alCrearMapa(GoogleMapController mapa) async {
    _mapa = mapa;
    for (final espera in const [300, 900, 2000]) {
      await Future<void>.delayed(Duration(milliseconds: espera));
      if (!mounted) return;
      await _aplicarCamara();
    }
    await _refrescarMapa();
  }

  void _cambiarModo(ModoCamara modo) {
    setState(() => _modo = modo);
    _aplicarCamara(animar: true);
  }

  @override
  Widget build(BuildContext context) {
    final colores = Theme.of(context).colorScheme;
    final yo = _yo;
    final iconos = _iconos;
    const centrado = Offset(0.5, 0.5);
    final anclaje = iconos == null ? const Offset(0.5, 1) : centrado;
    final proxima = ruta.proximaParada;

    final marcadores = <Marker>{
      Marker(
        markerId: const MarkerId('origen'),
        position: _origen,
        icon: iconos?.bodega ?? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
        anchor: anclaje,
        infoWindow: InfoWindow(title: 'Bodega (salida y regreso)', snippet: ruta.origenDireccion),
      ),
      for (final p in ruta.paradas)
        if (p.lat != null && p.lng != null)
          Marker(
            markerId: MarkerId(p.despachoId),
            position: LatLng(p.lat!, p.lng!),
            icon: iconos?.parada(p.orden + 1, p.estado) ?? BitmapDescriptor.defaultMarker,
            anchor: anclaje,
            zIndexInt: p.despachoId == proxima?.despachoId ? 5 : 1,
            infoWindow: InfoWindow(
              title: '${p.orden + 1}. ${p.cliente}',
              snippet: '${p.estado.etiqueta} · ${p.direccion}',
            ),
          ),
      if (yo != null)
        Marker(
          markerId: const MarkerId('yo'),
          position: yo,
          zIndexInt: 10,
          icon: iconos?.ubicacion ?? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
          anchor: anclaje,
          infoWindow: const InfoWindow(title: 'Tu ubicación'),
        ),
    };

    final lineas = <Polyline>{
      Polyline(polylineId: const PolylineId('ruta'), points: _trazado, color: colores.primary, width: 5),
      // En ruta: línea punteada de la ubicación actual a la próxima parada.
      if (widget.enRuta && yo != null && proxima?.lat != null && proxima?.lng != null)
        Polyline(
          polylineId: const PolylineId('tramo'),
          points: [yo, LatLng(proxima!.lat!, proxima.lng!)],
          color: Colors.orange.shade700,
          width: 4,
          patterns: [PatternItem.dash(20), PatternItem.gap(12)],
        ),
    };

    Widget botonModo(ModoCamara modo, IconData icono, String ayuda) {
      final activo = _modo == modo;
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: FloatingActionButton.small(
          heroTag: 'camara-${modo.name}',
          tooltip: ayuda,
          backgroundColor: activo ? colores.primary : null,
          foregroundColor: activo ? colores.onPrimary : null,
          onPressed: () => _cambiarModo(modo),
          child: Icon(icono),
        ),
      );
    }

    return Column(
      children: [
        ?widget.encabezado,
        if (widget.ubicacionEnVivo) _panelUbicacion(context),
        Expanded(
          flex: 3,
          child: !mapasDisponibles
              ? const _MapaNoDisponible()
              : LayoutBuilder(
                  builder: (context, restricciones) {
                    // Si el mapa cambia de tamaño (p. ej. una barra se acorta),
                    // se refresca para que no quede gris.
                    final tamano = restricciones.biggest;
                    if (_tamanoMapa != tamano) {
                      _tamanoMapa = tamano;
                      WidgetsBinding.instance.addPostFrameCallback((_) => _programarRefresco());
                    }
                    return Stack(
                      children: [
                        GoogleMap(
                          initialCameraPosition: CameraPosition(target: _origen, zoom: 11),
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
                          polylines: lineas,
                          myLocationButtonEnabled: false,
                          zoomControlsEnabled: false,
                          onMapCreated: _alCrearMapa,
                        ),
                        Positioned(
                          right: 12,
                          bottom: 12,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              botonModo(ModoCamara.rutaCompleta, Icons.zoom_out_map, 'Ver toda la ruta'),
                              if (widget.ubicacionEnVivo && yo != null) ...[
                                if (proxima != null)
                                  botonModo(ModoCamara.tramo, Icons.near_me, 'Ver tramo a la próxima parada'),
                                botonModo(ModoCamara.seguirme, Icons.my_location, 'Seguir mi ubicación'),
                              ],
                            ],
                          ),
                        ),
                      ],
                    );
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
                  selected: p.despachoId == proxima?.despachoId,
                  leading: CircleAvatar(
                    backgroundColor: IconosMapa.colorEstado(p.estado),
                    foregroundColor: Colors.white,
                    child: Text('${p.orden + 1}'),
                  ),
                  title: Text(p.cliente),
                  subtitle: Text(p.direccion),
                  trailing: ChipEstado(p.estado),
                  onTap: () => widget.onParadaTap?.call(p),
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
          },
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
        title: Text(
          proxima == null
              ? 'Todas las entregas de esta ruta están completas'
              : 'Próxima parada: ${proxima.orden + 1}. ${proxima.cliente}',
        ),
        subtitle: proxima == null
            ? null
            : Text(
                distancia == null
                    ? (_posicion == null ? 'Obteniendo tu ubicación…' : proxima.direccion)
                    : 'A $distancia en línea recta · ${proxima.direccion}',
              ),
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
