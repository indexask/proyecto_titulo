import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geocoding/geocoding.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../providers/cotizaciones_provider.dart';

class CotizacionFormScreen extends ConsumerStatefulWidget {
  const CotizacionFormScreen({super.key});

  @override
  ConsumerState<CotizacionFormScreen> createState() =>
      _CotizacionFormScreenState();
}

class _CotizacionFormScreenState extends ConsumerState<CotizacionFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _tituloCtrl = TextEditingController();
  final _numeroCtrl = TextEditingController();
  final _clienteCtrl = TextEditingController();
  final _direccionCtrl = TextEditingController();
  final _descripcionCtrl = TextEditingController();
  final _unidadesCtrl = TextEditingController();
  final _precioUnidadCtrl = TextEditingController();
  final _totalCtrl = TextEditingController();

  DateTime? _fecha;
  File? _pdf;
  String? _pdfNombre;
  File? _foto;
  bool _extrayendo = false;
  bool _guardando = false;

  @override
  void dispose() {
    _tituloCtrl.dispose();
    _numeroCtrl.dispose();
    _clienteCtrl.dispose();
    _direccionCtrl.dispose();
    _descripcionCtrl.dispose();
    _unidadesCtrl.dispose();
    _precioUnidadCtrl.dispose();
    _totalCtrl.dispose();
    super.dispose();
  }

  Future<void> _elegirPdf() async {
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );
    if (file == null || file.path == null) return;
    setState(() {
      _pdf = File(file.path!);
      _pdfNombre = file.name;
    });
    await _extraerDatos();
  }

  Future<void> _extraerDatos() async {
    if (_pdf == null) return;
    setState(() => _extrayendo = true);
    try {
      final datos =
          await ref.read(cotizacionesServiceProvider).extraerDesdePdf(_pdf!);
      setState(() {
        _numeroCtrl.text = (datos['numero_cotizacion'] as String?) ?? '';
        _clienteCtrl.text = (datos['solicitado_por'] as String?) ?? '';
        _direccionCtrl.text = (datos['direccion_entrega'] as String?) ?? '';
        _descripcionCtrl.text = (datos['descripcion'] as String?) ?? '';
        _unidadesCtrl.text = datos['unidades']?.toString() ?? '';
        _precioUnidadCtrl.text = datos['precio_unidad']?.toString() ?? '';
        _totalCtrl.text = datos['total']?.toString() ?? '';
        _tituloCtrl.text = _numeroCtrl.text.isNotEmpty
            ? 'Cotización ${_numeroCtrl.text}'
            : (_descripcionCtrl.text.isNotEmpty
                ? _descripcionCtrl.text.split('\n').first
                : '');
        final fechaStr = datos['fecha_cotizacion'] as String?;
        _fecha = fechaStr != null ? DateTime.tryParse(fechaStr) : null;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Datos extraídos. Revisa y corrige si es necesario.'),
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo extraer el PDF: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _extrayendo = false);
    }
  }

  Future<void> _elegirFoto() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (picked == null) return;
    setState(() => _foto = File(picked.path));
  }

  Future<void> _elegirFecha() async {
    final fecha = await showDatePicker(
      context: context,
      initialDate: _fecha ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (fecha != null) setState(() => _fecha = fecha);
  }

  Future<void> _guardar() async {
    if (!_formKey.currentState!.validate()) return;
    if (_pdf == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Adjunta el PDF de la cotización')),
      );
      return;
    }
    if (_direccionCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ingresa la dirección de entrega')),
      );
      return;
    }

    setState(() => _guardando = true);
    try {
      final ubicaciones =
          await Geocoding().locationFromAddress(_direccionCtrl.text.trim());
      if (ubicaciones.isEmpty) {
        throw Exception('No se encontró la dirección de entrega');
      }
      final loc = ubicaciones.first;

      await ref.read(cotizacionesServiceProvider).crear(
            titulo: _tituloCtrl.text.trim(),
            cliente: _clienteCtrl.text.trim(),
            monto: num.tryParse(_totalCtrl.text.trim()),
            pdf: _pdf!,
            foto: _foto,
            numeroCotizacion: _numeroCtrl.text.trim().isEmpty
                ? null
                : _numeroCtrl.text.trim(),
            fechaCotizacion: _fecha,
            direccionEntrega: _direccionCtrl.text.trim(),
            direccionLat: loc.latitude,
            direccionLng: loc.longitude,
            descripcion: _descripcionCtrl.text.trim().isEmpty
                ? null
                : _descripcionCtrl.text.trim(),
            unidades: num.tryParse(_unidadesCtrl.text.trim()),
            precioUnidad: num.tryParse(_precioUnidadCtrl.text.trim()),
          );
      ref.invalidate(cotizacionesListProvider);
      ref.invalidate(cotizacionesSinRutaProvider);
      if (mounted) context.pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('dd-MM-yyyy');

    return Scaffold(
      appBar: AppBar(title: const Text('Subir cotización adjudicada')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              OutlinedButton.icon(
                onPressed: _extrayendo ? null : _elegirPdf,
                icon: const Icon(Icons.picture_as_pdf),
                label: Text(_pdfNombre ?? 'Adjuntar PDF de cotización'),
              ),
              if (_extrayendo) ...[
                const SizedBox(height: 12),
                const LinearProgressIndicator(),
                const SizedBox(height: 4),
                const Text('Extrayendo datos con IA...',
                    style: TextStyle(fontSize: 12, color: Colors.grey)),
              ],
              if (_pdf != null && !_extrayendo) ...[
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: _extraerDatos,
                  icon: const Icon(Icons.auto_awesome),
                  label: const Text('Volver a extraer datos'),
                ),
              ],
              const Divider(height: 32),
              TextFormField(
                controller: _tituloCtrl,
                decoration: const InputDecoration(labelText: 'Título'),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Requerido' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _numeroCtrl,
                decoration: const InputDecoration(labelText: 'N° de cotización'),
              ),
              const SizedBox(height: 16),
              InkWell(
                onTap: _elegirFecha,
                child: InputDecorator(
                  decoration: const InputDecoration(labelText: 'Fecha de cotización'),
                  child: Text(_fecha != null ? dateFormat.format(_fecha!) : '—'),
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _clienteCtrl,
                decoration: const InputDecoration(labelText: 'Solicitado por (cliente)'),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _direccionCtrl,
                decoration: const InputDecoration(
                  labelText: 'Dirección de entrega',
                  helperText: 'Se usará como punto de la ruta',
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Requerido' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _descripcionCtrl,
                maxLines: 3,
                decoration: const InputDecoration(labelText: 'Descripción'),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _unidadesCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Unidades'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _precioUnidadCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Precio unidad'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _totalCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Total'),
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: _elegirFoto,
                icon: const Icon(Icons.photo),
                label: Text(_foto != null ? 'Foto seleccionada' : 'Foto del producto (opcional)'),
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _guardando ? null : _guardar,
                child: _guardando
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Guardar cotización'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
