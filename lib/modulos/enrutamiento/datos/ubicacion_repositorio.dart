import 'package:geolocator/geolocator.dart';

enum EstadoUbicacion { activa, sinPermiso, permisoBloqueado, gpsApagado }

/// Ubicación en tiempo real del Chofer (RF-23: ruta geolocalizada).
/// Solo se usa en su dispositivo; no se envía ni se guarda en el servidor.
class UbicacionRepositorio {
  Future<EstadoUbicacion> solicitarPermiso() async {
    if (!await Geolocator.isLocationServiceEnabled()) return EstadoUbicacion.gpsApagado;
    var permiso = await Geolocator.checkPermission();
    if (permiso == LocationPermission.denied) {
      permiso = await Geolocator.requestPermission();
    }
    return switch (permiso) {
      LocationPermission.whileInUse || LocationPermission.always => EstadoUbicacion.activa,
      LocationPermission.deniedForever => EstadoUbicacion.permisoBloqueado,
      _ => EstadoUbicacion.sinPermiso,
    };
  }

  /// Posiciones a medida que el Chofer se mueve (cada 10 m).
  Stream<Position> posiciones() => Geolocator.getPositionStream(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 10),
      );

  /// Distancia en línea recta, en metros.
  double distanciaMetros(double lat1, double lng1, double lat2, double lng2) =>
      Geolocator.distanceBetween(lat1, lng1, lat2, lng2);

  Future<bool> abrirAjustes() => Geolocator.openAppSettings();
}
