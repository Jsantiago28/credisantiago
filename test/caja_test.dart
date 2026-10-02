import 'package:flutter_test/flutter_test.dart';
import 'package:prestamistas_rd/logic/caja.dart';

CobroCaja cobro(int recibo, DateTime fecha, double monto, String cliente,
        {double mora = 0, bool anulado = false}) =>
    CobroCaja(
        numeroRecibo: recibo,
        fecha: fecha,
        monto: monto,
        montoMora: mora,
        anulado: anulado,
        cliente: cliente);

void main() {
  final cobros = [
    cobro(1, DateTime(2026, 9, 22, 9, 15), 400, 'José Pérez'),
    cobro(2, DateTime(2026, 9, 23, 16, 40), 460, 'María Rosario', mora: 60),
    cobro(3, DateTime(2026, 9, 23, 8, 5), 400, 'José Pérez'),
    cobro(4, DateTime(2026, 9, 23, 10, 0), 4000, 'Luis Guzmán', anulado: true),
    cobro(5, DateTime(2026, 9, 20, 11, 0), 2466, 'Ana Castillo'),
  ];

  test('agrupa por día, el más reciente primero', () {
    final dias = cajaPorDia(cobros);
    expect(dias.map((d) => d.dia), [
      DateTime(2026, 9, 23),
      DateTime(2026, 9, 22),
      DateTime(2026, 9, 20),
    ]);
  });

  test('total del día sin los anulados, separado en cuotas y mora', () {
    final hoy = cajaPorDia(cobros).first;
    expect(hoy.total, 860);
    expect(hoy.cuotas, 800);
    expect(hoy.mora, 60);
    expect(hoy.cantidad, 2);
    expect(hoy.anulados, 1);
    expect(hoy.cobros.length, 3); // el anulado se sigue viendo (tachado)
  });

  test('los cobros del día van por hora', () {
    final hoy = cajaPorDia(cobros).first;
    expect(hoy.cobros.map((c) => c.numeroRecibo), [3, 4, 2]);
  });

  test('un día con solo cobros anulados suma 0', () {
    final d = cajaPorDia([cobro(9, DateTime(2026, 9, 1, 9), 500, 'X', anulado: true)]).single;
    expect(d.total, 0);
    expect(d.cantidad, 0);
    expect(d.anulados, 1);
  });

  test('clave del día para guardar el cierre', () {
    expect(claveDia(DateTime(2026, 9, 3)), '2026-09-03');
  });

  test('resumen para WhatsApp', () {
    final hoy = cajaPorDia(cobros).first;
    final texto = resumenCajaTexto(hoy, negocio: 'Préstamos Núñez', nota: 'Le entregué todo a Juan');
    expect(texto, contains('Caja del 23 sep 2026 — Préstamos Núñez'));
    expect(texto, contains('Total recibido: RD\$860 (2 cobros)'));
    expect(texto, contains('A mora: RD\$60'));
    expect(texto, contains('• 8:05 am José Pérez: RD\$400'));
    expect(texto, contains('• 4:40 pm María Rosario: RD\$460'));
    expect(texto, isNot(contains('Luis Guzmán')));
    expect(texto, contains('(1 cobro(s) anulado(s), no cuentan)'));
    expect(texto, contains('Nota: Le entregué todo a Juan'));
  });

  test('lee la fila de Supabase con el cliente embebido', () {
    final c = CobroCaja.desdeFila({
      'id': 'x',
      'numero_recibo': 12,
      'monto': 460,
      'monto_mora': 60,
      'fecha_pago': '2026-09-23T20:40:00Z',
      'anulado': false,
      'prestamos': {
        'clientes': {'nombre': 'María Rosario'}
      },
    });
    expect(c.cliente, 'María Rosario');
    expect(c.montoCuota, 400);
    expect(c.numeroRecibo, 12);
  });
}
