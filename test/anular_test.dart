import 'package:flutter_test/flutter_test.dart';
import 'package:prestamistas_rd/logic/calculo_prestamo.dart';

/// 10,000 al 20% por 30 días diario desde el 1/9, mora 5% con 1 día de
/// gracia: 30 cuotas de 400; la #k vence el (1 + k)/9.
Map<String, dynamic> prestamo() {
  final plan = calcularPlan(
      monto: 10000, tasaInteresMensual: 20, diasPlazo: 30, frecuencia: 'diario');
  return {
    'monto': 10000.0,
    'cuota': plan.cuota,
    'cantidad_cuotas': plan.cantidadCuotas,
    'monto_total': plan.montoTotal,
    'frecuencia': 'diario',
    'fecha_desembolso': '2026-09-01',
    'mora_diaria': 5.0,
    'dias_gracia': 1,
  };
}

DateTime sep(int dia, [int hora = 10]) => DateTime(2026, 9, dia, hora);

PagoRegistrado pago(int numero, DateTime fecha, double monto,
        {double mora = 0, bool anulado = false}) =>
    PagoRegistrado(
      id: 'p$numero',
      numeroRecibo: numero,
      fecha: fecha,
      monto: monto,
      montoMora: mora,
      anulado: anulado,
      motivoAnulacion: anulado ? 'mal digitado' : null,
    );

void main() {
  test('un cobro anulado no cuenta: da lo mismo que si no existiera', () {
    final p = prestamo();
    final conAnulado = estadoPrestamo(
        p, [pago(1, sep(2), 400), pago(2, sep(3), 4000, anulado: true)], sep(3, 18));
    final sinEl = estadoPrestamo(p, [pago(1, sep(2), 400)], sep(3, 18));
    expect(conAnulado.balance, sinEl.balance);
    expect(conAnulado.balance, 11600);
    expect(conAnulado.cobradoCuotas, 400);
    expect(conAnulado.proximoPago, sinEl.proximoPago);
  });

  test('si se salda por error y se anula ese cobro, deja de estar saldado', () {
    final p = prestamo();
    expect(estadoPrestamo(p, [pago(1, sep(2), 12000)], sep(2, 18)).saldado, isTrue);
    final anulado = estadoPrestamo(p, [pago(1, sep(2), 12000, anulado: true)], sep(2, 18));
    expect(anulado.saldado, isFalse);
    expect(anulado.balance, 12000);
  });

  test('al anular un cobro, la mora vuelve a correr desde su vencimiento', () {
    final p = prestamo();
    // Cobró la #1 el 2/9 y la anuló: el 5/9 la #1 debe 2 días de mora (40).
    final e = estadoPrestamo(p, [pago(1, sep(2), 400, anulado: true)], sep(5));
    expect(e.cuotas[0].pendiente, 400);
    expect(e.cuotas[0].moraPendiente, 40);
  });

  test('mora pagada de más no se pierde: pasa a las cuotas', () {
    final p = prestamo();
    // Cobro con 50 "a mora" cuando no había mora (quedó así por una anulación).
    final e = estadoPrestamo(p, [pago(1, sep(2), 450, mora: 50)], sep(2, 18));
    expect(e.moraCobrada, 0);
    expect(e.cobradoCuotas, 450);
    expect(e.balance, 12000 - 450);
    expect(e.cuotas[1].pendiente, 350); // la #2 recibió los 50
  });

  test('el recibo de un cobro anulado no se puede generar', () {
    final p = prestamo();
    final malo = pago(1, sep(2), 4000, anulado: true);
    expect(() => datosRecibo(p, [malo], malo), throwsArgumentError);
  });

  test('los recibos siguientes se calculan sin el cobro anulado', () {
    final p = prestamo();
    final malo = pago(1, sep(2, 9), 4000, anulado: true);
    final bueno = pago(2, sep(2, 11), 400);
    final r = datosRecibo(p, [malo, bueno], bueno);
    expect(r.cubre, ['Cuota #1 (2/9/2026)']);
    expect(r.balanceDespues, 11600);
    expect(r.numero, 2); // el #1 queda anulado; no se reusa
  });

  test('la mora cobrada del mes no cuenta cobros anulados', () {
    final pagos = [
      pago(1, sep(4), 420, mora: 20),
      pago(2, sep(5), 460, mora: 60, anulado: true),
    ];
    expect(moraCobradaEnMes(pagos, sep(20)), 20);
  });

  test('pagosValidos quita los anulados', () {
    final lista = [pago(1, sep(2), 400), pago(2, sep(3), 400, anulado: true)];
    expect(pagosValidos(lista).map((x) => x.id), ['p1']);
  });

  test('lee la marca de anulado de la base de datos', () {
    final p = PagoRegistrado.desdeFila({
      'id': 'x',
      'monto': 400,
      'fecha_pago': '2026-09-02T14:00:00Z',
      'anulado': true,
      'anulado_en': '2026-09-02T15:00:00Z',
      'motivo_anulacion': 'puse 4000',
    });
    expect(p.anulado, isTrue);
    expect(p.motivoAnulacion, 'puse 4000');
    expect(p.anuladoEn, isNotNull);
    // Pagos viejos (antes de la migración) no traen la columna: no anulados.
    expect(PagoRegistrado.desdeFila({'monto': 400, 'fecha_pago': '2026-09-02T14:00:00Z'}).anulado,
        isFalse);
  });
}
