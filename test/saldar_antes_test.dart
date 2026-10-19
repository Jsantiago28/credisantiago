import 'package:flutter_test/flutter_test.dart';
import 'package:prestamistas_rd/logic/calculo_prestamo.dart';

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
}
