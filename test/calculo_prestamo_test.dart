import 'package:flutter_test/flutter_test.dart';
import 'package:prestamistas_rd/logic/calculo_prestamo.dart';

/// Simula lo que queda guardado en Supabase al confirmar (ver
/// confirmarPrestamo). `cuota` y `monto_total` son numeric(12,2).
Map<String, dynamic> guardar(
  PlanPrestamo plan, {
  required double monto,
  required double tasa,
  required String frecuencia,
  String fechaDesembolso = '2026-09-01',
}) {
  final p = <String, dynamic>{
    'monto': monto,
    'tasa_interes': tasa,
    'cuota': double.parse(plan.cuota.toStringAsFixed(2)),
    'cantidad_cuotas': plan.cantidadCuotas,
    'monto_total': double.parse(plan.montoTotal.toStringAsFixed(2)),
    'frecuencia': frecuencia,
    'fecha_desembolso': fechaDesembolso,
    'estado': 'en_calle',
  };
  p['proximo_pago'] = fechaSql(proximoPago(p, 0)!);
  return p;
}

PlanPrestamo plan(double monto, double tasa, int dias, String frecuencia) => calcularPlan(
    monto: monto, tasaInteresMensual: tasa, diasPlazo: dias, frecuencia: frecuencia);

/// Lo que Cobrar sugiere para la próxima cuota pendiente.
double sugerido(Map<String, dynamic> p, double pagado) =>
    generarCronograma(prestamo: p, totalPagado: pagado)
        .firstWhere((c) => !(c['pagada'] as bool))['pendiente'] as double;

int pagadas(Map<String, dynamic> p, double totalPagado) =>
    generarCronograma(prestamo: p, totalPagado: totalPagado)
        .where((c) => c['pagada'] as bool)
        .length;

