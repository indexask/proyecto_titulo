/// Producto del catálogo (RF-11). Contiene datos financieros: solo lo ve el
/// Administrador.
class Producto {
  final String id;
  final String nombre;
  final num costoCompra;
  final num precioVenta;

  const Producto({
    required this.id,
    required this.nombre,
    required this.costoCompra,
    required this.precioVenta,
  });

  num get margenUnitario => precioVenta - costoCompra;

  factory Producto.fromMap(Map<String, dynamic> map) => Producto(
        id: map['id'] as String,
        nombre: map['nombre'] as String,
        costoCompra: map['costo_compra'] as num,
        precioVenta: map['precio_venta'] as num,
      );
}
