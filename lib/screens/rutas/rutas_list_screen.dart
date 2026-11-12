import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../models/ruta.dart';
import '../../providers/rutas_provider.dart';
import '../../widgets/async_view.dart';

class RutasListScreen extends ConsumerWidget {
  const RutasListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rutasAsync = ref.watch(rutasListProvider);

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(rutasListProvider.future),
        child: AsyncStateView(
          loading: rutasAsync.isLoading,
          error: rutasAsync.error,
          onRetry: () => ref.invalidate(rutasListProvider),
          child: Builder(builder: (_) {
            final items = rutasAsync.value ?? [];
            if (items.isEmpty) {
              return const Center(
                child: Text('No hay rutas creadas todavía.'),
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
                    subtitle: Text('${r.puntos.length} puntos · ${r.choferId == null ? 'sin chofer asignado' : 'asignada'}'),
                    onTap: () => context.push('/admin/rutas/${r.id}'),
                  ),
                );
              },
            );
          }),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/admin/rutas/nueva'),
        icon: const Icon(Icons.add_road),
        label: const Text('Crear ruta'),
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
