// Pruebas del decodificador de polilíneas. Ejecutar también en navegador:
//   flutter test --platform chrome test/polilinea_test.dart
// (en web los operadores de bits de Dart son de 32 bits sin signo; el error
// original solo aparecía ahí).
import 'package:flutter_test/flutter_test.dart';
import 'package:gygtrack/core/polilinea.dart';

void main() {
  test('ejemplo de la documentación de Google', () {
    expect(decodificarPolilinea('_p~iF~ps|U_ulLnnqC_mqNvxq`@'),
        [(38.5, -120.2), (40.7, -120.95), (43.252, -126.453)]);
  });

  test('coordenadas de Santiago (latitud y longitud negativas)', () {
    // Codificación estándar de: Maipú → Providencia → La Reina.
    final puntos = [(-33.5100, -70.7580), (-33.4378, -70.6155), (-33.4460, -70.5420)];
    final decodificados = decodificarPolilinea(codificarPolilinea(puntos));
    expect(decodificados.length, 3);
    for (var i = 0; i < 3; i++) {
      expect(decodificados[i].$1, closeTo(puntos[i].$1, 1e-5));
      expect(decodificados[i].$2, closeTo(puntos[i].$2, 1e-5));
    }
  });

  test('todos los puntos quedan dentro de rangos válidos', () {
    final puntos = [for (var i = 0; i < 50; i++) (-33.4 - i * 0.003, -70.6 + i * 0.002)];
    for (final p in decodificarPolilinea(codificarPolilinea(puntos))) {
      expect(p.$1, inInclusiveRange(-90, 90));
      expect(p.$2, inInclusiveRange(-180, 180));
    }
  });
}

/// Codificador de referencia (algoritmo de Google) solo para las pruebas.
String codificarPolilinea(List<(double, double)> puntos) {
  final salida = StringBuffer();
  var latAnt = 0, lngAnt = 0;
  void codificar(int valor) {
    var v = valor < 0 ? (-valor) * 2 - 1 : valor * 2;
    while (v >= 0x20) {
      salida.writeCharCode((0x20 | (v % 32)) + 63);
      v ~/= 32;
    }
    salida.writeCharCode(v + 63);
  }

  for (final (lat, lng) in puntos) {
    final la = (lat * 1e5).round(), ln = (lng * 1e5).round();
    codificar(la - latAnt);
    codificar(ln - lngAnt);
    latAnt = la;
    lngAnt = ln;
  }
  return salida.toString();
}
