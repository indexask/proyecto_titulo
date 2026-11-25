import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/formato.dart';
import '../../../core/widgets/vista_async.dart';
import '../dominio/orden_compra.dart';
import '../dominio/rentabilidad.dart';
import 'comercial_providers.dart';

/// Visualización gráfica de la utilidad de las operaciones (RF-08).
class UtilidadPanel extends ConsumerWidget {
  const UtilidadPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(ordenesProvider);
    return VistaAsync(
      cargando: async.isLoading,
      error: async.error,
      onReintentar: () => ref.invalidate(ordenesProvider),
      child: Builder(builder: (context) {
        final ordenes = [...?async.value]..sort((a, b) => b.createdAt.compareTo(a.createdAt));
        if (ordenes.isEmpty) return const Center(child: Text('Sin órdenes para graficar.'));

        final margenTotal = ordenes.fold<num>(0, (s, o) => s + o.margenNeto);
        final ventaTotal = ordenes.fold<num>(0, (s, o) => s + o.ventaTotal);
        final pct = porcentajeMargen(margenTotal, ventaTotal);
        final tema = Theme.of(context);

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _Indicador(titulo: 'Utilidad neta total', valor: formatoClp(margenTotal)),
                _Indicador(titulo: 'Venta adjudicada', valor: formatoClp(ventaTotal)),
                _Indicador(titulo: 'Margen promedio', valor: pct == null ? '—' : '${pct.toStringAsFixed(1)} %'),
                _Indicador(titulo: 'Órdenes', valor: '${ordenes.length}'),
              ],
            ),
            const SizedBox(height: 24),
            Text('Utilidad por orden (más recientes primero)', style: tema.textTheme.titleMedium),
            const SizedBox(height: 12),
            _GraficoBarras(ordenes: ordenes.take(20).toList()),
          ],
        );
      }),
    );
  }
}

class _Indicador extends StatelessWidget {
  final String titulo;
  final String valor;

  const _Indicador({required this.titulo, required this.valor});

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return SizedBox(
      width: 200,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(titulo, style: tema.textTheme.bodySmall),
              const SizedBox(height: 4),
              Text(valor, style: tema.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Barras horizontales: verde para utilidad, rojo para pérdida.
class _GraficoBarras extends StatelessWidget {
  final List<OrdenCompra> ordenes;

  const _GraficoBarras({required this.ordenes});

  @override
  Widget build(BuildContext context) {
    final maximo = ordenes.map((o) => o.margenNeto.abs()).fold<num>(0, math.max);
    final tema = Theme.of(context);
    return Column(
      children: [
        for (final o in ordenes)
          InkWell(
            onTap: () => context.push('/admin/ordenes/${o.id}'),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  SizedBox(
                    width: 140,
                    child: Text(o.titulo, overflow: TextOverflow.ellipsis, style: tema.textTheme.bodySmall),
                  ),
                  Expanded(
                    child: LayoutBuilder(builder: (context, c) {
                      final fraccion = maximo == 0 ? 0.0 : o.margenNeto.abs() / maximo;
                      return Align(
                        alignment: Alignment.centerLeft,
                        child: Container(
                          height: 18,
                          width: math.max(2, c.maxWidth * fraccion),
                          decoration: BoxDecoration(
                            color: o.margenNeto < 0 ? Colors.red.shade400 : Colors.green.shade500,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      );
                    }),
                  ),
                  SizedBox(
                    width: 110,
                    child: Text(formatoClp(o.margenNeto), textAlign: TextAlign.end),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
