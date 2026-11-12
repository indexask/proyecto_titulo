import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../providers/cotizaciones_provider.dart';
import '../../widgets/async_view.dart';

class CotizacionDetailScreen extends ConsumerWidget {
  final String cotizacionId;

  const CotizacionDetailScreen({super.key, required this.cotizacionId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(cotizacionDetailProvider(cotizacionId));
    final currency = NumberFormat.currency(locale: 'es_CL', symbol: '\$');
    final dateFormat = DateFormat('dd-MM-yyyy');

    return Scaffold(
      appBar: AppBar(title: const Text('Detalle de cotización')),
      body: AsyncStateView(
        loading: async.isLoading,
        error: async.error,
        onRetry: () => ref.invalidate(cotizacionDetailProvider(cotizacionId)),
        child: Builder(builder: (_) {
          final c = async.value;
          if (c == null) return const SizedBox.shrink();
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (c.fotoUrl != null)
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.network(c.fotoUrl!, height: 200, fit: BoxFit.cover),
                ),
              const SizedBox(height: 16),
              Text(c.titulo, style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 16),
              _fila('N° cotización', c.numeroCotizacion ?? '—'),
              _fila('Fecha', c.fechaCotizacion != null ? dateFormat.format(c.fechaCotizacion!) : '—'),
              _fila('Solicitado por', c.cliente ?? '—'),
              _fila('Dirección de entrega', c.direccionEntrega ?? '—'),
              _fila('Descripción', c.descripcion ?? '—'),
              _fila('Unidades', c.unidades?.toString() ?? '—'),
              _fila('Precio unidad', c.precioUnidad != null ? currency.format(c.precioUnidad) : '—'),
              _fila('Total', c.monto != null ? currency.format(c.monto) : '—'),
              const SizedBox(height: 16),
              if (c.archivoUrl != null)
                OutlinedButton.icon(
                  onPressed: () => launchUrl(Uri.parse(c.archivoUrl!),
                      mode: LaunchMode.externalApplication),
                  icon: const Icon(Icons.picture_as_pdf),
                  label: const Text('Abrir PDF de la cotización'),
                ),
            ],
          );
        }),
      ),
    );
  }

  Widget _fila(String label, String valor) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 150,
            child: Text(label, style: const TextStyle(color: Colors.grey)),
          ),
          Expanded(child: Text(valor)),
        ],
      ),
    );
  }
}
