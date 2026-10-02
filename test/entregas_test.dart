import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestamistas_rd/logic/caja.dart';
import 'package:prestamistas_rd/screens/caja_screen.dart';
import 'package:prestamistas_rd/screens/cobrador_shell.dart';

import 'cobradores_test.dart' show diaConCobradores, juan, pedro;

void main() {
  test('caja por cobrador: cada quien, sin anulados; el prestamista al final', () {
    final filas = cajaPorCobrador(diaConCobradores());
    expect(filas.map((f) => f.cobradorId), ['c1', 'c2', null]);
    expect(filas.map((f) => f.total), [2500, 800, 3000]);
    expect(filas.map((f) => f.cantidad), [2, 1, 1]);
    expect(filas.first.mora, 100);
  });

  test('cuadre: cuadra, falta o sobra (los centavos no cuentan)', () {
    expect(cuadre(cobrado: 2500, entregado: 2500).texto, 'Cuadra');
    expect(cuadre(cobrado: 2500, entregado: 2500.4).diferencia, 0);
    final falta = cuadre(cobrado: 2500, entregado: 2000);
    expect(falta.texto, 'Falta RD\$500');
    expect(falta.diferencia, -500);
    expect(cuadre(cobrado: 2500, entregado: 2600).texto, 'Sobra RD\$100');
  });

  test('lee la entrega de Supabase', () {
    final e = Entrega.desdeFila({
      'id': 'e1',
      'cobrador_id': 'c1',
      'fecha': '2026-09-30',
      'cobrado': 2500,
      'entregado': 2000,
      'nota': 'mañana trae el resto',
    });
    expect(e.fecha, DateTime(2026, 9, 30));
    expect(e.entregado, 2000);
    expect(e.nota, 'mañana trae el resto');
  });

  test('el resumen por WhatsApp dice cuánto cobró cada quien', () {
    final texto = resumenCajaTexto(diaConCobradores(),
        negocio: 'Inversiones Castillo', nombresCobradores: {'c1': 'Juan Pérez', 'c2': 'Pedro Díaz'});
    expect(texto, contains('Por cobrador:'));
    expect(texto, contains('• Juan Pérez: RD\$2,500 (2)'));
    expect(texto, contains('• Pedro Díaz: RD\$800 (1)'));
    expect(texto, contains('• Yo: RD\$3,000 (1)'));
    // Sin cobradores, el resumen queda como antes.
    final solo = cajaPorDia([
      CobroCaja(fecha: DateTime(2026, 9, 30, 8), monto: 1000, cliente: 'Ana'),
    ]).single;
    expect(resumenCajaTexto(solo, negocio: 'X'), isNot(contains('Por cobrador')));
  });

  testWidgets('caja del día: por cobrador, con la entrega y si cuadra', (tester) async {
    tester.view.physicalSize = const Size(360, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData.dark(),
      home: CajaDiaScreen(
        prestamistaId: 'p1',
        dia: diaConCobradores(),
        cierre: null,
        gastos: const [],
        cobradores: const [juan, pedro],
        entregas: {
          'c1': Entrega(
              cobradorId: 'c1', fecha: DateTime(2026, 9, 30), cobrado: 2500, entregado: 2000),
          // Pedro entregó antes de que se anulara un cobro: avisa del cambio.
          'c2': Entrega(
              cobradorId: 'c2', fecha: DateTime(2026, 9, 30), cobrado: 10799, entregado: 800),
        },
      ),
    ));
    expect(tester.takeException(), isNull);
    expect(find.text('Por cobrador'), findsOneWidget);
    expect(find.text('Juan Pérez'), findsOneWidget);
    expect(find.text('Te entregó RD\$2,000 · Falta RD\$500'), findsOneWidget);
    expect(find.text('Te entregó RD\$800 · Cuadra'), findsOneWidget);
    expect(find.textContaining('Cuando te entregó había cobrado RD\$10,799'), findsOneWidget);
    expect(find.text('Tú'), findsOneWidget);

    // Tocar a Juan abre el cuadre con lo que entregó.
    await tester.tap(find.text('Juan Pérez'));
    await tester.pumpAndSettle();
    expect(find.text('Entrega de Juan'), findsOneWidget);
    expect(find.text('Falta RD\$500'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextField, '2000'), '2500');
    await tester.pump();
    expect(find.text('Cuadra'), findsOneWidget);
  });

  testWidgets('sin cobradores no sale la sección', (tester) async {
    tester.view.physicalSize = const Size(360, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final dia = cajaPorDia([
      CobroCaja(fecha: DateTime(2026, 9, 30, 8), monto: 1000, cliente: 'Ana'),
    ]).single;
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData.dark(),
      home: CajaDiaScreen(
          prestamistaId: 'p1', dia: dia, cierre: null, gastos: const [], cobradores: const []),
    ));
    expect(find.text('Por cobrador'), findsNothing);
  });

  testWidgets('mi caja del cobrador: dice si el jefe ya recibió', (tester) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final ahora = DateTime.now();
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData.dark(),
      home: MiCajaCobrador(
        cobros: [
          CobroCaja(
              fecha: DateTime(ahora.year, ahora.month, ahora.day, 9), monto: 1500, cliente: 'Ana'),
        ],
        entrega: Entrega(cobradorId: 'c1', fecha: ahora, cobrado: 1500, entregado: 1500),
      ),
    ));
    expect(tester.takeException(), isNull);
    expect(find.text('Tu jefe recibió RD\$1,500 · Cuadra'), findsOneWidget);
  });
}
