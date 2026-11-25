import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../modulos/administracion_seguridad/presentacion/auth_providers.dart';
import '../modulos/administracion_seguridad/presentacion/login_pantalla.dart';
import '../modulos/administracion_seguridad/presentacion/panel_administrador.dart';
import '../modulos/administracion_seguridad/presentacion/splash_pantalla.dart';
import '../modulos/enrutamiento/presentacion/rutas_admin_pantallas.dart';
import '../modulos/enrutamiento/presentacion/rutas_chofer_pantalla.dart';
import '../modulos/gestion_comercial/dominio/cotizacion_importada.dart';
import '../modulos/gestion_comercial/presentacion/orden_detalle_pantalla.dart';
import '../modulos/gestion_comercial/presentacion/orden_form_pantalla.dart';
import '../modulos/logistico_notificaciones/presentacion/alertas_pantalla.dart';
import '../modulos/logistico_notificaciones/presentacion/chofer_inicio_pantalla.dart';
import '../modulos/logistico_notificaciones/presentacion/despacho_chofer_pantalla.dart';

class _RefrescoRouter extends ChangeNotifier {
  _RefrescoRouter(Ref ref) {
    ref.listen(sesionProvider, (_, _) => notifyListeners());
    ref.listen(usuarioActualProvider, (_, _) => notifyListeners());
  }
}

/// Navegación con control de acceso por rol (RBAC, RF-02): cada rol solo
/// puede abrir sus propias rutas (/admin o /chofer).
final routerProvider = Provider<GoRouter>((ref) {
  final refresco = _RefrescoRouter(ref);
  ref.onDispose(refresco.dispose);

  return GoRouter(
    initialLocation: '/splash',
    refreshListenable: refresco,
    redirect: (context, state) {
      final ubicacion = state.matchedLocation;
      if (ref.read(sesionProvider).isLoading && ref.read(usuarioIdProvider) == null) return null;

      if (ref.read(usuarioIdProvider) == null) {
        return ubicacion == '/login' ? null : '/login';
      }

      final usuario = ref.read(usuarioActualProvider);
      if (usuario.isLoading || usuario.hasError || usuario.value == null) {
        return ubicacion == '/splash' ? null : '/splash';
      }

      final inicio = usuario.value!.esAdministrador ? '/admin' : '/chofer';
      if (ubicacion == '/login' || ubicacion == '/splash') return inicio;
      if (!ubicacion.startsWith(inicio)) return inicio;
      return null;
    },
    routes: [
      GoRoute(path: '/splash', builder: (c, s) => const SplashPantalla()),
      GoRoute(path: '/login', builder: (c, s) => const LoginPantalla()),

      // --- Administrador (web/escritorio) ---
      GoRoute(path: '/admin', builder: (c, s) => const PanelAdministrador()),
      GoRoute(
        path: '/admin/ordenes/nueva',
        builder: (c, s) => OrdenFormPantalla(importada: s.extra as CotizacionImportada?),
      ),
      GoRoute(
        path: '/admin/ordenes/:id',
        builder: (c, s) => OrdenDetallePantalla(ordenId: s.pathParameters['id']!),
      ),
      GoRoute(
        path: '/admin/ordenes/:id/editar',
        builder: (c, s) => OrdenFormPantalla(ordenId: s.pathParameters['id']!),
      ),
      GoRoute(path: '/admin/rutas/nueva', builder: (c, s) => const RutaFormPantalla()),
      GoRoute(
        path: '/admin/rutas/:id',
        builder: (c, s) => RutaAdminPantalla(rutaId: s.pathParameters['id']!),
      ),

      // --- Chofer (app móvil) ---
      GoRoute(path: '/chofer', builder: (c, s) => const ChoferInicioPantalla()),
      GoRoute(
        path: '/chofer/despachos/:id',
        builder: (c, s) => DespachoChoferPantalla(despachoId: s.pathParameters['id']!),
      ),
      GoRoute(
        path: '/chofer/rutas/:id',
        builder: (c, s) => RutaChoferPantalla(rutaId: s.pathParameters['id']!),
      ),
      GoRoute(path: '/chofer/alertas', builder: (c, s) => const AlertasPantalla()),
    ],
  );
});
