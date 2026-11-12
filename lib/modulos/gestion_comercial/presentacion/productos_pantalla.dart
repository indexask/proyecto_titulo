import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errores.dart';
import '../../../core/formato.dart';
import '../../../core/widgets/vista_async.dart';
import '../dominio/producto.dart';
import 'comercial_providers.dart';
import 'foto_producto.dart';

/// Catálogo de productos y sus costos (RF-11).
class ProductosLista extends ConsumerWidget {
  const ProductosLista({super.key});

  Future<void> _editar(BuildContext context, WidgetRef ref, [Producto? p]) async {
    final guardado = await showDialog<bool>(
      context: context,
      builder: (_) => _DialogoProducto(producto: p),
    );
    if (guardado == true) ref.invalidate(productosProvider);
  }

  Future<void> _eliminar(BuildContext context, WidgetRef ref, Producto p) async {
    try {
      await ref.read(productosRepositorioProvider).eliminar(p.id);
      ref.invalidate(productosProvider);
    } catch (e) {
      if (context.mounted) {
        mostrarMensaje(context, 'No se pudo eliminar (¿está usado en alguna orden?): ${mensajeError(e)}');
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(productosProvider);
    return Scaffold(
      body: VistaAsync(
        cargando: async.isLoading,
        error: async.error,
        onReintentar: () => ref.invalidate(productosProvider),
        child: Builder(builder: (context) {
          final productos = async.value ?? const <Producto>[];
          if (productos.isEmpty) {
            return const Center(child: Text('El catálogo está vacío.'));
          }
          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: productos.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final p = productos[i];
              return ListTile(
                leading: FotoProducto(ruta: p.fotoPath),
                title: Text(p.nombre),
                subtitle: Text('Costo ${formatoClp(p.costoCompra)} · Precio ${formatoClp(p.precioVenta)}'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Margen ${formatoClp(p.margenUnitario)}'),
                    PopupMenuButton<String>(
                      onSelected: (accion) =>
                          accion == 'editar' ? _editar(context, ref, p) : _eliminar(context, ref, p),
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: 'editar', child: Text('Editar')),
                        PopupMenuItem(value: 'eliminar', child: Text('Eliminar')),
                      ],
                    ),
                  ],
                ),
                onTap: () => _editar(context, ref, p),
              );
            },
          );
        }),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _editar(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('Nuevo producto'),
      ),
    );
  }
}

class _DialogoProducto extends ConsumerStatefulWidget {
  final Producto? producto;

  const _DialogoProducto({this.producto});

  @override
  ConsumerState<_DialogoProducto> createState() => _DialogoProductoState();
}

class _DialogoProductoState extends ConsumerState<_DialogoProducto> {
  final _formKey = GlobalKey<FormState>();
  late final _nombre = TextEditingController(text: widget.producto?.nombre);
  late final _costo = TextEditingController(
      text: widget.producto == null ? '' : textoMonto(widget.producto!.costoCompra));
  late final _precio = TextEditingController(
      text: widget.producto == null ? '' : textoMonto(widget.producto!.precioVenta));
  bool _guardando = false;

  @override
  void dispose() {
    _nombre.dispose();
    _costo.dispose();
    _precio.dispose();
    super.dispose();
  }

  String? _validarMonto(String? v) {
    final n = parsearMonto(v ?? '');
    return (n == null || n < 0) ? 'Monto inválido' : null;
  }

  Future<void> _guardar() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _guardando = true);
    try {
      await ref.read(productosRepositorioProvider).guardar(
            id: widget.producto?.id,
            nombre: _nombre.text.trim(),
            costoCompra: parsearMonto(_costo.text)!,
            precioVenta: parsearMonto(_precio.text)!,
          );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) mostrarMensaje(context, mensajeError(e));
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.producto == null ? 'Nuevo producto' : 'Editar producto'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _nombre,
              decoration: const InputDecoration(labelText: 'Nombre'),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Requerido' : null,
            ),
            TextFormField(
              controller: _costo,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Costo de compra'),
              validator: _validarMonto,
            ),
            TextFormField(
              controller: _precio,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Precio de venta referencial'),
              validator: _validarMonto,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
        FilledButton(onPressed: _guardando ? null : _guardar, child: const Text('Guardar')),
      ],
    );
  }
}
