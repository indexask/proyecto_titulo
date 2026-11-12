import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/env.dart';
import 'core/router.dart';
import 'core/supabase_client.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (Env.isConfigured) {
    await initSupabase();
  }
  runApp(const ProviderScope(child: App()));
}

class App extends ConsumerWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!Env.isConfigured) {
      return const MaterialApp(home: _MissingEnvScreen());
    }

    final router = ref.watch(routerProvider);
    return MaterialApp.router(
      title: 'Cotizaciones y Rutas',
      theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo)),
      routerConfig: router,
    );
  }
}

class _MissingEnvScreen extends StatelessWidget {
  const _MissingEnvScreen();

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
