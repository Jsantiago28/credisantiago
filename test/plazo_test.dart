import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestamistas_rd/logic/calculo_prestamo.dart';
import 'package:prestamistas_rd/screens/login_screen.dart';
import 'package:prestamistas_rd/services/inactividad.dart';
import 'package:prestamistas_rd/widgets/plazo.dart';

void main() {
  test('el plazo en meses son 30 días cada uno', () {
    expect(diasDelPlazo(3, enMeses: true), 90);
    expect(diasDelPlazo(45, enMeses: false), 45);
    expect(convertirPlazo('90', aMeses: true), '3');
    expect(convertirPlazo('3', aMeses: false), '90');
    expect(convertirPlazo('10', aMeses: true), '1'); // nunca 0 meses
    expect(convertirPlazo('', aMeses: true), '');
  });

  testWidgets('la tabla de amortización cabe en un teléfono y deja ver todas las cuotas',
      (tester) async {
    tester.view.physicalSize = const Size(360, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final plan = calcularPlan(
        monto: 2060000,
        tasaInteresMensual: 1.8333,
        diasPlazo: 1800,
        frecuencia: 'mensual',
        tipo: TipoInteres.saldo);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: TablaAmortizacion(plan: plan, frecuencia: 'mensual', desde: DateTime(2025, 10, 30)),
        ),
      ),
    ));
    expect(tester.takeException(), isNull);
    expect(find.text('RD\$37,765.98'), findsOneWidget); // interés de la cuota 1
    expect(find.text('Ver las 60 cuotas'), findsOneWidget);
    await tester.tap(find.text('Ver las 60 cuotas'));
    await tester.pump();
    expect(find.text('Ver menos'), findsOneWidget);
  });

  testWidgets('si la sesión se cerró por inactividad, la entrada lo explica', (tester) async {
    Inactividad.cerradaPorInactividad = true;
    await tester.pumpWidget(const MaterialApp(home: LoginScreen()));
    expect(find.textContaining('40 minutos sin usarse'), findsOneWidget);
    expect(Inactividad.cerradaPorInactividad, isFalse); // se avisa una sola vez
  });
}
