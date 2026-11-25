import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/router.dart';
import '../../administracion_seguridad/presentacion/auth_providers.dart';
import '../datos/push_repositorio.dart';
import 'logistico_providers.dart';

final pushRepositorioProvider = Provider<PushRepositorio>((ref) => PushRepositorio());

/// Para mostrar avisos desde fuera de una pantalla (push en primer plano).
final mensajeroGlobal = GlobalKey<ScaffoldMessengerState>();

/// Mientras haya un usuario con sesión: registra el dispositivo para recibir
/// push (RF-19), mantiene el token al día y reacciona a las notificaciones.
final pushServicioProvider = Provider<void>((ref) {
  final usuario = ref.watch(usuarioActualProvider).value;
  if (usuario == null || !PushRepositorio.disponible) return;

  final push = ref.read(pushRepositorioProvider);
  final suscripciones = <StreamSubscription<Object?>>[];
  ref.onDispose(() {
    for (final s in suscripciones) {
      s.cancel();
    }
  });

  void abrirAlertas() =>
      ref.read(routerProvider).go(usuario.esAdministrador ? '/admin' : '/chofer/alertas');

  unawaited(push.registrar().catchError((Object e) {
    debugPrint('No se pudo registrar el dispositivo para push: $e');
    return false;
  }));

  suscripciones
    ..add(push.cambiosDeToken.listen((t) => unawaited(push.guardarTokenRenovado(t))))
    // App abierta: el sistema no muestra la notificación, así que se avisa en
    // pantalla y se refrescan las alertas.
    ..add(push.mensajesEnPrimerPlano.listen((m) {
      ref.invalidate(alertasProvider);
      final n = m.notification;
      if (n != null) {
        mensajeroGlobal.currentState?.showSnackBar(SnackBar(
          content: Text('${n.title ?? 'Alerta'}\n${n.body ?? ''}'),
          duration: const Duration(seconds: 8),
          action: SnackBarAction(label: 'Ver', onPressed: abrirAlertas),
        ));
      }
    }))
    // El usuario tocó la notificación con la app en segundo plano.
    ..add(push.notificacionesAbiertas.listen((_) => abrirAlertas()));

  // La app se abrió desde una notificación estando cerrada.
  unawaited(push.notificacionInicial().then((m) {
    if (m != null) abrirAlertas();
  }));
});
