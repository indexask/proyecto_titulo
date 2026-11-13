import 'package:url_launcher/url_launcher.dart';

/// Punto de navegación: se usa la dirección exacta de la orden; las
/// coordenadas solo si no hay dirección.
class PuntoNavegacion {
  final String direccion;
  final double? lat;
  final double? lng;

  const PuntoNavegacion({required this.direccion, this.lat, this.lng});

  /// Texto para Maps URLs. Con coordenadas, Google Maps rotula el destino con
  /// el lugar más cercano (p. ej. "Universidad de Chile" en vez de la calle),
  /// por eso se prefiere la dirección. "|" separa waypoints y se quita.
  String? get consulta {
    final d = direccion.replaceAll('|', ' ').trim();
    if (d.isNotEmpty) return d;
    if (lat != null && lng != null) return '$lat,$lng';
    return null;
  }
}

/// Navegación con Google Maps (enlaces "Maps URLs": sin costo y sin clave).
/// En Android/iOS abre la app Google Maps; en el navegador, una pestaña.
/// No modifica la ruta: el Chofer solo la sigue (RF-23).
class NavegacionRepositorio {
  /// Google Maps acepta hasta 9 paradas intermedias (en el navegador del
  /// teléfono, solo 3).
  static const maxParadasIntermedias = 9;

  /// URL de indicaciones en auto desde la ubicación actual, pasando por
  /// [paradas] en orden, hasta [destino]. Si hay más paradas de las que
  /// admite Google Maps, el recorrido termina en la última que cabe.
  static Uri urlRuta(List<PuntoNavegacion> paradas, PuntoNavegacion destino) {
    final puntos = [...paradas, destino].map((p) => p.consulta).whereType<String>().toList();
    final tramo = puntos.take(maxParadasIntermedias + 1).toList();
    return Uri.https('www.google.com', '/maps/dir/', {
      'api': '1',
      'destination': tramo.last,
      if (tramo.length > 1) 'waypoints': tramo.sublist(0, tramo.length - 1).join('|'),
      'travelmode': 'driving',
      'dir_action': 'navigate',
    });
  }

  /// Cuántas paradas quedan fuera del enlace por el límite de Google Maps.
  static int paradasFuera(List<PuntoNavegacion> paradas) =>
      (paradas.length - maxParadasIntermedias - 1).clamp(0, paradas.length);

  Future<bool> navegarRuta(List<PuntoNavegacion> paradas, PuntoNavegacion destino) =>
      launchUrl(urlRuta(paradas, destino), mode: LaunchMode.externalApplication);
}
