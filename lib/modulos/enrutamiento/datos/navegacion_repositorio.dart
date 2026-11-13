import 'package:url_launcher/url_launcher.dart';

/// Navegación paso a paso hacia una parada con Google Maps (enlaces "Maps
/// URLs": sin costo y sin clave). En Android/iOS abre la app Google Maps;
/// en el navegador, una pestaña nueva. No modifica la ruta: el Chofer solo
/// la sigue (RF-23).
class NavegacionRepositorio {
  /// URL de indicaciones en auto desde la ubicación actual hasta el destino.
  static Uri urlNavegacion(double lat, double lng) => Uri.https('www.google.com', '/maps/dir/', {
        'api': '1',
        'destination': '$lat,$lng',
        'travelmode': 'driving',
        'dir_action': 'navigate',
      });

  Future<bool> navegarA(double lat, double lng) =>
      launchUrl(urlNavegacion(lat, lng), mode: LaunchMode.externalApplication);
}
