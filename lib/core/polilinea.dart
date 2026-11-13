/// Decodifica una polilínea codificada de Google (Encoded Polyline Algorithm)
/// en una lista de coordenadas (lat, lng). La devuelve la Routes API.
List<(double, double)> decodificarPolilinea(String codificada) {
  final puntos = <(double, double)>[];
  var indice = 0;
  var lat = 0;
  var lng = 0;

  // Ojo: en web (JavaScript) los operadores de bits de Dart trabajan como
  // enteros SIN signo de 32 bits; `~x` devuelve 4294967295 - x en vez de un
  // número negativo. Por eso se arma el valor con multiplicaciones/sumas y el
  // signo se aplica aritméticamente (no con `~`).
  int siguienteValor() {
    var resultado = 0;
    var factor = 1;
    int byte;
    do {
      byte = codificada.codeUnitAt(indice++) - 63;
      resultado += (byte & 0x1f) * factor;
      factor *= 32;
    } while (byte >= 0x20 && indice < codificada.length);
    // Zigzag: los impares son negativos. ~(r >> 1) == -(r ~/ 2) - 1.
    return resultado.isOdd ? -(resultado ~/ 2) - 1 : resultado ~/ 2;
  }

  while (indice < codificada.length) {
    lat += siguienteValor();
    if (indice >= codificada.length) break;
    lng += siguienteValor();
    puntos.add((lat / 1e5, lng / 1e5));
  }
  return puntos;
}
