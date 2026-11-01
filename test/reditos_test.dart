import 'package:flutter_test/flutter_test.dart';
import 'package:prestamistas_rd/logic/calculo_prestamo.dart';
import 'package:prestamistas_rd/logic/contrato.dart';

/// RD$10,000 al 10% mensual, 3 cuotas mensuales de solo réditos, desde el
/// 1/9/2026: cuotas el 1/10, 1/11 y 1/12.
Map<String, dynamic> prestamo({double mora = 0}) {
  final plan = calcularPlan(
      monto: 10000,
      tasaInteresMensual: 10,
      diasPlazo: 90,
      frecuencia: 'mensual',
      tipo: TipoInteres.reditos);
  return {
    'monto': 10000,
    'tasa_interes': 10,
    'frecuencia': 'mensual',
    'cantidad_cuotas': plan.cantidadCuotas,
    'cuota': plan.cuota,
    'monto_total': plan.montoTotal,
    'tipo_interes': 'reditos',
    'fecha_desembolso': '2026-09-01',
    'mora_diaria': mora,
    'dias_gracia': 1,
  };
}

void main() {
  group('Plan de solo réditos', () {
    test('10,000 al 10% mensual, 3 cuotas mensuales: 1,000, 1,000 y 11,000', () {
      final p = calcularPlan(
          monto: 10000,
          tasaInteresMensual: 10,
          diasPlazo: 90,
          frecuencia: 'mensual',
          tipo: TipoInteres.reditos);
      expect(p.tipo, TipoInteres.reditos);
      expect(p.cantidadCuotas, 3);
      expect(p.cuota, 1000);
      expect(p.ultimaCuota, 11000);
      expect(p.montoTotal, 13000);
      expect(p.interesTotal, 3000);
      expect([for (final f in p.filas) f.cuota], [1000, 1000, 11000]);
      expect([for (final f in p.filas) f.interes], [1000, 1000, 1000]);
      expect([for (final f in p.filas) f.capital], [0, 0, 10000]);
      expect([for (final f in p.filas) f.saldo], [10000, 10000, 0]);
    });

    test('semanal: el interés de cada semana es la tasa mensual por 7 ÷ 30', () {
      // 10,000 × 20% × 7 ÷ 30 = 466.67 → 467 por semana; 30 días = 5 semanas.
      final p = calcularPlan(
          monto: 10000,
          tasaInteresMensual: 20,
          diasPlazo: 30,
          frecuencia: 'semanal',
          tipo: TipoInteres.reditos);
      expect(p.cantidadCuotas, 5);
      expect(p.cuota, 467);
      expect(p.ultimaCuota, 10467);
      expect(p.montoTotal, 467 * 5 + 10000);
    });

    test('diario: 10,000 al 20% → 67 diarios y la última 10,067', () {
      final p = calcularPlan(
          monto: 10000,
          tasaInteresMensual: 20,
          diasPlazo: 30,
          frecuencia: 'diario',
          tipo: TipoInteres.reditos);
      expect(p.cantidadCuotas, 30);
      expect(p.cuota, 67);
      expect(p.ultimaCuota, 10067);
      expect(p.montoTotal, 67 * 30 + 10000);
    });

    test('sin interés no hay réditos: no se puede', () {
      expect(
          () => calcularPlan(
              monto: 10000,
              tasaInteresMensual: 0,
              diasPlazo: 90,
              frecuencia: 'mensual',
              tipo: TipoInteres.reditos),
          throwsArgumentError);
    });

    test('se guarda y se lee como "reditos"', () {
      expect(TipoInteres.reditos.valor, 'reditos');
      expect(tipoInteresDe({'tipo_interes': 'reditos'}), TipoInteres.reditos);
      expect(tipoInteresDe({'tipo_interes': 'saldo'}), TipoInteres.saldo);
      expect(tipoInteresDe({'tipo_interes': 'otro'}), TipoInteres.fijo);
      expect(TipoInteres.desdeValor('reditos'), TipoInteres.reditos);
      expect(TipoInteres.desdeValor(null), isNull);
    });
  });

  group('Cronograma y estado de réditos', () {
    test('cuotas, fechas e interés de cada una', () {
      final c = generarCronograma(prestamo: prestamo(), totalPagado: 0);
      expect([for (final x in c) x['monto']], [1000, 1000, 11000]);
      expect([for (final x in c) x['interes']], [1000, 1000, 1000]);
      expect([for (final x in c) x['fecha']],
          [DateTime(2026, 10, 1), DateTime(2026, 11, 1), DateTime(2026, 12, 1)]);
    });

    test('lo cobrado de las primeras cuotas es todo ganancia', () {
      expect(interesCobrado(prestamo(), 2000), 2000);
      // De la última (11,000 = 1,000 interés + 10,000 capital), mitad cobrada.
      expect(interesCobrado(prestamo(), 2000 + 5500), closeTo(2500, 0.01));
      expect(interesCobrado(prestamo(), 13000), closeTo(3000, 0.01));
    });

    test('estado: debe 13,000 y queda saldado al pagar todo', () {
      final p = prestamo();
      final e = estadoPrestamo(p, const [], DateTime(2026, 9, 15));
      expect(e.balance, 13000);
      final pagos = [
        PagoRegistrado(fecha: DateTime(2026, 10, 1), monto: 1000),
        PagoRegistrado(fecha: DateTime(2026, 11, 1), monto: 1000),
        PagoRegistrado(fecha: DateTime(2026, 12, 1), monto: 11000),
      ];
      expect(estadoPrestamo(p, pagos, DateTime(2026, 12, 1)).saldado, isTrue);
    });
  });

  group('Saldar hoy con réditos', () {
    test('al día: capital + interés de los días corridos + 1 de cierre', () {
      final pagos = [PagoRegistrado(fecha: DateTime(2026, 10, 1), monto: 1000)];
      // Del 1/10 al 10/10: 9 días + 1 de cierre = 10 de los 31 de octubre.
      final s = calcularSaldarHoy(prestamo(), pagos, DateTime(2026, 10, 10));
      expect(s.capital, 10000);
      expect(s.dias, 10);
      expect(s.interesDias, (1000 * 10 / 31).roundToDouble()); // 323
      expect(s.monto, 10000 + 323);
      expect(s.balance, 12000);
      expect(s.descuento, 12000 - 10323);
    });

    test('atrasado: también paga las cuotas vencidas', () {
      // 5/11 sin pagar nada: vencieron 1/10 y 1/11 (2,000 de réditos).
      final s = calcularSaldarHoy(prestamo(), const [], DateTime(2026, 11, 5));
      expect(s.interesVencido, 2000);
      expect(s.capital, 10000);
      expect(s.dias, 5);
      expect(s.interesDias, (1000 * 5 / 30).roundToDouble()); // 167
      expect(s.monto, 10000 + 2000 + 167);
    });

    test('con mora: la mora va completa', () {
      final s = calcularSaldarHoy(prestamo(mora: 1), const [], DateTime(2026, 11, 5));
      expect(s.mora, greaterThan(0));
      expect(s.monto, 10000 + 2000 + 167 + s.mora);
    });

    test('la última cuota en curso: capital + días de su interés', () {
      final pagos = [
        PagoRegistrado(fecha: DateTime(2026, 10, 1), monto: 1000),
        PagoRegistrado(fecha: DateTime(2026, 11, 1), monto: 1000),
      ];
      final s = calcularSaldarHoy(prestamo(), pagos, DateTime(2026, 11, 2));
      expect(s.dias, 2);
      expect(s.monto, 10000 + (1000 * 2 / 30).roundToDouble());
    });
  });

  test('el contrato explica los réditos', () {
    final d = datosContrato(
        prestamo: prestamo(), cliente: null, perfil: null, hoy: DateTime(2026, 9, 1));
    expect(d.tipoInteres, TipoInteres.reditos);
    expect(d.tasaTexto, contains('10% mensual, solo réditos'));
    expect(d.tasaTexto, contains('la última cuota paga además todo el capital'));
    expect(d.cuota, 1000);
    expect(d.ultimaCuota, 11000);
  });
}
