import 'package:flutter_test/flutter_test.dart';
import 'package:gygtrack/modulos/gestion_comercial/dominio/cotizacion_importada.dart';

void main() {
  test('lee la respuesta de importar-cotizacion (cotización real 5609-132-COT26)', () {
    final c = CotizacionImportada.fromMap({
      'fechaCotizacion': '2026-08-12',
      'solicitadoPor': 'UNIVERSIDAD DE CHILE',
      'direccion': 'Arturo Bürhle 50, Providencia, Región Metropolitana de Santiago',
      'numeroCotizacion': '5609-132-COT26',
      'lineas': [
        {
          'descripcion': 'Aspiradora Industrial Polvo / Agua - 80 Lts. 3 Motores -3.000W - Glanz BF585-3',
          'unidades': 1,
          'precioUnidad': 259697,
          'total': 259697,
        },
      ],
      'subtotal': 259697,
      'iva': 49342,
      'totalConIva': 309039,
      'plazoDiasHabiles': {'min': 2, 'max': 5},
      'foto': {'base64': '/9j/4AAQ', 'tipo': 'image/jpeg'},
      'advertencias': <String>[],
    });
    expect(c.fechaCotizacion, DateTime(2026, 8, 12));
    expect(c.solicitadoPor, 'UNIVERSIDAD DE CHILE');
    expect(c.numeroCotizacion, '5609-132-COT26');
    expect(c.lineas.single.unidades, 1);
    expect(c.lineas.single.precioUnidad, 259697);
    expect(c.subtotal, 259697);
    expect(c.plazoDiasHabiles?.max, 5);
    expect(c.foto?.take(2), [0xFF, 0xD8]); // encabezado JPEG
  });

  test('días hábiles: salta sábados y domingos', () {
    // Jueves 12-11-2026 + 5 días hábiles = jueves 19-11-2026.
    expect(sumarDiasHabiles(DateTime(2026, 11, 12), 5), DateTime(2026, 11, 19));
    // Viernes + 1 día hábil = lunes.
    expect(sumarDiasHabiles(DateTime(2026, 11, 13), 1), DateTime(2026, 11, 16));
  });

  test('reconoce productos del catálogo aunque cambien mayúsculas, tildes o espacios', () {
    expect(normalizarNombre('  Aspiradora  INDUSTRIAL Polvo/Agua '), normalizarNombre('aspiradora industrial polvo/agua'));
    expect(normalizarNombre('Cámara Ñandú'), 'camara nandu');
  });

  test('varias fotos: una por producto en el orden de la tabla', () {
    final c = CotizacionImportada.fromMap({
      'lineas': [
        {'descripcion': 'Mesa plegable', 'unidades': 20, 'precioUnidad': 36542, 'total': 730840},
        {'descripcion': 'Silla plegable', 'unidades': 200, 'precioUnidad': 20714, 'total': 4142800},
      ],
      'fotos': [
        {'base64': 'AQI=', 'tipo': 'image/jpeg'},
        {'base64': 'AwQ=', 'tipo': 'image/jpeg'},
      ],
      'advertencias': <String>[],
    });
    expect(c.fotos.length, 2);
    expect(c.fotoDe(0), [1, 2]);
    expect(c.fotoDe(1), [3, 4]);
    expect(c.fotoDe(2), isNull);
  });
}
