import 'package:flutter_test/flutter_test.dart';
import 'package:prestamistas_rd/logic/calculo_prestamo.dart';
import 'package:prestamistas_rd/logic/graficas.dart';

/// RD$10,000 al 10% mensual, 3 cuotas mensuales sobre saldo, desde el 1/1/2026.
Map<String, dynamic> prestamo() {
  final plan = calcularPlan(
      monto: 10000,
      tasaInteresMensual: 10,
      diasPlazo: 90,
      frecuencia: 'mensual',
      tipo: TipoInteres.saldo);
  return {
    'monto': 10000,
    'tasa_interes': 10,
    'frecuencia': 'mensual',
    'cantidad_cuotas': plan.cantidadCuotas,
    'cuota': plan.cuota,
    'monto_total': plan.montoTotal,
    'tipo_interes': 'saldo',
    'fecha_desembolso': '2026-01-01',
    'mora_diaria': 0,
    'dias_gracia': 1,
  };
}

void main() {
  test('a los 9 días: capital + 10 días de interés (9 + 1 de cierre)', () {
    final s = calcularSaldarHoy(prestamo(), const [], DateTime(2026, 1, 10));
    expect(s.capital, 10000);
    expect(s.dias, 10);
    // Interés de la primera cuota: 10,000 × 10% = 1,000 por 31 días de enero.
    expect(s.interesDias, (1000 * 10 / 31).roundToDouble());
    expect(s.monto, 10000 + s.interesDias);
    expect(s.descuento, s.balance - s.monto);
    expect(s.conDescuento, isTrue);
  });

  test('pagada la cuota 1: capital que falta + días desde esa cuota', () {
    final p = prestamo();
    final cuota = (p['cuota'] as num).toDouble();
    final pagos = [PagoRegistrado(fecha: DateTime(2026, 2, 1), monto: cuota)];
    final s = calcularSaldarHoy(p, pagos, DateTime(2026, 2, 15));
    // Cuota 1: 1,000 de interés, el resto bajó el capital.
    expect(s.capital, closeTo(10000 - (cuota - 1000), 0.01));
    expect(s.dias, 15); // del 1/2 al 15/2, más 1 de cierre
    expect(s.monto, (s.capital + s.interesDias).roundToDouble());
  });

  test('con todas las cuotas vencidas no hay descuento', () {
    final s = calcularSaldarHoy(prestamo(), const [], DateTime(2026, 5, 1));
    expect(s.descuento, 0);
    expect(s.monto, s.balance);
  });

  test('el cobro con descuento deja el préstamo saldado y el recibo lo dice', () {
    final p = prestamo();
    final hoy = DateTime(2026, 1, 10);
    final s = calcularSaldarHoy(p, const [], hoy);
    final pago = PagoRegistrado(fecha: hoy, monto: s.monto, descuento: s.descuento, numeroRecibo: 1);
    final estado = estadoPrestamo(p, [pago], hoy);
    expect(estado.saldado, isTrue);

    final r = datosRecibo(p, [pago], pago);
    expect(r.saldado, isTrue);
    expect(r.monto, s.monto); // el dinero recibido, sin el descuento
    expect(r.cubre.first, 'Saldo del préstamo (cuotas #1 a #3)');
    expect(r.cubre.last, contains('Descuento de interés'));
  });

  test('el descuento no cuenta como dinero cobrado ni como ganancia', () {
    final p = prestamo();
    final hoy = DateTime(2026, 1, 10);
    final s = calcularSaldarHoy(p, const [], hoy);
    final pago = PagoRegistrado(fecha: hoy, monto: s.monto, descuento: s.descuento);
    final estado = estadoPrestamo(p, [pago], hoy);
    expect(estado.cobradoCuotas, s.monto); // solo el dinero
    expect(estado.descuentos, s.descuento);

    // Gráficas: el interés del cobro es lo ganado de verdad (los días de interés).
    final cobro = CobroGrafica(
        prestamoId: 'p', fecha: hoy, monto: s.monto, descuento: s.descuento);
    expect(interesPorCobro([cobro], {'p': p})[cobro], closeTo(s.interesDias, 0.01));

    // Reportes: "Ya llevas" y la proyectada quedan en lo ganado de verdad.
    final g = gananciaDelMes([
      {...p, 'total_pagado': estado.cobradoCuotas, 'total_descuento': estado.descuentos}
    ], hoy);
    expect(g.proyectada, closeTo(s.interesDias, 0.01));
    expect(g.yaLlevas, closeTo(s.interesDias, 0.01));
  });

  test('cuota vencida sin pagar: el capital no lleva el interés vencido (va aparte)', () {
    final s = calcularSaldarHoy(prestamo(), const [], DateTime(2026, 2, 15));
    expect(s.capital, closeTo(10000, 0.01));
    expect(s.interesVencido, closeTo(1000, 0.01));
    expect(s.dias, 15);
    // Total igual que antes: lo que debe menos el interés futuro, más los días.
    expect(s.monto, (s.balance - 697.90 - 365.10 + s.interesDias).roundToDouble());
    expect(s.capital + s.interesVencido + s.interesDias + s.mora, closeTo(s.monto, 1));
  });

  test('las partes (capital, interés vencido, días, mora) suman el total a pagar', () {
    final p = {...prestamo(), 'mora_diaria': 5};
    final cuota = (p['cuota'] as num).toDouble();
    for (final pagos in [
      <PagoRegistrado>[],
      [PagoRegistrado(fecha: DateTime(2026, 2, 1), monto: cuota)],
      // Adelantó media cuota: baja el capital.
      [PagoRegistrado(fecha: DateTime(2026, 2, 1), monto: cuota * 1.5)],
      [PagoRegistrado(fecha: DateTime(2026, 2, 20), monto: 1000)],
    ]) {
      for (final dia in [DateTime(2026, 1, 20), DateTime(2026, 2, 25), DateTime(2026, 3, 10)]) {
        final s = calcularSaldarHoy(p, pagos, dia);
        expect(s.capital + s.interesVencido + s.interesDias + s.mora, closeTo(s.monto, 1),
            reason: 'pagos ${pagos.map((x) => x.monto)} el $dia');
      }
    }
  });

  test('adelantó media cuota: ese adelanto es todo capital', () {
    final p = prestamo();
    final cuota = (p['cuota'] as num).toDouble();
    final s = calcularSaldarHoy(
        p, [PagoRegistrado(fecha: DateTime(2026, 2, 1), monto: cuota * 1.5)], DateTime(2026, 2, 10));
    // Cuota 1: 1,000 de interés; lo demás (y la media cuota adelantada) baja el capital.
    expect(s.capital, closeTo(10000 - (cuota - 1000) - cuota * 0.5, 0.01));
    expect(s.interesVencido, 0);
  });
}
