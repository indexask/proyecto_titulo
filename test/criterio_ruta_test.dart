import 'package:flutter_test/flutter_test.dart';
import 'package:gygtrack/modulos/enrutamiento/dominio/ruta.dart';

Map<String, dynamic> _r(num km, int min, num costo) =>
    {'distanciaKm': km, 'duracionMin': min, 'peajesClp': 0, 'combustibleClp': costo, 'costoClp': costo};

void main() {
  // Caso de la ruta del 13-11: plazo 97 min/65.9 km/$18.580, con TAG 88 min/
  // 68.6 km/$21.479, sin TAG 106 min/63.1 km/$14.946 (recomendada).
  final detalle = DetalleOptimizacion.fromMap({
    'sinOptimizar': _r(65.9, 97, 18580),
    'conTag': _r(68.6, 88, 21479),
    'sinTag': _r(63.1, 106, 14946),
    'elegida': 'sin_tag',
    'recomendada': 'sin_tag',
    'motivo': 'x',
    'alternativas': {'sin_optimizar': {}, 'con_tag': {}, 'sin_tag': {}},
  })!;

  test('cada criterio elige la alternativa que corresponde', () {
    expect(detalle.alternativaPara(CriterioRuta.equilibrada), AlternativaRuta.optimizadaSinTag);
    expect(detalle.alternativaPara(CriterioRuta.menosTiempo), AlternativaRuta.optimizadaConTag);
    expect(detalle.alternativaPara(CriterioRuta.menosPlata), AlternativaRuta.optimizadaSinTag);
    expect(detalle.alternativaPara(CriterioRuta.menosKm), AlternativaRuta.optimizadaSinTag);
    expect(detalle.tieneAlternativas, isTrue);
    expect(detalle.criterio, CriterioRuta.equilibrada);
  });

  test('en empate gana la recomendada', () {
    final d = DetalleOptimizacion.fromMap({
      'sinOptimizar': _r(50, 90, 10000),
      'conTag': _r(50, 80, 12000),
      'sinTag': _r(60, 100, 10000),
      'elegida': 'sin_optimizar',
      'recomendada': 'con_tag',
      'motivo': 'x',
    })!;
    expect(d.alternativaPara(CriterioRuta.menosKm), AlternativaRuta.optimizadaConTag);
    expect(d.tieneAlternativas, isFalse);
  });

  test('rutas antiguas sin "recomendada" usan la elegida', () {
    final d = DetalleOptimizacion.fromMap({
      'sinOptimizar': _r(1, 1, 1),
      'conTag': _r(1, 1, 1),
      'sinTag': _r(1, 1, 1),
      'elegida': 'con_tag',
      'motivo': 'x',
    })!;
    expect(d.recomendada, AlternativaRuta.optimizadaConTag);
  });
}
