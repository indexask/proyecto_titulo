import 'package:flutter_test/flutter_test.dart';
import 'package:gygtrack/modulos/enrutamiento/dominio/ruta.dart';
import 'package:gygtrack/modulos/logistico_notificaciones/dominio/estado_despacho.dart';

ParadaRuta _parada(int orden, EstadoDespacho estado) => ParadaRuta(
      orden: orden,
      despachoId: 'd$orden',
      cliente: 'C$orden',
      direccion: 'Calle $orden',
      lat: -33.4,
      lng: -70.6,
      estado: estado,
    );

Ruta _ruta(List<EstadoDespacho> estados) => Ruta(
      id: 'r',
      fecha: DateTime(2026, 11, 17),
      origenDireccion: 'Bodega',
      origenLat: -33.45,
      origenLng: -70.66,
      paradas: [for (var i = 0; i < estados.length; i++) _parada(i, estados[i])],
    );

void main() {
  group('Máquina de estados del despacho', () {
    test('transiciones permitidas, incluida No entregado', () {
      expect(EstadoDespacho.pendiente.puedeAvanzarA(EstadoDespacho.enRuta), isTrue);
      expect(EstadoDespacho.enRuta.puedeAvanzarA(EstadoDespacho.entregado), isTrue);
      expect(EstadoDespacho.enRuta.puedeAvanzarA(EstadoDespacho.noEntregado), isTrue);
      // Reintento y entrega posterior desde No entregado.
      expect(EstadoDespacho.noEntregado.puedeAvanzarA(EstadoDespacho.enRuta), isTrue);
      expect(EstadoDespacho.noEntregado.puedeAvanzarA(EstadoDespacho.entregado), isTrue);
    });

    test('transiciones NO permitidas', () {
      expect(EstadoDespacho.pendiente.puedeAvanzarA(EstadoDespacho.entregado), isFalse);
      expect(EstadoDespacho.pendiente.puedeAvanzarA(EstadoDespacho.noEntregado), isFalse);
      expect(EstadoDespacho.entregado.puedeAvanzarA(EstadoDespacho.enRuta), isFalse);
      expect(EstadoDespacho.entregado.siguientesPosibles, isEmpty);
    });

    test('solo No entregado exige motivo; entregado es terminal', () {
      expect(EstadoDespacho.noEntregado.requiereMotivo, isTrue);
      expect(EstadoDespacho.entregado.requiereMotivo, isFalse);
      expect(EstadoDespacho.entregado.esTerminal, isTrue);
      expect(EstadoDespacho.noEntregado.esTerminal, isFalse);
    });

    test('desdeCodigo reconoce no_entregado', () {
      expect(EstadoDespacho.desdeCodigo('no_entregado'), EstadoDespacho.noEntregado);
    });
  });

  group('Avance de la ruta con paradas no entregadas', () {
    test('una parada no entregada cuenta como resuelta: la ruta se completa', () {
      final ruta = _ruta([EstadoDespacho.entregado, EstadoDespacho.noEntregado]);
      expect(ruta.estado, EstadoRuta.completada);
      expect(ruta.proximaParada, isNull);
      expect(ruta.noEntregadas, 1);
      expect(ruta.entregadas, 1);
    });

    test('la próxima parada omite las no entregadas', () {
      final ruta = _ruta([EstadoDespacho.noEntregado, EstadoDespacho.pendiente]);
      expect(ruta.proximaParada?.orden, 1);
      expect(ruta.estado, EstadoRuta.enCurso);
    });
  });
}
