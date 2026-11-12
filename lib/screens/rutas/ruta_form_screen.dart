import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geocoding/geocoding.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../providers/cotizaciones_provider.dart';
import '../../providers/rutas_provider.dart';
import '../../widgets/async_view.dart';

class RutaFormScreen extends ConsumerStatefulWidget {
  const RutaFormScreen({super.key});

  @override
  ConsumerState<RutaFormScreen> createState() => _RutaFormScreenState();
}

class _RutaFormScreenState extends ConsumerState<RutaFormScreen> {
  final _nombreCtrl = TextEditingController();
  final _origenCtrl = TextEditingController();
  final _seleccionadas = <String>{};
  String? _choferId;
  bool _guardando = false;

  @override
  void dispose() {
    _nombreCtrl.dispose();
    _origenCtrl.dispose();
    super.dispose();
  }

  Future<void> _guardar(List<Map<String, dynamic>> cotizacionesData) async {
    if (_nombreCtrl.text.trim().isEmpty) {
      _snack('Ponle un nombre a la ruta');
      return;
    }
    if (_seleccionadas.isEmpty) {
      _snack('Selecciona al menos una cotización');
      return;
    }
    if (_origenCtrl.text.trim().isEmpty) {
      _snack('Ingresa la dirección de partida');
      return;
    }

    setState(() => _guardando = true);
    try {
      final ubicaciones =
          await Geocoding().locationFromAddress(_origenCtrl.text.trim());
      if (ubicaciones.isEmpty) {
        throw Exception('No se encontró la dirección de partida');
      }
      final origen = ubicaciones.first;

      final seleccionData = cotizacionesData
          .where((c) => _seleccionadas.contains(c['id']))
          .toList();

      final ruta = await ref.read(rutasServiceProvider).crearOptimizada(
            cotizaciones: seleccionData,
            nombre: _nombreCtrl.text.trim(),
            choferId: _choferId,
            origenDireccion: _origenCtrl.text.trim(),
            origenLat: origen.latitude,
            origenLng: origen.longitude,
          );
      ref.invalidate(rutasListProvider);
      ref.invalidate(cotizacionesSinRutaProvider);
      if (mounted) context.go('/admin/rutas/${ruta.id}');
    } catch (e) {
      _snack('Error: $e');
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final cotizacionesAsync = ref.watch(cotizacionesSinRutaProvider);
    final choferesAsync = ref.watch(choferesListProvider);
    final currency = NumberFormat.currency(locale: 'es_CL', symbol: '\$');

    return Scaffold(
      appBar: AppBar(title: const Text('Nueva ruta optimizada')),
      body: AsyncStateView(
        loading: cotizacionesAsync.isLoading,
        error: cotizacionesAsync.error,
        onRetry: () => ref.invalidate(cotizacionesSinRutaProvider),
        child: Builder(builder: (_) {
          final cotizaciones = cotizacionesAsync.value ?? [];
          final cotizacionesData = cotizaciones
              .where((c) => c.direccionLat != null && c.direccionLng != null)
              .map((c) => {
                    'id': c.id,
                    'direccion': c.direccionEntrega ?? '',
                    'lat': c.direccionLat,
                    'lng': c.direccionLng,
                  })
              .toList();

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              TextField(
                controller: _nombreCtrl,
                decoration: const InputDecoration(labelText: 'Nombre de la ruta'),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _origenCtrl,
                decoration: const InputDecoration(
                  labelText: 'Dirección de partida (bodega/local)',
                ),
              ),
              const SizedBox(height: 16),
              choferesAsync.when(
                data: (choferes) => DropdownButtonFormField<String>(
                  initialValue: _choferId,
                  decoration: const InputDecoration(labelText: 'Asignar chofer'),
                  items: choferes
                      .map((c) => DropdownMenuItem(
                          value: c.id, child: Text(c.fullName ?? c.id)))
                      .toList(),
                  onChanged: (v) => setState(() => _choferId = v),
                ),
                loading: () => const LinearProgressIndicator(),
                error: (e, _) => Text('No se pudo cargar choferes: $e'),
              ),
              const Divider(height: 32),
              Text('Cotizaciones a entregar',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 4),
              const Text(
                'Selecciona las que salen en esta ruta. El orden de visita se optimiza automáticamente.',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 8),
              if (cotizaciones.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Text('No hay cotizaciones disponibles sin ruta asignada.'),
                ),
              for (final c in cotizaciones)
                CheckboxListTile(
                  value: _seleccionadas.contains(c.id),
                  onChanged: c.direccionLat == null
                      ? null
                      : (v) {
                          setState(() {
                            if (v == true) {
                              _seleccionadas.add(c.id);
                            } else {
                              _seleccionadas.remove(c.id);
                            }
                          });
                        },
                  title: Text(c.titulo),
                  subtitle: Text(
                    '${c.cliente ?? 'Sin cliente'} · ${c.direccionEntrega ?? 'sin dirección'}'
                    '${c.direccionLat == null ? ' (sin geocodificar)' : ''}',
                  ),
                  secondary: c.monto != null ? Text(currency.format(c.monto)) : null,
                ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _guardando ? null : () => _guardar(cotizacionesData),
                child: _guardando
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Crear ruta optimizada'),
              ),
            ],
          );
        }),
      ),
    );
  }
}
