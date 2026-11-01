import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestamistas_rd/logic/calculo_prestamo.dart';
import 'package:prestamistas_rd/logic/ultimos_valores_prestamo.dart';
import 'package:prestamistas_rd/screens/calculadora_screen.dart';
import 'package:prestamistas_rd/screens/prestar_screen.dart';
import 'package:prestamistas_rd/services/supabase_service.dart';
import 'package:prestamistas_rd/widgets/cobro_prestamo.dart';
import 'package:prestamistas_rd/widgets/ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> abrir(WidgetTester tester, Widget pantalla) async {
  tester.view.physicalSize = const Size(600, 2600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(theme: ThemeData.dark(), home: pantalla));
  await tester.pump();
  await tester.pump();
}

/// Préstamo diario de 1,000 desde hace [diasAtras] días.
PrestamoConDatos prestamoDiario(int diasAtras) {
  final plan = calcularPlan(
      monto: 1000, tasaInteresMensual: 20, diasPlazo: 10, frecuencia: 'diario',
      tipo: TipoInteres.saldo);
  final hoy = DateTime.now();
  return PrestamoConDatos(
    prestamo: {
      'id': 'p1',
      'prestamista_id': 'jefe',
      'monto': 1000,
      'tasa_interes': 20,
      'frecuencia': 'diario',
      'cantidad_cuotas': plan.cantidadCuotas,
      'cuota': plan.cuota,
      'monto_total': plan.montoTotal,
      'tipo_interes': 'saldo',
      'fecha_desembolso': fechaSql(DateTime(hoy.year, hoy.month, hoy.day - diasAtras)),
      'mora_diaria': 0,
      'dias_gracia': 1,
    },
    cliente: {'nombre': 'Ana Pérez'},
    pagos: const [],
  );
}

Widget conBoton(PrestamoConDatos datos) => Scaffold(
      body: Builder(
        builder: (context) => Center(
          child: TextButton(
            onPressed: () => CobroPrestamo(context, datos, onCambio: () {}).abrirCuotas(),
            child: const Text('abrir'),
          ),
        ),
      ),
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('Prestar: método de interés y primer pago', () {
    testWidgets('se elige solo réditos y el resumen cambia', (tester) async {
      await abrir(
          tester, const PrestarScreen(cliente: {'nombre': 'José'}, prestamo: {'id': 'p1', 'monto': 5000}));
      expect(find.text('Sobre saldo (cuota fija)'), findsOneWidget);
      expect(find.text('Fijo sobre el monto'), findsOneWidget);
      await tester.tap(find.text('Solo réditos (capital al final)'));
      await tester.pump();
      // 5,000 al 20% diario: 5,000 × 20% ÷ 30 = 33.33 → 33 diarios; la última 5,033.
      expect(find.text('RD\$ 33'), findsOneWidget);
      expect(find.text('RD\$ 5033'), findsOneWidget);
      expect(find.textContaining('solo réditos'), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('abre con el último método elegido', (tester) async {
      await guardarUltimoTipoInteres(TipoInteres.fijo);
      expect(await leerUltimoTipoInteres(), TipoInteres.fijo);
      await abrir(
          tester, const PrestarScreen(cliente: {'nombre': 'José'}, prestamo: {'id': 'p1', 'monto': 5000}));
      final chip = tester.widget<ChoiceChip>(
          find.ancestor(of: find.text('Fijo sobre el monto'), matching: find.byType(ChoiceChip)));
      expect(chip.selected, isTrue);
    });

    testWidgets('muestra la fecha del primer pago (por defecto mañana en diario)', (tester) async {
      await abrir(
          tester, const PrestarScreen(cliente: {'nombre': 'José'}, prestamo: {'id': 'p1', 'monto': 5000}));
      final h = DateTime.now();
      final manana = DateTime(h.year, h.month, h.day + 1);
      expect(find.text('Fecha del primer pago'), findsOneWidget);
      expect(find.textContaining(fechaLarga(manana)), findsWidgets);
      await tester.tap(find.byKey(const Key('primer_pago')));
      await tester.pumpAndSettle();
      expect(find.byType(DatePickerDialog), findsOneWidget);
    });

    testWidgets('la calculadora también deja elegir y lo recuerda', (tester) async {
      await abrir(tester, const CalculadoraScreen(prestamistaId: 'p1'));
      expect(find.text('Sobre saldo (cuota fija)'), findsOneWidget);
      await tester.tap(find.byType(DropdownButtonFormField<TipoInteres>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Solo réditos (capital al final)').last);
      await tester.pumpAndSettle();
      expect(await leerUltimoTipoInteres(), TipoInteres.reditos);
      // 10,000 al 20% mensual por 1 mes en una cuota mensual: 2,000 + 10,000.
      expect(find.textContaining('Interés solo réditos'), findsWidgets);
      expect(find.text('RD\$2,000'), findsWidgets);
      expect(tester.takeException(), isNull);
    });
  });

  group('Cobrar de un toque', () {
    testWidgets('botón "Cobrar lo de hoy" con lo atrasado y lo de hoy', (tester) async {
      final datos = prestamoDiario(3); // vencieron 2 cuotas y la 3.ª vence hoy
      final estado = datos.estado(DateTime.now());
      final delDia = cobroDelDia(estado, DateTime.now());
      final loDeHoy = delDia.atrasado + delDia.venceHoy;
      expect(loDeHoy, estado.cuotas.take(3).fold(0.0, (s, c) => s + c.monto));

      await abrir(tester, conBoton(datos));
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();
      expect(find.text('Cobrar lo de hoy · ${rd(loDeHoy)}'), findsOneWidget);

      await tester.tap(find.byKey(const Key('cobrar_lo_de_hoy')));
      await tester.pumpAndSettle();
      expect(find.text('Cobrar a Ana Pérez'), findsOneWidget);
      final campo = tester.widget<TextField>(find.byType(TextField));
      expect(campo.controller!.text, loDeHoy.toStringAsFixed(0));
      // Botones rápidos y forma de pago.
      final cuota = estado.cuotas.first.monto;
      expect(find.text('Cuota · ${rd(cuota)}'), findsOneWidget);
      expect(find.text('Todo lo atrasado · ${rd(delDia.atrasado)}'), findsOneWidget);
      expect(find.text('Todo lo de hoy · ${rd(loDeHoy)}'), findsOneWidget);
      expect(find.text('Efectivo'), findsOneWidget);
      expect(find.text('Transferencia'), findsOneWidget);

      await tester.tap(find.text('Cuota · ${rd(cuota)}'));
      await tester.pump();
      expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
          cuota.toStringAsFixed(0));
      await tester.tap(find.text('Transferencia'));
      await tester.pump();
      final selector = tester.widget<SegmentedButton<String>>(find.byType(SegmentedButton<String>));
      expect(selector.selected, {'transferencia'});
      expect(tester.takeException(), isNull);
    });

    testWidgets('sin nada que cobrar hoy dice "Al día"', (tester) async {
      await abrir(tester, conBoton(prestamoDiario(0)));
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('cobrar_lo_de_hoy')), findsNothing);
      expect(find.text('Al día'), findsOneWidget);
      // La lista de cuotas sigue ahí.
      expect(find.textContaining('Cuota #1 —'), findsOneWidget);
    });
  });
}
