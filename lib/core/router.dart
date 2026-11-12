import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../models/profile.dart';
import '../providers/auth_provider.dart';
import '../screens/auth/login_screen.dart';
import '../screens/auth/register_screen.dart';
import '../screens/auth/splash_screen.dart';
import '../screens/cotizaciones/cotizacion_detail_screen.dart';
import '../screens/cotizaciones/cotizacion_form_screen.dart';
import '../screens/home/admin_home_screen.dart';
import '../screens/home/chofer_home_screen.dart';
import '../screens/rutas/ruta_form_screen.dart';
import '../screens/rutas/ruta_map_screen.dart';

class _RouterRefresh extends ChangeNotifier {
  _RouterRefresh(Ref ref) {
    ref.listen(authStateProvider, (_, _) => notifyListeners());
    ref.listen(profileProvider, (_, _) => notifyListeners());
  }
}

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = _RouterRefresh(ref);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    initialLocation: '/splash',
    refreshListenable: refresh,
    redirect: (context, state) {
      final authState = ref.read(authStateProvider);
      final loc = state.matchedLocation;

      if (authState.isLoading) return null;

      final session = ref.read(currentUserIdProvider);
      if (session == null) {
        return loc == '/login' || loc == '/register' ? null : '/login';
      }

      final profileAsync = ref.read(profileProvider);
      if (profileAsync.isLoading) return '/splash';

      final profile = profileAsync.value;
      if (profile == null) return null;

      final home = profile.role == UserRole.admin ? '/admin' : '/chofer';
      final onAuthScreens =
          loc == '/login' || loc == '/register' || loc == '/splash';
      if (onAuthScreens) return home;

      if (profile.role != UserRole.admin && loc.startsWith('/admin')) {
        return home;
      }
      return null;
    },
    routes: [
      GoRoute(path: '/splash', builder: (c, s) => const SplashScreen()),
      GoRoute(path: '/login', builder: (c, s) => const LoginScreen()),
      GoRoute(path: '/register', builder: (c, s) => const RegisterScreen()),
      GoRoute(path: '/admin', builder: (c, s) => const AdminHomeScreen()),
      GoRoute(
        path: '/admin/cotizaciones/nueva',
        builder: (c, s) => const CotizacionFormScreen(),
      ),
      GoRoute(
        path: '/admin/cotizaciones/:id',
        builder: (c, s) =>
            CotizacionDetailScreen(cotizacionId: s.pathParameters['id']!),
      ),
      GoRoute(
        path: '/admin/rutas/nueva',
        builder: (c, s) => const RutaFormScreen(),
      ),
      GoRoute(
        path: '/admin/rutas/:id',
        builder: (c, s) => RutaMapScreen(rutaId: s.pathParameters['id']!),
      ),
      GoRoute(path: '/chofer', builder: (c, s) => const ChoferHomeScreen()),
      GoRoute(
        path: '/chofer/rutas/:id',
        builder: (c, s) => RutaMapScreen(rutaId: s.pathParameters['id']!),
      ),
    ],
  );
});
