import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gygtrack/main.dart';

void main() {
  testWidgets('Muestra el mensaje de configuración cuando faltan las variables de entorno',
      (tester) async {
    await tester.pumpWidget(const ProviderScope(child: App()));
    await tester.pumpAndSettle();
    expect(find.textContaining('Faltan las variables de entorno'), findsOneWidget);
  });
}
