import 'package:flutter/material.dart';

import '../errores.dart';

/// Muestra un indicador de carga o un mensaje de error con reintento, y si no
/// hay ninguno de los dos, el contenido.
class VistaAsync extends StatelessWidget {
  final bool cargando;
  final Object? error;
  final VoidCallback? onReintentar;
  final Widget child;

  const VistaAsync({
    super.key,
    required this.cargando,
    required this.error,
    required this.child,
    this.onReintentar,
  });

  @override
  Widget build(BuildContext context) {
    if (cargando) return const Center(child: CircularProgressIndicator());
    if (error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Ocurrió un error: ${mensajeError(error!)}', textAlign: TextAlign.center),
              if (onReintentar != null) ...[
                const SizedBox(height: 12),
                FilledButton(onPressed: onReintentar, child: const Text('Reintentar')),
              ],
            ],
          ),
        ),
      );
    }
    return child;
  }
}

void mostrarMensaje(BuildContext context, String mensaje) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(mensaje)));
}
