import 'package:flutter_test/flutter_test.dart';
import 'package:gygtrack/modulos/enrutamiento/dominio/ruta.dart';
import 'package:gygtrack/modulos/logistico_notificaciones/dominio/estado_despacho.dart';

ParadaRuta parada(int orden, EstadoDespacho estado) => ParadaRuta(
      orden: orden,
      despachoId: 'd$orden',
      cliente: 'Cliente $orden',
      direccion: 'Calle $orden',
      lat: -33.4,
      lng: -70.6,
      estado: estado,
    );

void main() {
  test('la próxima parada es la primera no entregada', () {
    final ruta = Ruta(
      id: 'r',
      fecha: DateTime(2026, 11, 12),
      origenDireccion: 'Bodega',
      origenLat: -33.5,
      origenLng: -70.7,
      paradas: [
        parada(0, EstadoDespacho.entregado),
        parada(1, EstadoDespacho.enRuta),
        parada(2, EstadoDespacho.pendiente),
      ],
    );
    expect(ruta.proximaParada?.orden, 1);
  });

  test('lee la comparación de la optimización (tiempo, km, TAG)', () {
    Map<String, dynamic> r(num km, int min, num tag) =>
        {'distanciaKm': km, 'duracionMin': min, 'peajesClp': tag, 'combustibleClp': 6402, 'costoClp': 6402 + tag};
    final d = DetalleOptimizacion.fromMap({
      'sinOptimizar': r(58.2, 95, 2100),
      'conTag': r(45.3, 71, 1830),
      'sinTag': r(49.0, 92, 0),
      'elegida': 'sin_optimizar',
      'motivo': 'Se usa TAG: ahorra 21 min…',
      'paradasPrioritarias': 1,
    })!;
    expect(d.eleccion, AlternativaRuta.ordenPorPlazo);
    expect(d.elegida.duracionMin, 95);
    expect(d.sinOptimizar.distanciaKm, 58.2);
    expect(d.paradasPrioritarias, 1);
    expect(DetalleOptimizacion.fromMap(null), isNull);
  });
}
