import 'package:flutter_test/flutter_test.dart';
import 'package:prestamistas_rd/logic/calculo_prestamo.dart';

/// Préstamo como lo guarda confirmarPrestamo con [desembolso].
Map<String, dynamic> prestamo(DateTime desembolso, String frecuencia) {
  final plan = calcularPlan(
      monto: 10000, tasaInteresMensual: 10, diasPlazo: 90, frecuencia: frecuencia,
      tipo: TipoInteres.saldo);
  return {
    'monto': 10000,
    'tasa_interes': 10,
    'frecuencia': frecuencia,
    'cantidad_cuotas': plan.cantidadCuotas,
    'cuota': plan.cuota,
    'monto_total': plan.montoTotal,
    'tipo_interes': 'saldo',
    'fecha_desembolso': fechaSql(desembolso),
  };
}

void main() {
  final hoy = DateTime(2026, 11, 1);

  group('Fecha del primer pago', () {
    test('la de siempre: un período después de hoy', () {
      expect(primerPagoNormal(hoy, 'diario'), DateTime(2026, 11, 2));
      expect(primerPagoNormal(hoy, 'semanal'), DateTime(2026, 11, 8));
      expect(primerPagoNormal(hoy, 'quincenal'), DateTime(2026, 11, 16));
      expect(primerPagoNormal(hoy, 'mensual'), DateTime(2026, 12, 1));
    });

    test('se guarda un período antes del primer pago', () {
      expect(baseParaPrimerPago(DateTime(2026, 11, 20), 'diario'), DateTime(2026, 11, 19));
      expect(baseParaPrimerPago(DateTime(2026, 11, 20), 'semanal'), DateTime(2026, 11, 13));
      expect(baseParaPrimerPago(DateTime(2026, 11, 20), 'quincenal'), DateTime(2026, 11, 5));
      expect(baseParaPrimerPago(DateTime(2026, 11, 20), 'mensual'), DateTime(2026, 10, 20));
      expect(baseParaPrimerPago(DateTime(2027, 1, 31), 'mensual'), DateTime(2026, 12, 31));
      expect(baseParaPrimerPago(DateTime(2027, 3, 28), 'mensual'), DateTime(2027, 2, 28));
    });

    test('mensual del 29 al 31 no se puede si el mes anterior es más corto', () {
      // Febrero 2027 tiene 28 días: no hay forma de que la cuota caiga el 30/3.
      expect(baseParaPrimerPago(DateTime(2027, 3, 30), 'mensual'), isNull);
      expect(baseParaPrimerPago(DateTime(2027, 3, 29), 'mensual'), isNull);
      // Mayo → junio: 31 de mayo existe pero 31 de junio no; 30/6 sí se puede.
      expect(baseParaPrimerPago(DateTime(2027, 6, 30), 'mensual'), DateTime(2027, 5, 30));
      expect(primerPagoPermitido(hoy, 'mensual', DateTime(2027, 3, 1)), isTrue); // 120 días
      expect(primerPagoPermitido(hoy, 'mensual', DateTime(2027, 3, 2)), isFalse); // 121
    });

    test('desde mañana y hasta 120 días', () {
      expect(primerPagoPermitido(hoy, 'diario', hoy), isFalse);
      expect(primerPagoPermitido(hoy, 'diario', DateTime(2026, 11, 2)), isTrue);
      expect(primerPagoPermitido(hoy, 'semanal', hoy.add(const Duration(days: 120))), isTrue);
      expect(primerPagoPermitido(hoy, 'semanal', hoy.add(const Duration(days: 121))), isFalse);
    });

    test('lo que se guarda como fecha del préstamo', () {
      expect(fechaDesembolsoParaPrimerPago(hoy, 'semanal', null), hoy);
      // Elegir la misma de siempre es lo mismo que no elegir.
      expect(fechaDesembolsoParaPrimerPago(hoy, 'semanal', DateTime(2026, 11, 8)), hoy);
      expect(fechaDesembolsoParaPrimerPago(hoy, 'semanal', DateTime(2026, 11, 20)),
          DateTime(2026, 11, 13));
      // Antes de lo normal: la fecha guardada queda antes de hoy.
      expect(fechaDesembolsoParaPrimerPago(hoy, 'mensual', DateTime(2026, 11, 15)),
          DateTime(2026, 10, 15));
      expect(() => fechaDesembolsoParaPrimerPago(hoy, 'diario', hoy), throwsArgumentError);
      expect(() => fechaDesembolsoParaPrimerPago(hoy, 'mensual', DateTime(2027, 3, 30)),
          throwsArgumentError);
    });

    test('el cronograma arranca en el primer pago elegido', () {
      final primer = DateTime(2026, 11, 20);
      final p = prestamo(fechaDesembolsoParaPrimerPago(hoy, 'mensual', primer), 'mensual');
      final c = generarCronograma(prestamo: p, totalPagado: 0);
      expect([for (final x in c) x['fecha']],
          [DateTime(2026, 11, 20), DateTime(2026, 12, 20), DateTime(2027, 1, 20)]);
      expect(proximoPago(p, 0), primer);
      // La primera cuota lleva el interés normal de un mes (10% de 10,000).
      expect(c.first['interes'], 1000);
    });

    test('semanal más tarde: no vence nada ni hay mora antes del primer pago', () {
      final primer = DateTime(2026, 11, 25);
      final p = {
        ...prestamo(fechaDesembolsoParaPrimerPago(hoy, 'semanal', primer), 'semanal'),
        'mora_diaria': 5,
      };
      final e = estadoPrestamo(p, const [], DateTime(2026, 11, 24));
      expect(e.moraPendiente, 0);
      expect(cobroDelDia(e, DateTime(2026, 11, 24)).atrasado, 0);
      expect(e.cuotas.first.fecha, primer);
    });
  });
}
