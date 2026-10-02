import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestamistas_rd/logic/calculo_prestamo.dart';
import 'package:prestamistas_rd/logic/gestiones.dart';
import 'package:prestamistas_rd/services/supabase_service.dart';
import 'package:prestamistas_rd/widgets/gestiones.dart';

import 'ui_test.dart' show enTelefono;

PrestamoConDatos prestamo() {
  final plan = calcularPlan(monto: 10000, tasaInteresMensual: 20, diasPlazo: 30, frecuencia: 'diario');
  return PrestamoConDatos(
    prestamo: {
      'id': 'p1',
      'estado': 'en_calle',
      'monto': 10000.0,
      'cuota': plan.cuota,
      'cantidad_cuotas': plan.cantidadCuotas,
      'monto_total': plan.montoTotal,
      'frecuencia': 'diario',
      'fecha_desembolso': '2026-09-01',
    },
    cliente: {'nombre': 'María Altagracia de los Santos Rodríguez'},
    pagos: const [],
  );
}

void main() {
  testWidgets('historial: una promesa larga con su acuerdo cabe en un teléfono', (tester) async {
    final g = Gestion(
      prestamoId: 'p1',
      fecha: DateTime(2026, 9, 22, 15, 40),
      tipo: 'whatsapp',
      resultado: 'promesa',
      acuerdo: 'Paga el viernes 2,000 y el resto el lunes cuando cobre en la zona franca',
      promesaFecha: DateTime(2039, 12, 1), // lejos, para que la fila no dependa de hoy,
      promesaMonto: 125000,
    );
    await enTelefono(
        tester,
        Column(children: [
          FilaGestion(g, pagos: [PagoRegistrado(fecha: DateTime(2026, 9, 23), monto: 800)]),
          LineaPromesa(estadoPromesa(g, const [], DateTime(2040))),
        ]));
    expect(find.textContaining('WhatsApp · Prometió pagar'), findsOneWidget);
    expect(find.textContaining('ha dado RD\$800'), findsOneWidget);
    expect(find.text('NO CUMPLIÓ'), findsOneWidget);
  });

  testWidgets('formulario de gestión cabe en un teléfono y pide fecha y monto al prometer',
      (tester) async {
    await enTelefono(
      tester,
      Builder(
        builder: (context) => ElevatedButton(
          onPressed: () => anotarGestion(context, prestamo()),
          child: const Text('abrir'),
        ),
      ),
    );
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
    expect(find.text('Monto prometido'), findsOneWidget);
    expect(find.text('Acuerdo'), findsOneWidget);

    // Si no prometió, no se piden fecha ni monto, y el campo pasa a "Nota".
    await tester.tap(find.text('No estaba'));
    await tester.pumpAndSettle();
    expect(find.text('Monto prometido'), findsNothing);
    expect(find.text('Nota'), findsOneWidget);
  });

  test('hora legible', () {
    expect(fechaHora(DateTime(2026, 9, 25, 15, 4)), '25 sep 3:04 pm');
    expect(fechaHora(DateTime(2026, 9, 25, 0, 30)), '25 sep 12:30 am');
  });
}
