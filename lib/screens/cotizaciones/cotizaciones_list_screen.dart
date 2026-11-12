import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../providers/cotizaciones_provider.dart';
import '../../widgets/async_view.dart';

class CotizacionesListScreen extends ConsumerWidget {
  const CotizacionesListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cotizacionesAsync = ref.watch(cotizacionesListProvider);
    final currency = NumberFormat.currency(locale: 'es_CL', symbol: '\$');

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(cotizacionesListProvider.future),
        child: AsyncStateView(
          loading: cotizacionesAsync.isLoading,
          error: cotizacionesAsync.error,
          onRetry: () => ref.invalidate(cotizacionesListProvider),
          child: Builder(builder: (_) {
            final items = cotizacionesAsync.value ?? [];
            if (items.isEmpty) {
              return const Center(
                child: Text('Aún no hay cotizaciones adjudicadas.'),
              );
            }
            return ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: items.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, i) {
                final c = items[i];
                return Card(
                  child: ListTile(
                    title: Text(c.titulo),
                    subtitle: Text(c.cliente ?? 'Sin cliente'),
                    trailing: c.monto != null
                        ? Text(currency.format(c.monto))
                        : null,
                    onTap: () => context.push('/admin/cotizaciones/${c.id}'),
                  ),
                );
              },
            );
          }),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/admin/cotizaciones/nueva'),
        icon: const Icon(Icons.add),
        label: const Text('Subir cotización'),
      ),
    );
  }
}
