import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/env.dart';
import 'core/router.dart';
import 'core/supabase_client.dart';
import 'modulos/logistico_notificaciones/datos/push_repositorio.dart';
import 'modulos/logistico_notificaciones/presentacion/push_servicio.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (Env.isConfigured) {
    await initSupabase();
    await PushRepositorio.inicializar();
  }
  runApp(const ProviderScope(child: App()));
}

class App extends ConsumerWidget {
  const App({super.key});

  static final _tema = ThemeData(
    colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1B5E8C)),
    inputDecorationTheme: const InputDecorationTheme(border: OutlineInputBorder()),
  );

  static const _localizaciones = [
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!Env.isConfigured) {
      return MaterialApp(theme: _tema, home: const _FaltaConfiguracion());
    }
    ref.watch(pushServicioProvider);
    return MaterialApp.router(
      title: 'GyGTrack',
      scaffoldMessengerKey: mensajeroGlobal,
      debugShowCheckedModeBanner: false,
      theme: _tema,
      locale: const Locale('es', 'CL'),
      supportedLocales: const [Locale('es', 'CL'), Locale('es')],
      localizationsDelegates: _localizaciones,
      routerConfig: ref.watch(routerProvider),
    );
  }
}

class _FaltaConfiguracion extends StatelessWidget {
  const _FaltaConfiguracion();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Faltan las variables de entorno de Supabase.\n\n'
            'Corre la app con:\n'
            'flutter run --dart-define-from-file=env/dev.json',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}
