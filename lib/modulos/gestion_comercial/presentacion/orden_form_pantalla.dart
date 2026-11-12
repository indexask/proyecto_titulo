import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/errores.dart';
import '../../../core/formato.dart';
import '../../../core/widgets/vista_async.dart';
import '../../administracion_seguridad/presentacion/auth_providers.dart';
import '../../enrutamiento/presentacion/enrutamiento_providers.dart';
import '../dominio/orden_compra.dart';
import '../dominio/producto.dart';
import '../dominio/rentabilidad.dart';
import 'comercial_providers.dart';

/// Registro / edición de una adjudicación (RF-05, RF-06, RF-09, RF-10).
/// El margen neto se calcula al instante mientras se ingresan costos y
/// precios (RF-07, KPI-03).
class OrdenFormPantalla extends ConsumerWidget {
  final String? ordenId;

  const OrdenFormPantalla({super.key, this.ordenId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final productos = ref.watch(productosProvider);
    final usuarios = ref.watch(usuariosProvider);
    final orden = ordenId == null ? null : ref.watch(ordenProvider(ordenId!));

    final cargando = productos.isLoading || usuarios.isLoading || (orden?.isLoading ?? false);
    final error = productos.error ?? usuarios.error ?? orden?.error;

    return Scaffold(
      appBar: AppBar(title: Text(ordenId == null ? 'Registrar adjudicación' : 'Editar orden')),
      body: VistaAsync(
        cargando: cargando,
        error: error,
        onReintentar: () {
          ref.invalidate(productosProvider);
          ref.invalidate(usuariosProvider);
          if (ordenId != null) ref.invalidate(ordenProvider(ordenId!));
        },
        child: cargando || error != null
            ? const SizedBox.shrink()
            : _Formulario(
                productos: productos.value!,
                orden: orden?.value,
              ),
      ),
    );
  }
}

class _LineaForm implements LineaConMargen {
  Producto? producto;
  final cantidadCtrl = TextEditingController(text: '1');
  final costoCtrl = TextEditingController();
  final precioCtrl = TextEditingController();

  _LineaForm();

  _LineaForm.desde(DetalleOrden d, List<Producto> catalogo) {
    producto = catalogo.where((p) => p.id == d.productoId).firstOrNull;
    cantidadCtrl.text = '${d.cantidad}';
    costoCtrl.text = textoMonto(d.costoCompra);
    precioCtrl.text = textoMonto(d.precioVenta);
  }

  void elegir(Producto p) {
    producto = p;
    costoCtrl.text = textoMonto(p.costoCompra);
    precioCtrl.text = textoMonto(p.precioVenta);
  }

  @override
  num get cantidad => int.tryParse(cantidadCtrl.text.trim()) ?? 0;
  @override
  num get costoCompra => parsearMonto(costoCtrl.text) ?? 0;
  @override
  num get precioVenta => parsearMonto(precioCtrl.text) ?? 0;

  bool get completa =>
      producto != null &&
      cantidad > 0 &&
      parsearMonto(costoCtrl.text) != null &&
      parsearMonto(precioCtrl.text) != null;

  DetalleOrden aDetalle() => DetalleOrden(
        productoId: producto!.id,
        productoNombre: producto!.nombre,
        cantidad: cantidad.toInt(),
        costoCompra: costoCompra,
        precioVenta: precioVenta,
      );

  void dispose() {
    cantidadCtrl.dispose();
    costoCtrl.dispose();
    precioCtrl.dispose();
  }
}

class _Formulario extends ConsumerStatefulWidget {
  final List<Producto> productos;
  final OrdenCompra? orden;

  const _Formulario({required this.productos, required this.orden});

  @override
  ConsumerState<_Formulario> createState() => _FormularioState();
}

class _FormularioState extends ConsumerState<_Formulario> {
  final _formKey = GlobalKey<FormState>();
  final _numeroCtrl = TextEditingController();
  final _clienteCtrl = TextEditingController();
  final _direccionCtrl = TextEditingController();
  late DateTime _fechaComprometida;
  String? _responsableId;
  double? _lat;
  double? _lng;
  final _lineas = <_LineaForm>[];
  bool _geocodificando = false;
  bool _guardando = false;

