import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/auth_provider.dart';
import '../cotizaciones/cotizaciones_list_screen.dart';
import '../rutas/rutas_list_screen.dart';

class AdminHomeScreen extends ConsumerWidget {
  const AdminHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Panel administrador'),
          bottom: const TabBar(tabs: [
            Tab(text: 'Cotizaciones'),
            Tab(text: 'Rutas'),
          ]),
          actions: [
            IconButton(
              icon: const Icon(Icons.logout),
              onPressed: () => ref.read(authServiceProvider).signOut(),
            ),
          ],
        ),
        body: const TabBarView(children: [
          CotizacionesListScreen(),
          RutasListScreen(),
        ]),
      ),
    );
  }
}
