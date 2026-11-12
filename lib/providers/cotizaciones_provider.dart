import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/cotizacion.dart';
import '../services/cotizaciones_service.dart';

final cotizacionesServiceProvider =
    Provider<CotizacionesService>((ref) => CotizacionesService());

final cotizacionesListProvider =
    FutureProvider.autoDispose<List<Cotizacion>>((ref) {
  return ref.watch(cotizacionesServiceProvider).listar();
});

final cotizacionesSinRutaProvider =
    FutureProvider.autoDispose<List<Cotizacion>>((ref) {
  return ref.watch(cotizacionesServiceProvider).listarSinRuta();
});

final cotizacionDetailProvider =
    FutureProvider.autoDispose.family<Cotizacion, String>((ref, id) async {
  final todas = await ref.watch(cotizacionesServiceProvider).listar();
  return todas.firstWhere((c) => c.id == id);
});
