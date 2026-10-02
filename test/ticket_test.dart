import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestamistas_rd/logic/calculo_prestamo.dart';
import 'package:prestamistas_rd/logic/ticket.dart';
import 'package:prestamistas_rd/recibos/imprimir_ticket.dart';
import 'package:prestamistas_rd/recibos/recibo_pdf.dart';

DatosRecibo recibo({bool saldado = false}) => DatosRecibo(
      numero: 125,
      fecha: DateTime(2026, 9, 30, 14, 5),
      monto: 1100,
      aCuota: 1000,
      aMora: 100,
      cubre: ['Cuota #3 (28/9/2026)', 'Abono a la cuota #4: RD\$ 60'],
      balanceDespues: saldado ? 0 : 8000,
      moraPendienteDespues: saldado ? 0 : 40,
      proximoPagoFecha: saldado ? null : DateTime(2026, 10, 7),
      proximoPagoMonto: saldado ? 0 : 1000,
      saldado: saldado,
    );

const negocio = NegocioRecibo(
  nombre: 'Inversiones Castillo',
  telefono: '809-555-1234',
  direccion: 'C/ Duarte #12, Santiago de los Caballeros',
  mensaje: 'Pague a tiempo y evite mora 🙏',
);

List<LineaTicket> lineas({int papel = 58, bool saldado = false, String? cobradoPor}) => lineasTicket(
      r: recibo(saldado: saldado),
      negocio: negocio,
      cliente: 'María Altagracia Rosario de los Santos',
      cedula: '001-1234567-8',
      cobradoPor: cobradoPor,
      papelMm: papel,
    );

void main() {
  test('ancho del papel', () {
    expect(anchoPapel(58), 32);
    expect(anchoPapel(80), 48);
  });

  test('dos columnas: el valor pegado a la derecha; si no cabe, baja', () {
    expect(filaDosColumnas('Balance', 'RD\$8,000', 20), ['Balance     RD\$8,000']);
    final largo = filaDosColumnas('María Altagracia Rosario', 'RD\$8,000', 20);
    expect(largo.last, '            RD\$8,000');
    expect(largo.every((l) => l.length <= 20), isTrue);
    // Un valor más largo que el papel se parte en varias líneas.
    final nombre = filaDosColumnas('Cliente', 'María Altagracia Rosario de los Santos', 20);
    expect(nombre.first, 'Cliente');
    expect(nombre.skip(1).join(' ').replaceAll(RegExp(r'\s+'), ' ').trim(),
        'María Altagracia Rosario de los Santos');
    expect(nombre.every((l) => l.length <= 20), isTrue);
  });

  for (final papel in [58, 80]) {
    test('ninguna línea se sale del papel de $papel mm', () {
      final ancho = anchoPapel(papel);
      for (final l in lineas(papel: papel, cobradoPor: 'Juan Pérez')) {
        expect(l.texto.length, lessThanOrEqualTo(l.grande ? ancho ~/ 2 : ancho), reason: l.texto);
      }
    });
  }

  test('lleva lo mismo que el recibo PDF', () {
    final texto = lineas(cobradoPor: 'Juan Pérez').map((l) => l.texto).join('\n');
    expect(texto, contains('INVERSIONES'));
    expect(texto, contains('Tel. 809-555-1234'));
    expect(texto, contains('RECIBO DE PAGO'));
    expect(texto, contains('#000125'));
    expect(texto, contains('30/9/2026 2:05 pm'));
    expect(texto, contains('Cédula'));
    expect(texto, contains('Cobrado por'));
    expect(texto, contains('MONTO RECIBIDO'));
    expect(texto, contains('RD\$1,100'));
    expect(texto, contains('  A mora'));
    expect(texto, contains('- Cuota #3 (28/9/2026)'));
    expect(texto, contains('Balance pendiente'));
    expect(texto, contains('Próximo pago'));
    expect(texto, contains('Pague a tiempo y evite mora'));
    // El nombre del negocio va grande, en negrita y centrado.
    final primera = lineas().first;
    expect(primera.grande && primera.negrita && primera.centro, isTrue);
  });

  test('saldado: lo dice y no trae próximo pago', () {
    final texto = lineas(saldado: true).map((l) => l.texto).join('\n');
    expect(texto, contains('PRÉSTAMO SALDADO'));
    expect(texto, isNot(contains('Próximo pago')));
    expect(texto, isNot(contains('Balance pendiente')));
  });

  test('sin cobrador no sale "Cobrado por"', () {
    expect(lineas().any((l) => l.texto.contains('Cobrado por')), isFalse);
  });

  test('acentos y ñ en la tabla PC850; emojis y comillas curvas no la dañan', () {
    expect(textoPc850('áéíóú ñÑ ¿¡'),
        [0xA0, 0x82, 0xA1, 0xA2, 0xA3, 0x20, 0xA4, 0xA5, 0x20, 0xA8, 0xAD]);
    expect(textoPc850('Núñez 💰'), [0x4E, 0xA3, 0xA4, 0x65, 0x7A, 0x20]);
    expect(String.fromCharCodes(textoPc850('“El Flaco” – ok')), '"El Flaco" - ok');
  });

  test('bytes ESC/POS: reinicia, pone la tabla PC850 y corta al final', () {
    final bytes = ticketEscPos(lineas());
    expect(bytes.sublist(0, 5), [0x1B, 0x40, 0x1B, 0x74, 2]);
    expect(bytes.sublist(bytes.length - 4), [0x1D, 0x56, 66, 0]);
    // Doble tamaño para el nombre del negocio.
    expect(_contiene(bytes, [0x1D, 0x21, 0x11]), isTrue);
    // El nombre del cliente con sus acentos.
    expect(_contiene(bytes, textoPc850('María')), isTrue);
  });

  testWidgets('hoja de imprimir: sin Bluetooth, lo explica y ofrece RawBT', (tester) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    int? papelPedido;
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData.dark(),
      home: Scaffold(
        body: HojaImprimir(bytes: (mm) {
          papelPedido = mm;
          return ticketEscPos(lineas(papel: mm));
        }),
      ),
    ));
    expect(tester.takeException(), isNull);
    expect(find.text('58 mm (chica)'), findsOneWidget);
    expect(find.textContaining('Este navegador no se conecta directo'), findsOneWidget);
    final bluetooth = tester.widget<ButtonStyleButton>(
        find.ancestor(of: find.text('Bluetooth directo'), matching: find.byWidgetPredicate((w) => w is ButtonStyleButton)));
    expect(bluetooth.onPressed, isNull);

    await tester.tap(find.text('80 mm (grande)'));
    await tester.pump();
    // Fuera de Android, RawBT avisa que no se puede.
    await tester.tap(find.text('Con la app RawBT (Android)'));
    await tester.pump();
    expect(papelPedido, 80);
    expect(find.textContaining('RawBT solo funciona en Android'), findsOneWidget);
  });
}

bool _contiene(List<int> todo, List<int> parte) {
  for (var i = 0; i + parte.length <= todo.length; i++) {
    var igual = true;
    for (var j = 0; j < parte.length; j++) {
      if (todo[i + j] != parte[j]) {
        igual = false;
        break;
      }
    }
    if (igual) return true;
  }
  return false;
}
