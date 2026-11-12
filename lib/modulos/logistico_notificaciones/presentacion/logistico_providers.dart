import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../administracion_seguridad/presentacion/auth_providers.dart';
import '../datos/alertas_repositorio.dart';
import '../datos/despachos_chofer_repositorio.dart';
import '../dominio/alerta.dart';
import '../dominio/estado_despacho.dart';

final despachosRemotoProvider = Provider<DespachosRemoto>((ref) => DespachosRemotoSupabase());

final despachosChoferRepositorioProvider = Provider<DespachosChoferRepositorio?>((ref) {
  final usuarioId = ref.watch(usuarioIdProvider);
  if (usuarioId == null) return null;
  return DespachosChoferRepositorio(
    ref.watch(despachosRemotoProvider),
    ref.watch(almacenLocalProvider),
    usuarioId,
  );
});

/// Despachos del Chofer con sincronización automática al recuperar la
/// conexión (RF-15).
class DespachosChoferNotifier extends AsyncNotifier<ResultadoDespachos> {
  DespachosChoferRepositorio get _repo {
    final repo = ref.read(despachosChoferRepositorioProvider);
    if (repo == null) throw StateError('Sin sesión activa');
    return repo;
  }

  @override
  Future<ResultadoDespachos> build() async {
    final repo = ref.watch(despachosChoferRepositorioProvider);
    if (repo == null) throw StateError('Sin sesión activa');

    final suscripcion = Connectivity().onConnectivityChanged.listen((resultados) {
      if (!resultados.contains(ConnectivityResult.none)) unawaited(recargar());
    });
    ref.onDispose(suscripcion.cancel);

    return repo.cargar();
  }

  Future<void> recargar() async {
    final resultado = await AsyncValue.guard(_repo.cargar);
    if (!ref.mounted) return;
    // Si falla la recarga pero ya había datos, se conservan.
    if (resultado.hasError && state.hasValue) return;
    state = resultado;
  }

  /// Lanza una excepción si la transición no está permitida.
  Future<void> cambiarEstado(String despachoId, EstadoDespacho nuevo) async {
    final resultado = await _repo.cambiarEstado(despachoId, nuevo);
    if (ref.mounted) state = AsyncData(resultado);
  }
}

final despachosChoferProvider =
    AsyncNotifierProvider<DespachosChoferNotifier, ResultadoDespachos>(DespachosChoferNotifier.new);

final alertasRepositorioProvider =
    Provider<AlertasRepositorio>((ref) => AlertasRepositorio(ref.watch(almacenLocalProvider)));

/// Alertas según el rol: el Administrador ve todas; el Chofer, las de sus
/// órdenes.
final alertasProvider = FutureProvider.autoDispose<List<Alerta>>((ref) async {
  final usuario = await ref.watch(usuarioActualProvider.future);
  if (usuario == null) return [];
  final repo = ref.watch(alertasRepositorioProvider);
  return usuario.esAdministrador ? repo.listarTodas() : repo.listarDelChofer(usuario.id);
});
