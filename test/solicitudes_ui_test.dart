import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestamistas_rd/screens/solicitudes_screen.dart';

Future<void> abrir(WidgetTester tester, List<Map<String, dynamic>> nuevas) async {
  tester.view.physicalSize = const Size(400, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    theme: ThemeData.dark(),
    home: SolicitudesScreen(
        prestamistaId: 'yo', nuevas: nuevas, error: null, onReintentar: () {}),
  ));
  await tester.pump();
}

void main() {
  testWidgets('sin solicitudes: botón para compartir el link', (tester) async {
    await abrir(tester, const []);
    expect(find.text('Compartir mi link'), findsOneWidget);
    expect(find.textContaining('desde Perfil'), findsNothing);
  });

  testWidgets('rechazar pide confirmar y se puede cancelar', (tester) async {
    await abrir(tester, [
      {
        'id': 's1',
        'nombre': 'Ana Gómez',
        'telefono': '8095551234',
        'monto_solicitado': 5000,
        'created_at': DateTime.now().toIso8601String(),
      }
    ]);
    await tester.tap(find.text('Rechazar'));
    await tester.pumpAndSettle();
    expect(find.text('¿Rechazar a Ana Gómez?'), findsOneWidget);

    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(find.text('¿Rechazar a Ana Gómez?'), findsNothing);
    expect(find.text('Ana Gómez rechazado.'), findsNothing);
  });
}
