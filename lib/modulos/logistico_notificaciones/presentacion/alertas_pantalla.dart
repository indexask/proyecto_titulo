import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/formato.dart';
import '../../../core/widgets/vista_async.dart';
import '../dominio/alerta.dart';
import 'logistico_providers.dart';

/// Registro de alertas emitidas (RF-20). Se usa en ambas vistas: el
/// Administrador ve todas y el Chofer solo las de sus órdenes.
class AlertasLista extends ConsumerWidget {
  const AlertasLista({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(alertasProvider);
    return RefreshIndicator(
      onRefresh: () => ref.refresh(alertasProvider.future),
      child: VistaAsync(
        cargando: async.isLoading,
        error: async.error,
        onReintentar: () => ref.invalidate(alertasProvider),
        child: Builder(builder: (context) {
          final alertas = async.value ?? const <Alerta>[];
          if (alertas.isEmpty) {
            return ListView(children: const [
              SizedBox(height: 120),
              Center(child: Text('No hay alertas emitidas.')),
            ]);
          }
          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: alertas.length,
            separatorBuilder: (_, _) => const SizedBox(height: 4),
            itemBuilder: (context, i) {
              final a = alertas[i];
              final esDiaCero = a.tipo == TipoAlerta.diaCero;
              return Card(
                child: ListTile(
                  leading: Icon(
                    esDiaCero ? Icons.error : Icons.warning_amber,
                    color: esDiaCero ? Colors.red : Colors.orange,
                  ),
                  title: Text('${a.tipo.etiqueta} · ${a.cliente}'),
                  subtitle: Text(
                    '${a.numeroOc != null ? 'OC ${a.numeroOc} · ' : ''}'
                    'Plazo ${formatoFecha(a.fechaComprometida)}\n'
                    'Emitida ${formatoFechaHora(a.fechaEmision)}',
                  ),
                  isThreeLine: true,
                ),
              );
            },
          );
        }),
      ),
    );
  }
}

class AlertasPantalla extends StatelessWidget {
  const AlertasPantalla({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(appBar: AppBar(title: const Text('Alertas')), body: const AlertasLista());
  }
}