  @override
  void initState() {
    super.initState();
    final o = widget.orden;
    _numeroCtrl.text = o?.numeroOc ?? '';
    _clienteCtrl.text = o?.cliente ?? '';
    _direccionCtrl.text = o?.direccionEntrega ?? '';
    _lat = o?.direccionLat;
    _lng = o?.direccionLng;
    _fechaComprometida = o?.fechaComprometida ?? hoy().add(const Duration(days: 7));
    _responsableId = o?.responsableId;
    _lineas.addAll(o?.detalles.map((d) => _LineaForm.desde(d, widget.productos)) ?? const []);
    if (_lineas.isEmpty) _lineas.add(_LineaForm());
  }

  @override
  void dispose() {
    _numeroCtrl.dispose();
    _clienteCtrl.dispose();
    _direccionCtrl.dispose();
    for (final l in _lineas) {
      l.dispose();
    }
    super.dispose();
  }

  Future<void> _validarDireccion() async {
    if (_direccionCtrl.text.trim().isEmpty) return;
    setState(() => _geocodificando = true);
    try {
      final r = await ref.read(geocodificacionRepositorioProvider).geocodificar(_direccionCtrl.text.trim());
      setState(() {
        _direccionCtrl.text = r.direccion;
        _lat = r.lat;
        _lng = r.lng;
      });
    } catch (e) {
      if (mounted) mostrarMensaje(context, mensajeError(e));
    } finally {
      if (mounted) setState(() => _geocodificando = false);
    }
  }

