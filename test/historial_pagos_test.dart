import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestamistas_rd/logic/calculo_prestamo.dart';
import 'package:prestamistas_rd/logic/historial_pagos.dart';
import 'package:prestamistas_rd/recibos/historial_pdf.dart';
import 'package:prestamistas_rd/recibos/recibo_pdf.dart';
import 'package:prestamistas_rd/screens/historial_pagos_screen.dart';

/// 10,000 al 20% por 30 días semanal desde [desde].
Map<String, dynamic> prestamo(String desde, String estado) {
  final plan = calcularPlan(
      monto: 10000, tasaInteresMensual: 20, diasPlazo: 30, frecuencia: 'semanal');
  return {
    'monto': 10000.0,
    'tasa_interes': 20.0,
    'cuota': plan.cuota,
    'cantidad_cuotas': plan.cantidadCuotas,
    'monto_total': plan.montoTotal,
    'frecuencia': 'semanal',
    'fecha_desembolso': desde,
    'mora_diaria': 0.0,
    'dias_gracia': 1,
    'estado': estado,
  };
}

PagoRegistrado pago(int recibo, DateTime fecha, double monto, {bool anulado = false}) =>
    PagoRegistrado(
        id: 'p$recibo',
        numeroRecibo: recibo,
        fecha: fecha,
        monto: monto,
        anulado: anulado,
        motivoAnulacion: anulado ? 'mal digitado' : null);

void main() {
  final hoy = DateTime(2026, 10, 15);
  final viejo = prestamo('2026-06-01', 'pagado');
  final actual = prestamo('2026-10-01', 'en_calle');
  final total = montoTotalGuardado(viejo);

  List<PrestamoHistorial> armar() => historialPagos([
        (prestamo: viejo, pagos: [pago(1, DateTime(2026, 6, 20), total)]),
        (prestamo: prestamo('2026-09-01', 'borrador'), pagos: const []),
        (prestamo: prestamo('2026-08-01', 'cancelado'), pagos: const []),
        (
          prestamo: actual,
          pagos: [
            pago(3, DateTime(2026, 10, 8), 3000),
            pago(2, DateTime(2026, 10, 7), 500, anulado: true),
          ]
        ),
      ], hoy);

  test('trae los préstamos del más nuevo al más viejo, sin borradores ni cancelados vacíos', () {
    final h = armar();
    expect(h.length, 2);
    expect(h.first.desde, DateTime(2026, 10, 1));
    expect(h.first.estadoTexto, 'En la calle');
    expect(h.last.estadoTexto, 'Saldado');
  });

  test('los cobros van por fecha y los anulados no cuentan en lo pagado', () {
    final actualH = armar().first;
    expect(actualH.pagos.map((p) => p.numeroRecibo), [2, 3]);
    expect(actualH.pagado, 3000);
    expect(actualH.balance, montoTotalGuardado(actual) - 3000);
    final viejoH = armar().last;
    expect(viejoH.pagado, total);
    expect(viejoH.balance, 0);
  });

  test('el PDF se genera (y se guarda de muestra si se pide)', () async {
    final bytes = await historialPdf(
      prestamos: armar(),
      negocio: const NegocioRecibo(nombre: 'Inversiones MC', telefono: '809-555-1234'),
      cliente: 'Juan Pérez',
      cedula: '001-0000000-1',
      hoy: hoy,
    );
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    final muestra = Platform.environment['HISTORIAL_MUESTRA'];
    if (muestra != null) File(muestra).writeAsBytesSync(bytes);
  });

  testWidgets('la pantalla muestra los préstamos, los pagos y el botón del PDF', (tester) async {
    tester.view.physicalSize = const Size(400, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: HistorialPagosScreen(cliente: 'Juan Pérez', prestamos: armar()),
    ));
    expect(tester.takeException(), isNull);
    expect(find.text('Compartir PDF'), findsOneWidget);
    expect(find.text('EN LA CALLE'), findsOneWidget);
    expect(find.text('SALDADO'), findsOneWidget);
    expect(find.text('Anulado: mal digitado'), findsOneWidget);
  });
}
