import 'package:flutter_test/flutter_test.dart';
import 'package:gygtrack/modulos/enrutamiento/datos/navegacion_repositorio.dart';
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

  test('la navegación abre toda la ruta en Google Maps con las direcciones exactas', () {
    const bodega = PuntoNavegacion(direccion: 'San Juan de la Cruz 5453, Maipú', lat: -33.5, lng: -70.7);
    final url = NavegacionRepositorio.urlRuta(const [
      PuntoNavegacion(direccion: 'Arturo Burhle 50, Providencia', lat: -33.43, lng: -70.61),
      PuntoNavegacion(direccion: 'Loreley 1582, La Reina'),
      PuntoNavegacion(direccion: '', lat: -33.40, lng: -70.64), // sin dirección: coordenadas
    ], bodega);
    expect(url.host, 'www.google.com');
    expect(url.path, '/maps/dir/');
    expect(url.queryParameters, {
      'api': '1',
      'destination': 'San Juan de la Cruz 5453, Maipú',
      'waypoints': 'Arturo Burhle 50, Providencia|Loreley 1582, La Reina|-33.4,-70.64',
      'travelmode': 'driving',
      'dir_action': 'navigate',
    });
  });

  test('con más paradas que el límite de Google Maps, el enlace llega hasta la décima', () {
    final paradas = [for (var i = 1; i <= 12; i++) PuntoNavegacion(direccion: 'Calle $i')];
    final url = NavegacionRepositorio.urlRuta(paradas, const PuntoNavegacion(direccion: 'Bodega'));
    expect(url.queryParameters['destination'], 'Calle 10');
    expect(url.queryParameters['waypoints']!.split('|').length, 9);
    expect(NavegacionRepositorio.paradasFuera(paradas), 2);
    expect(NavegacionRepositorio.paradasFuera(paradas.take(10).toList()), 0);
  });

  test('estado de la ruta según sus paradas: por iniciar, en curso, completada', () {
    Ruta con(List<EstadoDespacho> estados) => Ruta(
          id: 'r',
          fecha: DateTime(2026, 11, 12),
          origenDireccion: 'Bodega',
          origenLat: -33.5,
          origenLng: -70.7,
          paradas: [for (final (i, e) in estados.indexed) parada(i, e)],
        );
    expect(con([EstadoDespacho.pendiente, EstadoDespacho.pendiente]).estado, EstadoRuta.porIniciar);
    expect(con([EstadoDespacho.enRuta, EstadoDespacho.pendiente]).estado, EstadoRuta.enCurso);
    expect(con([EstadoDespacho.entregado, EstadoDespacho.enRuta]).estado, EstadoRuta.enCurso);
    expect(con([EstadoDespacho.entregado, EstadoDespacho.entregado]).estado, EstadoRuta.completada);
    expect(con([EstadoDespacho.entregado, EstadoDespacho.enRuta]).entregadas, 1);
  });
}
