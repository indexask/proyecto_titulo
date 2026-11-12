import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase_client.dart';
import '../dominio/producto.dart';

/// Catálogo de productos y sus costos (RF-11), con foto opcional.
class ProductosRepositorio {
  static const _bucket = 'productos';

  Future<List<Producto>> listar() async {
    final data = await supabase.from('producto').select().order('nombre');
    return data.map(Producto.fromMap).toList();
  }

  /// Crea o actualiza el producto y devuelve su id.
  Future<String> guardar({
    String? id,
    required String nombre,
    required num costoCompra,
    required num precioVenta,
  }) async {
    final valores = {'nombre': nombre, 'costo_compra': costoCompra, 'precio_venta': precioVenta};
    if (id == null) {
      final fila = await supabase.from('producto').insert(valores).select('id').single();
      return fila['id'] as String;
    }
    await supabase.from('producto').update(valores).eq('id', id);
    return id;
  }

  Future<void> eliminar(String id) => supabase.from('producto').delete().eq('id', id);

  /// Sube la foto (JPEG) al bucket privado y la asocia al producto.
  Future<void> subirFoto(String productoId, Uint8List jpeg) async {
    final ruta = '$productoId.jpg';
    await supabase.storage.from(_bucket).uploadBinary(
          ruta,
          jpeg,
          fileOptions: const FileOptions(contentType: 'image/jpeg', upsert: true),
        );
    await supabase.from('producto').update({'foto_path': ruta}).eq('id', productoId);
  }

  /// URL firmada temporal para mostrar la foto (el bucket es privado).
  Future<String> urlFoto(String ruta) =>
      supabase.storage.from(_bucket).createSignedUrl(ruta, 60 * 60);
}
