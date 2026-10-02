import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestamistas_rd/logic/graficas.dart';
import 'package:prestamistas_rd/screens/graficas_screen.dart';
import 'package:prestamistas_rd/widgets/graficas.dart';

void main() {
  final hoy = DateTime(2026, 9, 24, 15);
  final cobros = [
    for (var d = 0; d < 60; d++)
      CobroGrafica(
          prestamoId: 'p1',
          fecha: DateTime(2026, 9, 24 - d, 10),
          monto: 1250000,
          montoMora: d % 5 == 0 ? 40 : 0),
  ];
  final prestamos = [
    {'id': 'p1', 'monto': 10000, 'monto_total': 12000, 'estado': 'en_calle', 'fecha_desembolso': '2026-09-01'},
  ];

  Future<void> pintar(WidgetTester tester) async {
    tester.view.physicalSize = const Size(360, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData.dark(),
      home: Scaffold(
          body: ListView(
              padding: const EdgeInsets.all(16),
              children: contenidoGraficas(prestamos, cobros, hoy))),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('las gráficas caben en un teléfono con montos grandes', (tester) async {
    await pintar(tester);
    expect(find.text('Lo que entró cada día · últimos 30 días'), findsOneWidget);
    expect(find.text('Cómo está tu dinero en la calle'), findsOneWidget);
  });

  testWidgets('"Ver números" muestra la tabla y vuelve a la gráfica', (tester) async {
    await pintar(tester);
    await tester.tap(find.text('Ver números').first);
    await tester.pumpAndSettle();
    expect(find.text('24 sep'), findsWidgets);
    expect(find.text('Ver gráfica'), findsOneWidget);
    await tester.tap(find.text('Ver gráfica'));
    await tester.pumpAndSettle();
    expect(find.text('Ver gráfica'), findsNothing);
  });

  test('eje con números limpios', () {
    expect(ejeLimpio(3700), (tope: 4000.0, paso: 1000.0));
    expect(ejeLimpio(8800), (tope: 10000.0, paso: 2500.0));
    expect(ejeLimpio(0), (tope: 1000.0, paso: 250.0));
    expect(rdCorto(2500), '2.5K');
    expect(rdCorto(60000), '60K');
    expect(rdCorto(1200000), '1.2M');
    expect(rdCorto(500), '500');
  });
}
