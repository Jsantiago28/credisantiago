import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestamistas_rd/screens/mi_recibo_screen.dart';

void main() {
  testWidgets('Mi recibo cabe en un teléfono y trae lo guardado', (tester) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData.dark(),
      home: MiReciboScreen(perfil: {
        'id': 'abc',
        'nombre': 'Mitchell Castillo',
        'negocio': 'Inversiones Castillo',
        'whatsapp': '809-555-1234',
        'recibo_mensaje': 'Pague a tiempo y evite mora',
      }),
    ));

    expect(find.text('Inversiones Castillo'), findsOneWidget);
    expect(find.text('Pague a tiempo y evite mora'), findsOneWidget);
    expect(find.text('Poner logo'), findsOneWidget);
    expect(find.textContaining('sale tu WhatsApp (809-555-1234)'), findsOneWidget);

    await tester.scrollUntilVisible(find.text('Guardar'), 200,
        scrollable: find.byType(Scrollable).first);
    expect(find.text('Ver cómo queda'), findsOneWidget);
  });

  test('recibo de ejemplo', () {
    final r = reciboDeEjemplo(DateTime(2026, 9, 29));
    expect(r.cubre, ['Cuota #3 (29/9/2026)']);
    expect(r.proximoPagoFecha, DateTime(2026, 10, 6));
    expect(r.saldado, isFalse);
  });
}
