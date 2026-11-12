/// Decodifica una polilínea codificada de Google (Encoded Polyline Algorithm)
/// en una lista de coordenadas (lat, lng). La devuelve la Routes API.
List<(double, double)> decodificarPolilinea(String codificada) {
  final puntos = <(double, double)>[];
  var indice = 0;
  var lat = 0;
  var lng = 0;

  int siguienteValor() {
    var resultado = 0;
    var desplazamiento = 0;
    int byte;
    do {
      byte = codificada.codeUnitAt(indice++) - 63;
      resultado |= (byte & 0x1f) << desplazamiento;
      desplazamiento += 5;
    } while (byte >= 0x20 && indice < codificada.length);
    return (resultado & 1) != 0 ? ~(resultado >> 1) : (resultado >> 1);
  }

  while (indice < codificada.length) {
    lat += siguienteValor();
    if (indice >= codificada.length) break;
    lng += siguienteValor();
    puntos.add((lat / 1e5, lng / 1e5));
  }
  return puntos;
}
