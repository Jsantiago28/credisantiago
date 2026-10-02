import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestamistas_rd/logic/calculo_prestamo.dart';
import 'package:prestamistas_rd/logic/importar.dart';
import 'package:prestamistas_rd/screens/importar_screen.dart';

final hoy = DateTime(2026, 9, 30, 10);

const titulos = [
  'Nombre y apellido', 'Cédula', 'Teléfono', 'Dirección', 'Monto prestado',
  'Interés mensual %', 'Frecuencia', 'Plazo en días', 'Fecha del préstamo', 'Ya pagó',
  'Mora diaria %', 'Días de gracia',
];

({List<FilaImportada> filas, List<String> faltan}) revisar(List<List<Object?>> filas,
        {Set<String> existentes = const {}}) =>
    revisarArchivo([titulos, ...filas], cedulasExistentes: existentes, hoy: hoy);

void main() {
  test('reconoce los títulos aunque estén escritos distinto', () {
    final c = columnasDe(['CLIENTE', 'cedula', 'Celular', null, 'Capital', 'Tasa', 'Fecha']);
    expect(c['nombre'], 0);
    expect(c['cedula'], 1);
    expect(c['telefono'], 2);
    expect(c['monto'], 4);
    expect(c['interes'], 5);
    expect(c['fecha'], 6);
  });

  test('sin nombre, cédula o teléfono en los títulos: dice cuál falta', () {
    final r = revisarArchivo([
      ['Nombre', 'Dirección']
    ], cedulasExistentes: const {}, hoy: hoy);
    expect(r.faltan, ['Cédula', 'Teléfono']);
    expect(r.filas, isEmpty);
  });

  test('cliente sin préstamo: pone guiones a la cédula y al teléfono', () {
    final f = revisar([
      ['  María   Gómez ', '40276543210', '18295556789', 'Los Jardines'],
    ]).filas.single;
    expect(f.lista, isTrue);
    expect(f.fila, 2);
    expect(f.cliente['nombre'], 'María Gómez');
    expect(f.cliente['cedula'], '402-7654321-0');
    expect(f.cliente['telefono'], '829-555-6789');
    expect(f.cliente['direccion'], 'Los Jardines');
    expect(f.prestamo, isNull);
  });

  test('cliente con préstamo en la calle', () {
    final f = revisar([
      ['Juan Pérez', '001-1234567-8', '809-555-1234', null, 'RD\$ 10,000', 0.2, 'Semanal', 60,
          '1/9/2026', 4000, null, null],
    ]).filas.single;
    expect(f.errores, isEmpty);
    final p = f.prestamo!;
    expect(p.monto, 10000);
    expect(p.interesMensual, 20); // 0.2 = 20% (celda con formato de %)
    expect(p.frecuencia, 'semanal');
    expect(p.diasPlazo, 60);
    expect(p.fecha, DateTime(2026, 9, 1));
    expect(p.yaPago, 4000);
    expect(p.moraDiaria, 5); // lo de siempre si no lo trae
    expect(p.diasGracia, 1);
  });

  test('fechas: de Excel, número de serie, día/mes/año y año-mes-día', () {
    DateTime? fecha(Object v) => revisar([
          ['Juan Pérez', '00112345678', '8095551234', null, 1000, 20, 'diario', 30, v],
        ]).filas.single.prestamo?.fecha;
    expect(fecha(DateTime(2026, 9, 1, 15)), DateTime(2026, 9, 1));
    expect(fecha(46266), DateTime(2026, 9, 1)); // número de serie de Excel
    expect(fecha('01/09/2026'), DateTime(2026, 9, 1));
    expect(fecha('1-9-26'), DateTime(2026, 9, 1));
    expect(fecha('2026-09-01'), DateTime(2026, 9, 1));
    expect(fecha('31/02/2026'), isNull); // no existe
  });

  test('errores: cada uno en palabras', () {
    final filas = revisar([
      ['Juan', '001-123', '555-1234'],
      ['Ana Pérez', '00112345678', '8095551234', null, 5000, null, 'anual', 0, '5/10/2026', -1],
      ['Luis Díaz', '00112345679', '8095551234', null, 1000, 20, 'mensual', 30, '1/9/2026', 999999],
    ]).filas;
    expect(filas[0].errores, [
      'Escribe nombre y apellido',
      'La cédula lleva 11 dígitos (tiene 6)',
      'El teléfono lleva 10 dígitos (ej. 809-555-1234)',
    ]);
    expect(filas[1].errores, containsAll([
      'Falta el interés mensual',
      'Frecuencia no válida: usa diario, semanal, quincenal o mensual',
      'Falta el plazo en días',
      'La fecha del préstamo es después de hoy',
      '"Ya pagó" no puede ser negativo',
    ]));
    expect(filas[2].errores.single, startsWith('"Ya pagó" es más que el total del préstamo'));
    expect(filas.every((f) => !f.lista), isTrue);
  });

  test('repetidos: con la app y dentro del mismo archivo; las filas vacías no cuentan', () {
    final filas = revisar([
      ['Juan Pérez', '001-1234567-8', '8095551234'],
      [null, '', null],
      ['Juan P. Pérez', '00112345678', '8095551234'],
      ['Ana Gómez', '40276543210', '8295556789'],
    ], existentes: {'40276543210'}).filas;
    expect(filas.length, 3);
    expect(filas.map((f) => f.lista), [true, false, false]);
    expect(filas[1].repetido, isTrue);
    expect(filas[1].fila, 4);
    expect(filas[2].repetido, isTrue);
  });

  test('el préstamo importado queda con su cronograma y lo pagado cubre las primeras cuotas', () {
    final p = ejemplo;
    final datos = p.datos();
    expect(datos['estado'], 'en_calle');
    expect(datos['fecha_desembolso'], '2026-09-01');
    final plan = calcularPlan(
        monto: 10000, tasaInteresMensual: 20, diasPlazo: 60, frecuencia: 'semanal');
    expect(datos['monto_total'], plan.montoTotal);
    expect(datos['cantidad_cuotas'], plan.cantidadCuotas);

    // Como lo guarda la app: un cobro "importado" el día del préstamo.
    final pagos = [PagoRegistrado(fecha: DateTime(2026, 9, 1, 12), monto: p.yaPago)];
    final estado = estadoPrestamo(datos, pagos, hoy);
    expect(estado.cobradoCuotas, p.yaPago);
    // Lo pagado cubre cuotas enteras sin mora.
    expect(estado.cuotas.where((c) => c.pagada && c.moraPendiente == 0).length,
        (p.yaPago / plan.cuota).floor());
    expect(estado.balance, greaterThanOrEqualTo(plan.montoTotal - p.yaPago));
  });

  test('si ya pagó todo, entra como saldado', () {
    final p = ejemplo;
    final total = p.montoTotal;
    final saldado = PrestamoImportado(
        monto: 10000,
        interesMensual: 20,
        frecuencia: 'semanal',
        diasPlazo: 60,
        fecha: DateTime(2026, 7, 1),
        yaPago: total);
    expect(saldado.datos()['estado'], 'pagado');
  });

  test('CSV con punto y coma y comillas', () {
    final celdas = leerCsv('﻿Nombre;Cédula;Teléfono;Dirección\n'
        '"Pérez; Juan";001-1234567-8;809-555-1234;"C/ ""A"" #5"\n');
    expect(celdas[1], ['Pérez; Juan', '001-1234567-8', '809-555-1234', 'C/ "A" #5']);
  });

  test('la plantilla se puede leer de vuelta', () {
    final celdas = leerCeldas(plantillaExcel(), 'plantilla.xlsx');
    expect(celdas.first.take(3), ['Nombre y apellido', 'Cédula', 'Teléfono']);
    final r = revisarArchivo(celdas, cedulasExistentes: const {}, hoy: hoy);
    expect(r.faltan, isEmpty);
    expect(r.filas.length, 2);
    expect(r.filas.every((f) => f.lista), isTrue);
    expect(r.filas.first.prestamo?.yaPago, 4000);
    expect(r.filas.last.prestamo, isNull);
  });

  testWidgets('pantalla: resumen, botón y cada fila, en un teléfono', (tester) async {
    tester.view.physicalSize = const Size(360, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final filas = revisar([
      ['Juan Pérez', '001-1234567-8', '809-555-1234', null, 10000, 20, 'semanal', 60, '1/9/2026', 4000],
      ['María Altagracia Rosario de los Santos', '40276543210', '8295556789'],
      ['Ana Gómez', '00112345678', '8095551234'],
      ['Luis', '123', '555'],
    ]).filas;
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData.dark(),
      home: ImportarScreen(prestamistaId: 'p1', filas: filas),
    ));
    expect(tester.takeException(), isNull);
    expect(find.text('2 listo(s)'), findsOneWidget);
    expect(find.text('1 con préstamo'), findsOneWidget);
    expect(find.text('1 ya existe(n)'), findsOneWidget);
    expect(find.text('1 con errores'), findsOneWidget);
    expect(find.text('Importar 2 cliente(s)'), findsOneWidget);
    expect(find.textContaining('Préstamo RD\$10,000 semanal del 1 sep 2026'), findsOneWidget);
    expect(find.text('Ya tienes un cliente con esa cédula: no se importa'), findsOneWidget);
  });
}

/// Un préstamo de ejemplo: 10,000 al 20% semanal a 60 días, desde el 1/9, ya pagó 4,000.
final ejemplo = PrestamoImportado(
  monto: 10000,
  interesMensual: 20,
  frecuencia: 'semanal',
  diasPlazo: 60,
  fecha: DateTime(2026, 9, 1),
  yaPago: 4000,
);
