/// Motor de rentabilidad (RF-07).
///
///   margen_neto(orden) = Σ ((precio_venta − costo_compra) × cantidad)
///
/// La base de datos es la fuente oficial del margen (trigger
/// detalle_orden_margen); este cálculo se usa para mostrarlo al instante
/// mientras el Administrador ingresa la orden (KPI-03: ≤ 2 s).
abstract interface class LineaConMargen {
  num get cantidad;
  num get costoCompra;
  num get precioVenta;
}

num margenDeLinea(LineaConMargen linea) =>
    (linea.precioVenta - linea.costoCompra) * linea.cantidad;

num calcularMargenNeto(Iterable<LineaConMargen> lineas) =>
    lineas.fold<num>(0, (total, linea) => total + margenDeLinea(linea));

num calcularVentaTotal(Iterable<LineaConMargen> lineas) =>
    lineas.fold<num>(0, (total, l) => total + l.precioVenta * l.cantidad);

/// Margen como porcentaje de la venta; `null` si no hay venta.
double? porcentajeMargen(num margen, num venta) => venta == 0 ? null : margen / venta * 100;
