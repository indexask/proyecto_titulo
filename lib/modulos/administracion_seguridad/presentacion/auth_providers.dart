import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/almacen_local.dart';
import '../datos/auth_repositorio.dart';
import '../datos/usuarios_repositorio.dart';
import '../dominio/usuario.dart';

final almacenLocalProvider = Provider<AlmacenLocal>((ref) => AlmacenLocal());

final authRepositorioProvider =
    Provider<AuthRepositorio>((ref) => AuthRepositorio(ref.watch(almacenLocalProvider)));

final usuariosRepositorioProvider = Provider<UsuariosRepositorio>((ref) => UsuariosRepositorio());

final sesionProvider = StreamProvider<AuthState>((ref) {
  return ref.watch(authRepositorioProvider).cambiosDeSesion;
});

final usuarioIdProvider = Provider<String?>((ref) {
  final sesion = ref.watch(sesionProvider).value;
  return sesion?.session?.user.id ?? ref.watch(authRepositorioProvider).usuarioIdActual;
});

final usuarioActualProvider = FutureProvider<Usuario?>((ref) async {
  final id = ref.watch(usuarioIdProvider);
  if (id == null) return null;
  return ref.watch(authRepositorioProvider).obtenerUsuario(id);
});

final usuariosProvider = FutureProvider.autoDispose<List<Usuario>>((ref) {
  return ref.watch(usuariosRepositorioProvider).listar();
});

final choferesProvider = FutureProvider.autoDispose<List<Usuario>>((ref) {
  return ref.watch(usuariosRepositorioProvider).listar(rol: Rol.chofer);
});
