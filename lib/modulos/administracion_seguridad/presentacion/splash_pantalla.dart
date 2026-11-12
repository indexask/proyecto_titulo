import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errores.dart';
import 'auth_providers.dart';

class SplashPantalla extends ConsumerWidget {
  const SplashPantalla({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final usuario = ref.watch(usuarioActualProvider);
    if (usuario.hasError) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('No se pudo cargar tu perfil: ${mensajeError(usuario.error!)}',
                    textAlign: TextAlign.center),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () => ref.invalidate(usuarioActualProvider),
                  child: const Text('Reintentar'),
                ),
                TextButton(
                  onPressed: () => ref.read(authRepositorioProvider).cerrarSesion(),
                  child: const Text('Cerrar sesión'),
                ),
              ],
            ),
          ),
        ),
      );
    }
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}