void main() {
  group('Prestar: interés mensual proporcional al plazo', () {
    test('30 días diario: 20% sobre 10,000 → 30 cuotas de 400', () {
      final p = plan(10000, 20, 30, 'diario');
      expect(p.interesTotal, 2000);
      expect(p.montoTotal, 12000);
      expect(p.cantidadCuotas, 30);
      expect(p.cuota, 400);
      expect(p.ultimaCuota, 400);
    });

    test('60 días = 2 meses → 40%', () {
      expect(plan(10000, 20, 60, 'diario').interesTotal, 4000);
    });

    test('15 días (medio mes) → 10%: 14 cuotas de 733 y una última de 738', () {
      final p = plan(10000, 20, 15, 'diario');
      expect(p.montoTotal, 11000);
      expect(p.cuota, 733);
      expect(p.ultimaCuota, 738);
    });

    test('45 días → 30%: 6,500 en 44 cuotas de 144 y una última de 164', () {
      final p = plan(5000, 20, 45, 'diario');
      expect(p.montoTotal, 6500);
      expect(p.cuota, 144);
      expect(p.ultimaCuota, 164);
    });

    test('1 día → 1 cuota con 1/30 del interés mensual, redondeado a peso', () {
      final p = plan(10000, 20, 1, 'diario');
      expect(p.cantidadCuotas, 1);
      expect(p.montoTotal, 10067); // 10,066.67
      expect(p.cuota, 10067);
      expect(p.ultimaCuota, 10067);
    });

    test('semanal: cuotas = semanas redondeando hacia arriba', () {
      expect(plan(1000, 20, 1, 'semanal').cantidadCuotas, 1);
      expect(plan(1000, 20, 7, 'semanal').cantidadCuotas, 1);
      expect(plan(1000, 20, 8, 'semanal').cantidadCuotas, 2);
      expect(plan(1000, 20, 28, 'semanal').cantidadCuotas, 4);
    });

    test('semanal 30 días → 5 semanas reales: el interés se cobra por 35 días', () {
      final p = plan(10000, 20, 30, 'semanal');
      expect(p.cantidadCuotas, 5);
      expect(p.diasCobrados, 35);
      expect(p.montoTotal, 12333); // 10,000 + 2,333.33
      expect(p.cuota, 2466);
      expect(p.ultimaCuota, 2469);
    });

    test('semanal con semanas exactas no cambia nada: 28 días = 28 días de interés', () {
      final p = plan(10000, 20, 28, 'semanal');
      expect(p.diasCobrados, 28);
      expect(p.montoTotal, 11867); // 10,000 + 1,866.67
    });

    test('quincenal 30 días: 2 quincenas, 20% → 12,000 en 2 cuotas de 6,000', () {
      final p = plan(10000, 20, 30, 'quincenal');
      expect(p.cantidadCuotas, 2);
      expect(p.diasCobrados, 30);
      expect(p.cuota, 6000);
    });

    test('quincenal 45 días: 3 quincenas', () {
      final p = plan(10000, 20, 45, 'quincenal');
      expect(p.cantidadCuotas, 3);
      expect(p.montoTotal, 13000);
    });

    test('mensual 90 días: 3 meses de 20% → 16,000 en 3 cuotas', () {
      final p = plan(10000, 20, 90, 'mensual');
      expect(p.cantidadCuotas, 3);
      expect(p.montoTotal, 16000);
      expect(p.cuota, 5333);
      expect(p.ultimaCuota, 5334);
    });

    test('mensual 45 días → se completa a 2 meses (40%)', () {
      final p = plan(10000, 20, 45, 'mensual');
      expect(p.cantidadCuotas, 2);
      expect(p.diasCobrados, 60);
      expect(p.montoTotal, 14000);
    });

    test('mismo monto y tasa: las 4 frecuencias cobran igual si el plazo cuadra', () {
      for (final f in frecuencias) {
        expect(plan(10000, 20, 30, f).montoTotal, f == 'semanal' ? 12333 : 12000,
            reason: f); // semanal: 30 días son 5 semanas (35 días)
      }
    });

    test('fechas mensuales: mismo día cada mes; el 31 cae al último día en meses cortos', () {
      expect(fechaCuota(DateTime(2026, 9, 15), 'mensual', 1), DateTime(2026, 10, 15));
      expect(fechaCuota(DateTime(2026, 11, 15), 'mensual', 2), DateTime(2027, 1, 15));
      expect(fechaCuota(DateTime(2027, 1, 31), 'mensual', 1), DateTime(2027, 2, 28));
      expect(fechaCuota(DateTime(2027, 1, 31), 'mensual', 2), DateTime(2027, 3, 31));
      expect(fechaCuota(DateTime(2027, 1, 31), 'mensual', 3), DateTime(2027, 4, 30));
    });

    test('fechas quincenales: cada 15 días', () {
      expect(fechaCuota(DateTime(2026, 9, 1), 'quincenal', 1), DateTime(2026, 9, 16));
      expect(fechaCuota(DateTime(2026, 9, 1), 'quincenal', 2), DateTime(2026, 10, 1));
    });

    test('nombres de cuotas y períodos', () {
      expect(nombreCuotas('diario'), 'cuotas diarias');
      expect(nombreCuotas('quincenal'), 'cuotas quincenales');
      expect(nombreCuotas('mensual', plural: false), 'cuota mensual');
      expect(nombrePeriodo('quincenal'), 'quincena');
      expect(nombrePeriodos('mensual'), 'meses');
    });

    test('tasa 0% → se devuelve exactamente el capital', () {
      expect(plan(3000, 0, 30, 'semanal').montoTotal, 3000);
    });

    test('datos inválidos se rechazan (antes: división por 0 o cuota 0)', () {
      expect(() => plan(1000, 20, 0, 'diario'), throwsArgumentError);
      expect(() => plan(1000, 20, 0, 'semanal'), throwsArgumentError);
      expect(() => plan(1000, 20, -5, 'diario'), throwsArgumentError);
      expect(() => plan(0, 20, 30, 'diario'), throwsArgumentError);
      expect(() => plan(1000, -1, 30, 'diario'), throwsArgumentError);
      expect(() => plan(10, 0, 30, 'diario'), throwsArgumentError); // 0.33/cuota
    });
  });

  group('Prestar vs Cobrar: recorrido de 1 a 90 días', () {
    test('cuotas enteras, la última absorbe, y lo guardado = lo prometido', () {
      final fallas = <String>[];
      for (final monto in [500.0, 1000.0, 2500.0, 5000.0, 7300.0, 10000.0, 25750.0]) {
        for (final tasa in [0.0, 5.0, 10.0, 20.0, 25.5]) {
          for (final frecuencia in frecuencias) {
            for (var dias = 1; dias <= 90; dias++) {
              final pl = plan(monto, tasa, dias, frecuencia);
              final caso = '$monto $tasa% $frecuencia $dias días';
              final n = pl.cantidadCuotas;
              final exacto = monto + monto * tasa / 100 * pl.diasCobrados / 30;

              if (pl.montoTotal != pl.montoTotal.roundToDouble()) fallas.add('$caso: total con centavos');
              if (pl.cuota != pl.cuota.roundToDouble()) fallas.add('$caso: cuota con centavos');
              if ((pl.montoTotal - exacto).abs() > 0.5) fallas.add('$caso: total mal redondeado');
              if (pl.cuota * (n - 1) + pl.ultimaCuota != pl.montoTotal) fallas.add('$caso: cuotas no suman el total');
              if (pl.ultimaCuota < pl.cuota || pl.ultimaCuota >= pl.cuota + n) {
                fallas.add('$caso: última cuota ${pl.ultimaCuota} vs cuota ${pl.cuota}');
              }
              // Períodos completos: cubre el plazo pedido sin pasarse de un período.
              final periodo = diasPorCuota(frecuencia);
              if (pl.diasCobrados < dias ||
                  pl.diasCobrados >= dias + periodo ||
                  pl.diasCobrados % periodo != 0) {
                fallas.add('$caso: plazo real ${pl.diasCobrados}');
              }

              final g = guardar(pl, monto: monto, tasa: tasa, frecuencia: frecuencia);
              final cron = generarCronograma(prestamo: g, totalPagado: 0);
              final suma = cron.fold<double>(0, (s, c) => s + (c['monto'] as double));
              if (montoTotalGuardado(g) != pl.montoTotal) fallas.add('$caso: guardado distinto');
              if (suma != pl.montoTotal) fallas.add('$caso: cronograma suma $suma');
              // Mensual va por calendario (1/9 → 1/10 → 1/11...), el resto por días.
              final fin = frecuencia == 'mensual'
                  ? DateTime(2026, 9 + n, 1)
                  : DateTime(2026, 9, 1).add(Duration(days: pl.diasCobrados));
              if (cron.last['fecha'] != fin) fallas.add('$caso: última cuota ${cron.last['fecha']} ≠ $fin');
            }
          }
        }
      }
      expect(fallas, isEmpty, reason: '${fallas.length} fallas. Ej:\n${fallas.take(10).join('\n')}');
    });
  });

  group('Cobrar: pagos parciales y cronograma', () {
    final p400 = guardar(plan(10000, 20, 30, 'diario'), monto: 10000, tasa: 20, frecuencia: 'diario');
    final p144 = guardar(plan(5000, 20, 45, 'diario'), monto: 5000, tasa: 20, frecuencia: 'diario');

    test('cuota exacta: 400 marca la #1, 200 ninguna, 600 una, 800 dos', () {
      expect(pagadas(p400, 400), 1);
      expect(pagadas(p400, 200), 0);
      expect(pagadas(p400, 600), 1);
      expect(pagadas(p400, 800), 2);
    });

    test('pago parcial: la cuota queda con lo que falta y Cobrar sugiere solo eso', () {
      expect(sugerido(p400, 0), 400);
      expect(sugerido(p400, 150), 250);
      expect(sugerido(p400, 550), 250); // #1 pagada, #2 con 150 abonados
    });

    test('cobrando cada vez lo sugerido se salda justo en el total (6,500)', () {
      var pagado = 0.0;
      var cobros = 0;
      while (!estaSaldado(p144, pagado)) {
        final s = sugerido(p144, pagado);
        expect(s, cobros < 44 ? 144 : 164, reason: 'cobro #${cobros + 1}');
        pagado += s;
        cobros++;
        expect(pagadas(p144, pagado), cobros);
      }
      expect(cobros, 45);
      expect(pagado, 6500);
      expect(proximoPago(p144, pagado), isNull);
    });

    test('pagar todo de una vez marca las 45 cuotas', () {
      expect(pagadas(p144, 6500), 45);
      expect(estaSaldado(p144, 6499), isFalse);
    });

    test('fechas diario: cuota #1 al día siguiente, la última el día 45', () {
      final c = generarCronograma(prestamo: p144, totalPagado: 0);
      expect(c.first['fecha'], DateTime(2026, 9, 2));
      expect(c.last['fecha'], DateTime(2026, 10, 16));
    });

    test('fechas semanal 30 días: 5 cuotas, la última a los 35 días', () {
      final g = guardar(plan(10000, 20, 30, 'semanal'), monto: 10000, tasa: 20, frecuencia: 'semanal');
      final c = generarCronograma(prestamo: g, totalPagado: 0);
      expect(c.map((x) => x['fecha']).toList(), [
        DateTime(2026, 9, 8),
        DateTime(2026, 9, 15),
        DateTime(2026, 9, 22),
        DateTime(2026, 9, 29),
        DateTime(2026, 10, 6),
      ]);
    });

    test('préstamo creado antes de monto_total (cuota 144.44): se salda con lo sugerido', () {
      final viejo = {...p144, 'cuota': 144.44, 'monto_total': null};
      expect(montoTotalGuardado(viejo), closeTo(6499.80, 0.001));
      expect(sugerido(viejo, 0), 144.44);
      expect(pagadas(viejo, 144.44), 1);
      var pagado = 0.0;
      for (var i = 0; i < 45; i++) {
        pagado += sugerido(viejo, pagado);
      }
      expect(estaSaldado(viejo, pagado), isTrue);
    });

    test('préstamo muy viejo (sin cantidad_cuotas) usa la fórmula plana y se puede saldar', () {
      final viejo = {'monto': 1000, 'tasa_interes': 20, 'cuota': 100, 'cantidad_cuotas': null};
      expect(montoTotalGuardado(viejo), 1200);
      expect(estaSaldado(viejo, 1200), isTrue);
    });
  });

  group('Reportes: coincide con Cobrar', () {
    final g = guardar(plan(10000, 20, 30, 'diario'), monto: 10000, tasa: 20, frecuencia: 'diario');
    final hoy = DateTime(2026, 9, 22);
    Map<String, dynamic> fila(Map<String, dynamic> p, double pagado) =>
        {...p, 'total_pagado': pagado};

    test('ganancia proyectada del mes = interés de los préstamos del mes', () {
      expect(gananciaDelMes([fila(g, 0)], hoy).proyectada, 2000);
    });

    test('"Ya llevas" = interés proporcional: de 3,000 cobrados, 500 son ganancia', () {
      final r = gananciaDelMes([fila(g, 3000)], hoy);
      expect(r.yaLlevas, closeTo(500, 0.001));
      expect(r.falta, closeTo(1500, 0.001));
    });

    test('"Ya llevas" suma la parte de interés de cada cuota del cronograma', () {
      final p144 = guardar(plan(5000, 20, 45, 'diario'), monto: 5000, tasa: 20, frecuencia: 'diario');
      final cron = generarCronograma(prestamo: p144, totalPagado: 288);
      final interesDosCuotas = (cron[0]['interes'] as double) + (cron[1]['interes'] as double);
      expect(interesCobrado(p144, 288), closeTo(interesDosCuotas, 0.001));
      expect(interesDosCuotas, closeTo(288 * 1500 / 6500, 0.001));
    });

    test('pagado completo → ya llevas toda la ganancia; un sobrepago no la infla', () {
      expect(gananciaDelMes([fila(g, 12000)], hoy).yaLlevas, closeTo(2000, 0.001));
      expect(gananciaDelMes([fila(g, 13000)], hoy).yaLlevas, closeTo(2000, 0.001));
      expect(gananciaDelMes([fila(g, 13000)], hoy).falta, 0);
    });

    test('préstamos de otro mes no cuentan', () {
      final agosto = {...g, 'fecha_desembolso': '2026-08-15'};
      expect(gananciaDelMes([fila(agosto, 3000)], hoy).proyectada, 0);
    });

    // Reportes usa la misma regla que Inicio (cobroDelDia), con el estado
    // calculado de los cobros.
    ({double atrasado, double venceHoy, int diasAtraso}) hoyDe(
            Map<String, dynamic> p, List<PagoRegistrado> pagos, DateTime dia) =>
        cobroDelDia(estadoPrestamo(p, pagos, dia), dia);
    List<PagoRegistrado> pago(double monto, {DateTime? fecha}) =>
        [PagoRegistrado(fecha: fecha ?? DateTime(2026, 9, 2), monto: monto)];

    test('cliente al día no sale atrasado aunque la columna proximo_pago esté vieja', () {
      final f = {...fila(g, 21 * 400), 'proximo_pago': '2026-09-02'};
      expect(proximoPago(f, 21 * 400), DateTime(2026, 9, 23));
      final d = hoyDe(f, pago(21 * 400), hoy);
      expect(d.atrasado, 0);
      expect(d.venceHoy, 0);
    });

    test('pagó 10 cuotas → la #11 venció el 12/9: 10 días de atraso', () {
      expect(proximoPago(g, 10 * 400), DateTime(2026, 9, 12));
      final d = hoyDe(g, pago(10 * 400), hoy);
      expect(d.atrasado, greaterThan(0));
      expect(d.diasAtraso, 10);
    });

    test('la cuota vence hoy → sale en "No han pagado hoy" con 0 días, sin atraso', () {
      final d = hoyDe(g, pago(20 * 400), hoy);
      expect(d.atrasado, 0);
      expect(d.venceHoy, 400);
      expect(d.diasAtraso, 0);
    });

    test('préstamo saldado no está atrasado', () {
      final d = hoyDe(g, pago(12000), DateTime(2026, 12, 1));
      expect(d.atrasado + d.venceHoy, 0);
    });

    test('los días de atraso cuentan desde la cuota SIN PAGAR, no desde una que solo debe mora', () {
      final conMora = {...g, 'mora_diaria': 5, 'dias_gracia': 1};
      // El 10/9 pagó las cuotas #1 y #2 (sin su mora); la #3 venció el 4/9.
      final d = hoyDe(conMora, pago(800, fecha: DateTime(2026, 9, 10)), hoy);
      expect(d.diasAtraso, 18);

      // Pagó todas las cuotas tarde y solo le queda la mora: atrasado, 0 días.
      final soloMora = hoyDe(conMora, pago(21 * 400, fecha: DateTime(2026, 9, 21)), hoy);
      expect(soloMora.atrasado, greaterThan(0));
      expect(soloMora.diasAtraso, 0);
    });

    test('al confirmar, proximo_pago = cuota #1 (mañana diario, en 7 días semanal)', () {
      expect(g['proximo_pago'], '2026-09-02');
      final s = guardar(plan(10000, 20, 30, 'semanal'), monto: 10000, tasa: 20, frecuencia: 'semanal');
      expect(s['proximo_pago'], '2026-09-08');
    });
  });
}
