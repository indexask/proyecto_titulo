import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'comercial_providers.dart';

/// Foto de un producto: desde Storage (ruta) o desde memoria (recién
/// extraída de una cotización). Si no hay foto, muestra un ícono.
class FotoProducto extends ConsumerWidget {
  final String? ruta;
  final Uint8List? bytes;
  final double tamano;

  const FotoProducto({super.key, this.ruta, this.bytes, this.tamano = 48});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    Widget contenido;
    if (bytes != null) {
      contenido = Image.memory(bytes!, fit: BoxFit.contain);
    } else if (ruta != null) {
      final url = ref.watch(urlFotoProductoProvider(ruta!));
      contenido = url.when(
        data: (u) => Image.network(u, fit: BoxFit.contain,
            errorBuilder: (_, _, _) => const Icon(Icons.broken_image)),
        loading: () => const Center(child: CircularProgressIndicator(strokeWidth: 2)),
        error: (_, _) => const Icon(Icons.broken_image),
      );
    } else {
      contenido = const Icon(Icons.inventory_2_outlined);
    }
    return SizedBox.square(
      dimension: tamano,
      child: ClipRRect(borderRadius: BorderRadius.circular(6), child: contenido),
    );
  }
}
