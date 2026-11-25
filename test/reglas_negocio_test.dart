import 'package:flutter_test/flutter_test.dart';
import 'package:gygtrack/core/formato.dart';
import 'package:gygtrack/core/polilinea.dart';
import 'package:gygtrack/modulos/gestion_comercial/dominio/orden_compra.dart';
import 'package:gygtrack/modulos/gestion_comercial/dominio/rentabilidad.dart';
import 'package:gygtrack/modulos/logistico_notificaciones/dominio/estado_despacho.dart';

DetalleOrden linea(int cantidad, num costo, num precio) => DetalleOrden(
      productoId: 'p',
      productoNombre: 'Producto',
      cantidad: cantidad,
      costoCompra: costo,
      precioVenta: precio,
    );

void main() {
  group('Motor de rentabilidad (RF-07)', () {
    test('margen neto = Σ (precio − costo) × cantidad', () {
      final lineas = [linea(10, 8000, 12000), linea(2, 150000, 190000)];
      // 10 × 4.000 + 2 × 40.000 = 120.000
      expect(calcularMargenNeto(lineas), 120000);
    });

    test('un margen negativo (pérdida) se refleja tal cual', () {
      expect(calcularMargenNeto([linea(3, 1000, 900)]), -300);
    });

    test('sin líneas el margen es cero', () {
      expect(calcularMargenNeto(const []), 0);
    });

    test('porcentaje de margen sobre la venta', () {
      expect(porcentajeMargen(25, 100), 25);
      expect(porcentajeMargen(10, 0), isNull);
    });
  });

  group('Máquina de estados del despacho (RF-14)', () {
    test('solo avanza un paso: Pendiente → En Ruta → Entregado', () {
      expect(EstadoDespacho.pendiente.siguiente, EstadoDespacho.enRuta);
      expect(EstadoDespacho.enRuta.siguiente, EstadoDespacho.entregado);
      expect(EstadoDespacho.entregado.siguiente, isNull);
    });

    test('no permite saltos ni retrocesos', () {
      expect(EstadoDespacho.pendiente.puedeAvanzarA(EstadoDespacho.entregado), isFalse);
      expect(EstadoDespacho.entregado.puedeAvanzarA(EstadoDespacho.enRuta), isFalse);
      expect(EstadoDespacho.enRuta.puedeAvanzarA(EstadoDespacho.enRuta), isFalse);
    });

    test('códigos coinciden con la base de datos', () {
      expect(EstadoDespacho.values.map((e) => e.codigo), ['pendiente', 'en_ruta', 'entregado']);
      expect(EstadoDespacho.desdeCodigo('en_ruta'), EstadoDespacho.enRuta);
    });
  });

  group('Formato chileno de montos', () {
    test('parsea montos con punto de miles y coma decimal', () {
      expect(parsearMonto('\$12.500'), 12500);
      expect(parsearMonto('1.234,5'), 1234.5);
      expect(parsearMonto(''), isNull);
      expect(parsearMonto('abc'), isNull);
    });

    test('textoMonto y parsearMonto son inversos', () {
      for (final v in [12500.0, 1234.5, 0, 990000]) {
        expect(parsearMonto(textoMonto(v)), v);
      }
    });
  });

  test('decodifica polilíneas de Google (ejemplo de la documentación)', () {
    final puntos = decodificarPolilinea('_p~iF~ps|U_ulLnnqC_mqNvxq`@');
    expect(puntos, [(38.5, -120.2), (40.7, -120.95), (43.252, -126.453)]);
  });
}