  Future<void> _guardar() async {
    if (!_formKey.currentState!.validate()) return;
    final lineas = _lineas.where((l) => l.producto != null).toList();
    if (lineas.isEmpty) return mostrarMensaje(context, 'Agrega al menos un producto');
    if (lineas.any((l) => !l.completa)) {
      return mostrarMensaje(context, 'Completa cantidad, costo y precio de cada producto');
    }

    setState(() => _guardando = true);
    try {
      final id = await ref.read(ordenesRepositorioProvider).guardar(
            id: widget.orden?.id,
            numeroOc: _numeroCtrl.text.trim(),
            cliente: _clienteCtrl.text.trim(),
            direccionEntrega: _direccionCtrl.text.trim(),
            direccionLat: _lat,
            direccionLng: _lng,
            fechaComprometida: _fechaComprometida,
            responsableId: _responsableId,
            detalles: lineas.map((l) => l.aDetalle()).toList(),
          );
      ref.invalidate(ordenesProvider);
      ref.invalidate(ordenProvider(id));
      if (!mounted) return;
      if (widget.orden == null) {
        context.pushReplacement('/admin/ordenes/$id');
      } else {
        context.pop();
      }
    } catch (e) {
      if (mounted) mostrarMensaje(context, mensajeError(e));
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final usuarios = ref.watch(usuariosProvider).value ?? const [];
    final lineasValidas = _lineas.where((l) => l.producto != null);
    final margen = calcularMargenNeto(lineasValidas);
    final venta = calcularVentaTotal(lineasValidas);
    final pct = porcentajeMargen(margen, venta);
    final tema = Theme.of(context);

    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Datos de la adjudicación', style: tema.textTheme.titleMedium),
          const SizedBox(height: 8),
          TextFormField(
            controller: _numeroCtrl,
            decoration: const InputDecoration(labelText: 'N° de orden de compra (Mercado Público)'),
          ),
          TextFormField(
            controller: _clienteCtrl,
            decoration: const InputDecoration(labelText: 'Cliente (organismo público)'),
            validator: (v) => (v == null || v.trim().isEmpty) ? 'Requerido' : null,
          ),
          TextFormField(
            controller: _direccionCtrl,
            decoration: InputDecoration(
              labelText: 'Dirección de entrega',
              helperText: _lat == null
                  ? 'Valídala para poder incluirla en una ruta'
                  : 'Dirección validada ✓',
              suffixIcon: _geocodificando
                  ? const Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator(strokeWidth: 2))
                  : IconButton(
                      tooltip: 'Validar dirección',
                      icon: const Icon(Icons.travel_explore),
                      onPressed: _validarDireccion,
                    ),
            ),
            validator: (v) => (v == null || v.trim().isEmpty) ? 'Requerido' : null,
            onChanged: (_) => setState(() => _lat = _lng = null),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.event),
            title: Text('Plazo de entrega: ${formatoFecha(_fechaComprometida)}'),
            trailing: const Icon(Icons.edit_calendar),
            onTap: () async {
              final f = await showDatePicker(
                context: context,
                initialDate: _fechaComprometida,
                firstDate: DateTime(2024),
                lastDate: DateTime(2100),
              );
              if (f != null) setState(() => _fechaComprometida = f);
            },
          ),
          DropdownButtonFormField<String?>(
            initialValue: _responsableId,
            decoration: const InputDecoration(labelText: 'Responsable'),
            items: [
              const DropdownMenuItem(value: null, child: Text('Sin asignar')),
              for (final u in usuarios)
                DropdownMenuItem(
                  value: u.id,
                  child: Text('${u.nombreVisible} (${u.esAdministrador ? 'Administrador' : 'Chofer'})'),
                ),
            ],
            onChanged: (v) => setState(() => _responsableId = v),
          ),
          const Divider(height: 32),
          Text('Productos, costos y precios adjudicados', style: tema.textTheme.titleMedium),
          if (widget.productos.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text('Primero registra productos en el catálogo.'),
            ),
          for (final (i, linea) in _lineas.indexed) _filaLinea(i, linea),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => setState(() => _lineas.add(_LineaForm())),
              icon: const Icon(Icons.add),
              label: const Text('Agregar producto'),
            ),
          ),
          const SizedBox(height: 8),
          Card(
            color: margen < 0 ? tema.colorScheme.errorContainer : tema.colorScheme.primaryContainer,
            child: ListTile(
              leading: const Icon(Icons.trending_up),
              title: Text('Margen neto: ${formatoClp(margen)}',
                  style: tema.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
              subtitle: Text('Venta total ${formatoClp(venta)}'
                  '${pct == null ? '' : ' · ${pct.toStringAsFixed(1)} % de margen'}'),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _guardando ? null : _guardar,
            child: _guardando
                ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Guardar orden'),
          ),
        ],
      ),
    );
  }

  Widget _filaLinea(int indice, _LineaForm linea) {
    InputDecoration deco(String etiqueta) => InputDecoration(labelText: etiqueta, isDense: true);
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: linea.producto?.id,
                    isExpanded: true,
                    decoration: deco('Producto'),
                    items: [
                      for (final p in widget.productos) DropdownMenuItem(value: p.id, child: Text(p.nombre)),
                    ],
                    onChanged: (id) => setState(
                        () => linea.elegir(widget.productos.firstWhere((p) => p.id == id))),
                  ),
                ),
                IconButton(
                  tooltip: 'Quitar',
                  icon: const Icon(Icons.close),
                  onPressed: () => setState(() => _lineas.removeAt(indice).dispose()),
                ),
              ],
            ),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: linea.cantidadCtrl,
                    keyboardType: TextInputType.number,
                    decoration: deco('Cantidad'),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextFormField(
                    controller: linea.costoCtrl,
                    keyboardType: TextInputType.number,
                    decoration: deco('Costo compra'),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextFormField(
                    controller: linea.precioCtrl,
                    keyboardType: TextInputType.number,
                    decoration: deco('Precio adjudicado'),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              ],
            ),
            if (linea.producto != null)
              Align(
                alignment: Alignment.centerRight,
                child: Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text('Margen línea: ${formatoClp(margenDeLinea(linea))}'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
