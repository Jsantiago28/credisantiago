import 'package:flutter_test/flutter_test.dart';
import 'package:prestamistas_rd/logic/caja.dart';
import 'package:prestamistas_rd/logic/calculo_prestamo.dart';
import 'package:prestamistas_rd/logic/graficas.dart';
import 'package:prestamistas_rd/logic/ticket.dart';
import 'package:prestamistas_rd/recibos/recibo_pdf.dart';

/// 10,000 al 20% por 30 días diario desde el 1/9: 30 cuotas de 400, mora
/// 5% diario con 1 día de gracia.
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

PagoRegistrado cargo(double monto, {DateTime? fecha, String tipo = 'legal', int recibo = 1}) =>
    PagoRegistrado(
      id: 'c$recibo',
      numeroRecibo: recibo,
      fecha: fecha ?? DateTime(2026, 9, 2, 10),
      monto: monto,
      cargo: monto,
      cargoTipo: tipo,
      cargoNota: 'Carta del abogado',
    );

void main() {
  test('un cargo aparte no baja lo que debe: es ganancia aparte', () {
    final p = prestamo();
    final hoy = DateTime(2026, 9, 2, 12);
    final sin = estadoPrestamo(p, [], hoy);
    final con = estadoPrestamo(p, [cargo(500)], hoy);
    expect(con.balance, sin.balance);
    expect(con.cobradoCuotas, 0);
    expect(con.moraCobrada, 0);
    expect(con.cargosCobrados, 500);
    // La cuota #1 (vence el 2/9) sigue por cobrar entera.
    expect(con.cuotas.first.pendiente, 400);
    expect(con.proximoPago, sin.proximoPago);
  });

  test('después del cargo, la cuota normal se cobra igual', () {
    final p = prestamo();
    final dia = DateTime(2026, 9, 2, 12);
    final pagos = [
      cargo(500),
      PagoRegistrado(id: 'p2', numeroRecibo: 2, fecha: dia, monto: 400),
    ];
    final e = estadoPrestamo(p, pagos, dia);
    expect(e.cuotas.first.pagada, isTrue);
    expect(e.cobradoCuotas, 400);
    expect(e.cargosCobrados, 500);
  });

  test('un cargo anulado no cuenta', () {
    final p = prestamo();
    final anulado = PagoRegistrado(
        fecha: DateTime(2026, 9, 2), monto: 500, cargo: 500, cargoTipo: 'otro', anulado: true);
    expect(estadoPrestamo(p, [anulado], DateTime(2026, 9, 2)).cargosCobrados, 0);
    expect(cargosCobradosEnMes([anulado, cargo(300)], DateTime(2026, 9, 20)), 300);
  });

  test('el recibo dice el tipo, el motivo y que no baja el balance', () {
    final p = prestamo();
    final pago = cargo(500);
    final r = datosRecibo(p, [pago], pago);
    expect(r.aCargo, 500);
    expect(r.aCuota, 0);
    expect(r.cargoTipo, 'Gasto legal');
    expect(r.cargoNota, 'Carta del abogado');
    expect(r.cubre, isEmpty);
    expect(r.balanceDespues, estadoPrestamo(p, [], pago.fecha).balance);

    final texto = lineasTicket(
      r: r,
      negocio: const NegocioRecibo(nombre: 'Prueba'),
      cliente: 'Cliente',
    ).map((l) => l.texto).join('\n');
    expect(texto, contains('Gasto legal'));
    expect(texto, contains('Motivo: Carta del abogado'));
    expect(texto, contains('Cargo aparte: no baja el'));
    expect(texto, isNot(contains('A cuota')));
  });

  test('textoCargo junta el tipo y la nota', () {
    expect(textoCargo(cargo(100, tipo: 'interes')), 'Interés: Carta del abogado');
    expect(textoCargo(PagoRegistrado(fecha: DateTime(2026), monto: 100)), '');
  });

  test('la caja separa los cargos de las cuotas', () {
    final dia = DateTime(2026, 9, 2, 9);
    final d = cajaPorDia([
      CobroCaja(fecha: dia, monto: 400, cliente: 'A'),
      CobroCaja(fecha: dia, monto: 500, cargo: 500, cliente: 'B'),
    ]).single;
    expect(d.total, 900);
    expect(d.cargos, 500);
    expect(d.cuotas, 400);
    expect(resumenCajaTexto(d, negocio: 'Prueba'), contains('Cargos aparte: RD\$500'));
  });

  test('en las gráficas el cargo cuenta como ganancia, no como cuota', () {
    final hoy = DateTime(2026, 9, 30);
    final c = CobroGrafica(
        prestamoId: 'x', fecha: DateTime(2026, 9, 2), monto: 500, cargo: 500);
    expect(c.montoCuota, 0);
    final dia = cobradoPorDia([c], hoy).firstWhere((d) => d.dia == DateTime(2026, 9, 2));
    expect(dia.cuotas, 0);
    expect(dia.mora, 500);
  });
}
