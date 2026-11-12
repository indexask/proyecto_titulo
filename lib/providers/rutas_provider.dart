import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/profile.dart';
import '../models/ruta.dart';
import '../services/rutas_service.dart';
import 'auth_provider.dart';

final rutasServiceProvider = Provider<RutasService>((ref) => RutasService());

final rutasListProvider = FutureProvider.autoDispose<List<Ruta>>((ref) {
  return ref.watch(rutasServiceProvider).listar();
});

final rutaDetailProvider =
    FutureProvider.autoDispose.family<Ruta, String>((ref, rutaId) {
  return ref.watch(rutasServiceProvider).obtener(rutaId);
});

final choferesListProvider = FutureProvider.autoDispose<List<Profile>>((ref) {
  return ref.watch(rutasServiceProvider).listarChoferes();
});

/// Rutas visibles para el chofer autenticado (chofer_id ya viene filtrado
/// por RLS, pero igual filtramos localmente por si el listado trae otras).
final misRutasProvider = FutureProvider.autoDispose<List<Ruta>>((ref) async {
  final userId = ref.watch(currentUserIdProvider);
  final rutas = await ref.watch(rutasServiceProvider).listar();
  return rutas.where((r) => r.choferId == userId).toList();
});
