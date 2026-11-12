import 'package:flutter/material.dart';

/// Centra un loader o un mensaje de error; útil para el estado de los
/// AsyncValue de Riverpod sin repetir el mismo boilerplate en cada pantalla.
class AsyncStateView extends StatelessWidget {
  final bool loading;
  final Object? error;
  final VoidCallback? onRetry;
  final Widget child;

  const AsyncStateView({
    super.key,
    required this.loading,
    required this.error,
    required this.child,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Ocurrió un error: $error', textAlign: TextAlign.center),
            if (onRetry != null) ...[
              const SizedBox(height: 12),
              FilledButton(onPressed: onRetry, child: const Text('Reintentar')),
            ],
          ],
        ),
      );
    }
    return child;
  }
}
