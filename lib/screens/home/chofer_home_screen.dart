import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../models/ruta.dart';
import '../../providers/auth_provider.dart';
import '../../providers/rutas_provider.dart';
import '../../widgets/async_view.dart';

class ChoferHomeScreen extends ConsumerWidget {
  const ChoferHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rutasAsync = ref.watch(misRutasProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mis rutas'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => ref.read(authServiceProvider).signOut(),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(misRutasProvider.future),
        child: AsyncStateView(
          loading: rutasAsync.isLoading,
          error: rutasAsync.error,
          onRetry: () => ref.invalidate(misRutasProvider),
          child: Builder(builder: (_) {
            final items = rutasAsync.value ?? [];
            if (items.isEmpty) {
              return const Center(
                child: Text('No tienes rutas asignadas por ahora.'),
              );
            }
            return ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: items.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, i) {
                final r = items[i];
                return Card(
                  child: ListTile(
                    leading: _estadoIcon(r.estado),
                    title: Text(r.nombre),
                    subtitle: Text('${r.puntos.length} puntos'),
                    onTap: () => context.push('/chofer/rutas/${r.id}'),
                  ),
                );
              },
            );
          }),
        ),
      ),
    );
  }

  Icon _estadoIcon(RutaEstado estado) {
    switch (estado) {
      case RutaEstado.completada:
        return const Icon(Icons.check_circle, color: Colors.green);
      case RutaEstado.enCurso:
        return const Icon(Icons.local_shipping, color: Colors.orange);
      case RutaEstado.pendiente:
        return const Icon(Icons.schedule, color: Colors.grey);
    }
  }
}
