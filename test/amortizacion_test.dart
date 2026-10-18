import 'package:flutter_test/flutter_test.dart';
import 'package:prestamistas_rd/logic/calculo_prestamo.dart';

/// La tabla de la cooperativa ("PRUEBA 1", 30/10/2025): RD$2,060,000 al
/// 1.8333% mensual, 60 cuotas mensuales fijas de RD$56,894.49.
void main() {
  group('Interés sobre saldo, igual que la cooperativa', () {
    final plan = calcularPlan(
      monto: 2060000,
      tasaInteresMensual: 1.8333,
      diasPlazo: 60 * 30,
      frecuencia: 'mensual',
      tipo: TipoInteres.saldo,
    );

    test('60 cuotas fijas de 56,894 (ellos 56,894.49: la app usa pesos enteros)', () {
      expect(plan.cantidadCuotas, 60);
      expect(plan.cuota, 56894);
    });

    test('el interés de cada cuota es el saldo por la tasa', () {
      final f = plan.filas;
      expect(f.first.interes, 37765.98); // 2,060,000 × 1.8333%
      expect(f.first.capital, closeTo(19128.02, 0.01));
      // Cuota 12 de la cooperativa: interés 33,534.69, saldo 1,805,838.34.
      expect(f[11].interes, closeTo(33534.69, 6));
      expect(f[11].saldo, closeTo(1805838.34, 60));
      // La última cuota termina de pagar el capital.
      expect(f.last.saldo, 0);
      expect(f.fold<double>(0, (s, x) => s + x.capital), closeTo(2060000, 0.01));
    });

    test('el interés total queda como el de la cooperativa (1,353,669.49)', () {
      expect(plan.interesTotal, closeTo(1353669.49, 100));
      expect(plan.montoTotal, closeTo(3413669.49, 100));
    });

    test('con la misma tasa, el fijo de antes cobraba casi 912 mil más', () {
      final fijo = calcularPlan(
          monto: 2060000, tasaInteresMensual: 1.8333, diasPlazo: 1800, frecuencia: 'mensual');
      expect(fijo.tipo, TipoInteres.fijo);
      expect(fijo.interesTotal - plan.interesTotal, greaterThan(900000));
    });
  });

  group('Sobre saldo en préstamos de la calle', () {
    test('10,000 al 20% mensual, 4 cuotas semanales', () {
      final p = calcularPlan(
          monto: 10000,
          tasaInteresMensual: 20,
          diasPlazo: 28,
          frecuencia: 'semanal',
          tipo: TipoInteres.saldo);
      // Tasa por semana: 20% × 7 ÷ 30 = 4.667%.
      expect(p.cantidadCuotas, 4);
      expect(p.filas.first.interes, closeTo(466.67, 0.01));
      expect(p.filas.fold<double>(0, (s, f) => s + f.cuota), p.montoTotal);
      expect(p.interesTotal, lessThan(1867)); // el fijo da 1,867
    });

    test('sin interés: se reparte el monto', () {
      final p = calcularPlan(
          monto: 1000, tasaInteresMensual: 0, diasPlazo: 4, frecuencia: 'diario', tipo: TipoInteres.saldo);
      expect(p.montoTotal, 1000);
      expect(p.interesTotal, 0);
    });
  });

  test('el cronograma de un préstamo sobre saldo trae el interés de la tabla', () {
    final plan = calcularPlan(
        monto: 10000,
        tasaInteresMensual: 10,
        diasPlazo: 90,
        frecuencia: 'mensual',
        tipo: TipoInteres.saldo);
    final prestamo = {
      'monto': 10000.0,
      'tasa_interes': 10.0,
      'cuota': plan.cuota,
      'cantidad_cuotas': plan.cantidadCuotas,
      'monto_total': plan.montoTotal,
      'frecuencia': 'mensual',
      'fecha_desembolso': '2026-10-01',
      'tipo_interes': 'saldo',
    };
    final c = generarCronograma(prestamo: prestamo, totalPagado: 0);
    expect(c.first['interes'], 1000); // 10,000 × 10%
    expect((c.last['interes'] as double) < (c.first['interes'] as double), isTrue);
    expect(interesCobrado(prestamo, plan.montoTotal), closeTo(plan.interesTotal, 0.01));
    // Un préstamo guardado sin tipo (de antes) sigue siendo fijo.
    expect(tipoInteresDe({...prestamo}..remove('tipo_interes')), TipoInteres.fijo);
  });
}
