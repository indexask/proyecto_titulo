import '../../../core/supabase_client.dart';
import '../dominio/producto.dart';

/// Catálogo de productos y sus costos (RF-11).
class ProductosRepositorio {
  Future<List<Producto>> listar() async {
    final data = await supabase.from('producto').select().order('nombre');
    return data.map(Producto.fromMap).toList();
  }

  Future<void> guardar({
    String? id,
    required String nombre,
    required num costoCompra,
    required num precioVenta,
  }) async {
    final valores = {'nombre': nombre, 'costo_compra': costoCompra, 'precio_venta': precioVenta};
    if (id == null) {
      await supabase.from('producto').insert(valores);
    } else {
      await supabase.from('producto').update(valores).eq('id', id);
    }
  }

  Future<void> eliminar(String id) => supabase.from('producto').delete().eq('id', id);
}
