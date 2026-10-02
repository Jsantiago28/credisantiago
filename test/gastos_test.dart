import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestamistas_rd/logic/caja.dart';
import 'package:prestamistas_rd/logic/gastos.dart';
import 'package:prestamistas_rd/screens/gastos_screen.dart';

final gastos = [
  Gasto(id: 'g1', fecha: DateTime(2026, 9, 2), monto: 500, categoria: 'gasolina'),
  Gasto(id: 'g2', fecha: DateTime(2026, 9, 20), monto: 3000, categoria: 'cobrador', nota: 'Juan'),
  Gasto(id: 'g3', fecha: DateTime(2026, 9, 20), monto: 700, categoria: 'gasolina'),
  Gasto(id: 'g4', fecha: DateTime(2026, 8, 31), monto: 9999, categoria: 'otro'),
];

void main() {
  test('gastos del mes: solo ese mes, el más reciente primero', () {
    final sep = gastosDelMes(gastos, DateTime(2026, 9));
    expect(sep.map((g) => g.id), ['g2', 'g3', 'g1']);
    expect(totalGastos(sep), 4200);
    expect(gastosDelMes(gastos, DateTime(2026, 8)).single.id, 'g4');
  });

  test('gastos del día', () {
    expect(gastosDelDia(gastos, DateTime(2026, 9, 20, 15)).map((g) => g.id), ['g2', 'g3']);
    expect(gastosDelDia(gastos, DateTime(2026, 9, 21)), isEmpty);
  });

  test('por categoría: la de más gasto primero', () {
    final c = gastosPorCategoria(gastosDelMes(gastos, DateTime(2026, 9)));
    expect(c.map((e) => e.categoria), ['cobrador', 'gasolina']);
    expect(c.map((e) => e.total), [3000, 1200]);
  });

  test('ganancia real = interés + mora − gastos (puede salir negativa)', () {
    final g = gananciaReal(interes: 5000, mora: 300, gastos: 4200);
    expect(g.real, 1100);
    expect(gananciaReal(interes: 1000, mora: 0, gastos: 1500).real, -500);
  });

  test('descripción y lectura de la fila de Supabase', () {
    final g = Gasto.desdeFila({
      'id': 'x',
      'fecha': '2026-09-29',
      'monto': 350,
      'categoria': 'telefono',
      'nota': '  ',
    });
    expect(g.fecha, DateTime(2026, 9, 29));
    expect(g.monto, 350);
    expect(g.descripcion, 'Teléfono y recargas');
    expect(gastos[1].descripcion, 'Pago al cobrador · Juan');
    expect(nombreCategoria('rara'), 'Otro');
  });

  test('el resumen de caja por WhatsApp incluye los gastos y lo que queda', () {
    final dia = cajaPorDia([
      CobroCaja(fecha: DateTime(2026, 9, 20, 9), monto: 5000, cliente: 'José Pérez'),
    ]).single;
    final texto = resumenCajaTexto(dia,
        negocio: 'Préstamos Núñez', gastos: gastosDelDia(gastos, DateTime(2026, 9, 20)));
    expect(texto, contains('Gastos: RD\$3,700'));
    expect(texto, contains('• Pago al cobrador · Juan: RD\$3,000'));
    expect(texto, contains('Te queda: RD\$1,300'));
    // Sin gastos, el resumen queda como antes.
    expect(resumenCajaTexto(dia, negocio: 'X'), isNot(contains('Gastos')));
  });

  testWidgets('pantalla de gastos cabe en un teléfono', (tester) async {
    tester.view.physicalSize = const Size(360, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final sep = gastosDelMes(gastos, DateTime(2026, 9));
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData.dark(),
      home: Scaffold(
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: contenidoGastos(
              gastos: sep, interes: 5000, mora: 300, mes: DateTime(2026, 9), onBorrar: (_) {}),
        ),
      ),
    ));
    expect(tester.takeException(), isNull);
    expect(find.text('GANANCIA REAL DE SEPTIEMBRE 2026'), findsOneWidget);
    expect(find.text('RD\$1,100'), findsOneWidget);
    expect(find.text('Gastos (3)'), findsOneWidget);
    expect(find.byTooltip('Borrar'), findsNWidgets(3));
  });

  testWidgets('sin gastos: lo dice y la ganancia real es lo ganado', (tester) async {
    tester.view.physicalSize = const Size(360, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData.dark(),
      home: Scaffold(
        body: ListView(
          children: contenidoGastos(
              gastos: const [], interes: 2000, mora: 0, mes: DateTime(2026, 10)),
        ),
      ),
    ));
    expect(find.text('RD\$2,000'), findsWidgets);
    expect(find.textContaining('No hay gastos anotados'), findsOneWidget);
    expect(find.text('En qué se fue'), findsNothing);
  });

  testWidgets('formulario de gasto cabe en un teléfono', (tester) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData.dark(),
      home: const Scaffold(body: FormularioGasto(prestamistaId: 'x')),
    ));
    expect(tester.takeException(), isNull);
    expect(find.text('Pago al cobrador'), findsOneWidget);
    expect(find.text('Hoy'), findsOneWidget);
    // Sin monto no guarda (y no llama a Supabase).
    await tester.tap(find.text('Guardar gasto'));
    await tester.pump();
    expect(find.text('Escribe cuánto gastaste'), findsOneWidget);
  });
}
