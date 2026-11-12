import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../enrutamiento/presentacion/rutas_admin_pantallas.dart';
import '../../gestion_comercial/presentacion/ordenes_lista_pantalla.dart';
import '../../gestion_comercial/presentacion/productos_pantalla.dart';
import '../../gestion_comercial/presentacion/utilidad_pantalla.dart';
import '../../logistico_notificaciones/presentacion/alertas_pantalla.dart';
import 'auth_providers.dart';
import 'cerrar_sesion.dart';

typedef _Seccion = ({String titulo, IconData icono, Widget contenido});

/// Panel de control del Administrador (web/escritorio). Agrupa las
/// funciones de los módulos que solo él puede usar (RBAC, RF-02).
class PanelAdministrador extends ConsumerStatefulWidget {
  const PanelAdministrador({super.key});

  @override
  ConsumerState<PanelAdministrador> createState() => _PanelAdministradorState();
}

class _PanelAdministradorState extends ConsumerState<PanelAdministrador> {
  int _indice = 0;

  static const List<_Seccion> _secciones = [
    (titulo: 'Órdenes', icono: Icons.receipt_long, contenido: OrdenesLista()),
    (titulo: 'Utilidad', icono: Icons.bar_chart, contenido: UtilidadPanel()),
    (titulo: 'Productos', icono: Icons.inventory, contenido: ProductosLista()),
    (titulo: 'Rutas', icono: Icons.route, contenido: RutasAdminLista()),
    (titulo: 'Alertas', icono: Icons.notifications, contenido: AlertasLista()),
  ];

  @override
  Widget build(BuildContext context) {
    final usuario = ref.watch(usuarioActualProvider).value;
    final ancho = MediaQuery.sizeOf(context).width >= 800;
    final seccion = _secciones[_indice];

    return Scaffold(
      appBar: AppBar(
        title: Text('GyGTrack · ${seccion.titulo}'),
        actions: [
          if (usuario != null && ancho)
            Center(child: Text(usuario.nombreVisible)),
          const BotonCerrarSesion(),
        ],
      ),
      body: Row(
        children: [
          if (ancho)
            NavigationRail(
              selectedIndex: _indice,
              labelType: NavigationRailLabelType.all,
              onDestinationSelected: (i) => setState(() => _indice = i),
              destinations: [
                for (final s in _secciones)
                  NavigationRailDestination(icon: Icon(s.icono), label: Text(s.titulo)),
              ],
            ),
          Expanded(child: seccion.contenido),
        ],
      ),
      bottomNavigationBar: ancho
          ? null
          : NavigationBar(
              selectedIndex: _indice,
              onDestinationSelected: (i) => setState(() => _indice = i),
              destinations: [
                for (final s in _secciones) NavigationDestination(icon: Icon(s.icono), label: s.titulo),
              ],
            ),
    );
  }
}
