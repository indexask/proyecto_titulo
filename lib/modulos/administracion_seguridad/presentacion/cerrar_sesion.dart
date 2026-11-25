import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../logistico_notificaciones/presentacion/push_servicio.dart';
import 'auth_providers.dart';

/// Cierre de sesión seguro (RF-04). Si quedan cambios offline sin
/// sincronizar, advierte antes de borrarlos del dispositivo.
Future<void> cerrarSesion(BuildContext context, WidgetRef ref, {int cambiosPendientes = 0}) async {
  final confirmado = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Cerrar sesión'),
      content: Text(cambiosPendientes > 0
          ? 'Tienes $cambiosPendientes cambio(s) de estado sin sincronizar. '
              'Si cierras sesión ahora se perderán. ¿Continuar?'
          : '¿Quieres cerrar tu sesión en este dispositivo?'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Cerrar sesión')),
      ],
    ),
  );
  if (confirmado == true) {
    // El dispositivo deja de recibir push de este usuario (antes de cerrar
    // la sesión, porque el borrado del token necesita estar autenticado).
    await ref.read(pushRepositorioProvider).desregistrar();
    await ref.read(authRepositorioProvider).cerrarSesion();
  }
}

class BotonCerrarSesion extends ConsumerWidget {
  final int cambiosPendientes;

  const BotonCerrarSesion({super.key, this.cambiosPendientes = 0});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return IconButton(
      tooltip: 'Cerrar sesión',
      icon: const Icon(Icons.logout),
      onPressed: () => cerrarSesion(context, ref, cambiosPendientes: cambiosPendientes),
    );
  }
}
