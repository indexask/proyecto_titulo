import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../datos/cotizaciones_repositorio.dart';
import '../datos/ordenes_repositorio.dart';
import '../datos/productos_repositorio.dart';
import '../dominio/orden_compra.dart';
import '../dominio/producto.dart';

final ordenesRepositorioProvider = Provider<OrdenesRepositorio>((ref) => OrdenesRepositorio());

final productosRepositorioProvider =
    Provider<ProductosRepositorio>((ref) => ProductosRepositorio());

final ordenesProvider = FutureProvider.autoDispose<List<OrdenCompra>>((ref) {
  return ref.watch(ordenesRepositorioProvider).listar();
});

final ordenProvider = FutureProvider.autoDispose.family<OrdenCompra, String>((ref, id) {
  return ref.watch(ordenesRepositorioProvider).obtener(id);
});

final productosProvider = FutureProvider.autoDispose<List<Producto>>((ref) {
  return ref.watch(productosRepositorioProvider).listar();
});

final cotizacionesRepositorioProvider =
    Provider<CotizacionesRepositorio>((ref) => CotizacionesRepositorio());

/// URL firmada de la foto de un producto (válida 1 hora).
final urlFotoProductoProvider = FutureProvider.autoDispose.family<String, String>((ref, ruta) {
  return ref.watch(productosRepositorioProvider).urlFoto(ruta);
});
