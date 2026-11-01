import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestamistas_rd/logic/caja.dart';
import 'package:prestamistas_rd/logic/calculo_prestamo.dart';
import 'package:prestamistas_rd/logic/cobradores.dart';
import 'package:prestamistas_rd/logic/ticket.dart';
import 'package:prestamistas_rd/recibos/recibo_pdf.dart';
import 'package:prestamistas_rd/screens/caja_screen.dart';
import 'package:prestamistas_rd/services/sin_conexion.dart';

/// Un día con Juan (cobrador) cobrando 1,000 en efectivo y 1,500 por
/// transferencia, y el prestamista 3,000 por transferencia.
DiaCaja dia() => cajaPorDia([
      CobroCaja(fecha: DateTime(2026, 11, 2, 8), monto: 1000, cliente: 'Ana', cobradorId: 'c1'),
      CobroCaja(
          fecha: DateTime(2026, 11, 2, 9),
          monto: 1500,
          cliente: 'Berta',
          cobradorId: 'c1',
          metodo: 'transferencia'),
      CobroCaja(
          fecha: DateTime(2026, 11, 2, 10),
          monto: 700,
          cliente: 'Carmen',
          cobradorId: 'c1',
          metodo: 'transferencia',
          anulado: true),
      CobroCaja(
          fecha: DateTime(2026, 11, 2, 11), monto: 3000, cliente: 'Elena', metodo: 'transferencia'),
    ]).single;

const juan = Cobrador(id: 'c1', nombre: 'Juan Pérez', email: 'juan@x.com');

void main() {
  group('Forma de pago en la caja', () {
    test('se lee de Supabase; los de antes son efectivo', () {
      final fila = {
        'id': 'x',
        'monto': 500,
        'fecha_pago': '2026-11-02T12:00:00Z',
        'prestamos': null,
      };
      expect(CobroCaja.desdeFila(fila).metodo, 'efectivo');
      expect(CobroCaja.desdeFila({...fila, 'metodo': 'transferencia'}).esTransferencia, isTrue);
    });

    test('el día separa efectivo y transferencia (sin anulados)', () {
      final d = dia();
      expect(d.total, 5500);
      expect(d.transferencia, 4500);
      expect(d.efectivo, 1000);
      expect(efectivoYTransferencia(d.efectivo, d.transferencia),
          'Efectivo RD\$1,000 · Transferencia RD\$4,500');
    });

    test('por cobrador: lo que tiene que entregar es solo el efectivo', () {
      final juanFila = cajaPorCobrador(dia()).firstWhere((f) => f.cobradorId == 'c1');
      expect(juanFila.total, 2500);
      expect(juanFila.efectivo, 1000);
      expect(cuadre(cobrado: juanFila.efectivo, entregado: 1000).texto, 'Cuadra');
    });

    test('el resumen por WhatsApp dice cuánto fue en efectivo y en transferencia', () {
      final texto = resumenCajaTexto(dia(), negocio: 'X', nombresCobradores: {'c1': 'Juan'});
      expect(texto, contains('Efectivo RD\$1,000 · Transferencia RD\$4,500'));
      expect(texto, contains('Berta: RD\$1,500 (transferencia)'));
      expect(texto, contains('• Juan: RD\$2,500 (2) · en efectivo RD\$1,000'));
    });

    testWidgets('caja del día: el total partido y la entrega cuadra con el efectivo',
        (tester) async {
      tester.view.physicalSize = const Size(360, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData.dark(),
        home: CajaDiaScreen(
          prestamistaId: 'p1',
          dia: dia(),
          cierre: null,
          gastos: const [],
          cobradores: const [juan],
          entregas: {
            'c1': Entrega(
                cobradorId: 'c1', fecha: DateTime(2026, 11, 2), cobrado: 1000, entregado: 1000),
          },
        ),
      ));
      expect(tester.takeException(), isNull);
      expect(find.text('Efectivo RD\$1,000 · Transferencia RD\$4,500'), findsOneWidget);
      // Juan cobró 2,500 pero 1,500 fue transferencia: con 1,000 cuadra.
      expect(find.text('Te entregó RD\$1,000 · Cuadra'), findsOneWidget);
      expect(find.textContaining('Cuando te entregó'), findsNothing);
    });
  });

  group('Forma de pago en el recibo', () {
    final prestamo = {
      'monto': 1000,
      'cuota': 550,
      'cantidad_cuotas': 2,
      'monto_total': 1100,
      'frecuencia': 'semanal',
      'fecha_desembolso': '2026-11-01',
    };

    test('el cobro guarda cómo se pagó', () {
      final p = PagoRegistrado.desdeFila({
        'monto': 550,
        'fecha_pago': '2026-11-08T12:00:00Z',
        'metodo': 'transferencia',
        'numero_recibo': 3,
      });
      expect(p.metodo, 'transferencia');
      expect(datosRecibo(prestamo, [p], p).metodo, 'Transferencia');
      final efectivo = PagoRegistrado(fecha: DateTime(2026, 11, 8), monto: 550, metodo: 'efectivo');
      expect(datosRecibo(prestamo, [efectivo], efectivo).metodo, 'Efectivo');
      // Sin método (o lo que traía un importado): el recibo no dice nada.
      final viejo = PagoRegistrado(fecha: DateTime(2026, 11, 8), monto: 550);
      expect(datosRecibo(prestamo, [viejo], viejo).metodo, isNull);
      expect(nombreMetodoPago('importado'), isNull);
    });

    test('el ticket dice la forma de pago', () {
      final p = PagoRegistrado(
          fecha: DateTime(2026, 11, 8), monto: 550, metodo: 'transferencia', numeroRecibo: 3);
      final lineas = lineasTicket(
        r: datosRecibo(prestamo, [p], p),
        negocio: const NegocioRecibo(nombre: 'X'),
        cliente: 'Ana',
      );
      expect(lineas.map((l) => l.texto),
          contains(filaDosColumnas('Forma de pago', 'Transferencia', 32).single));
    });

    test('el PDF sale con la forma de pago', () async {
      final p = PagoRegistrado(
          fecha: DateTime(2026, 11, 8), monto: 550, metodo: 'transferencia', numeroRecibo: 3);
      final bytes = await reciboPdf(
          r: datosRecibo(prestamo, [p], p), negocio: const NegocioRecibo(nombre: 'X'), cliente: 'Ana');
      expect(bytes, isNotEmpty);
    });
  });

  group('Cobro sin señal', () {
    test('guarda la forma de pago en el teléfono y la lleva al subir', () {
      final c = CobroPendiente(
          id: 'a',
          prestamoId: 'p',
          prestamistaId: 'j',
          monto: 500,
          montoMora: 0,
          fecha: DateTime(2026, 11, 2, 9),
          metodo: 'transferencia');
      final leido = CobroPendiente.desdeFila(c.aFila());
      expect(leido.metodo, 'transferencia');
      expect(leido.comoPago.metodo, 'transferencia');
      // Los que se guardaron antes de esto no traen método: son efectivo.
      expect(CobroPendiente.desdeFila(c.aFila()..remove('metodo')).metodo, 'efectivo');
    });
  });
}
