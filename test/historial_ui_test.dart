import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestamistas_rd/logic/historial.dart';
import 'package:prestamistas_rd/screens/editar_cliente_screen.dart';
import 'package:prestamistas_rd/widgets/historial_cliente.dart';

import 'ui_test.dart' show enTelefono;

void main() {
  testWidgets('historial: cambios largos caben en un teléfono', (tester) async {
    final f = DateTime(2026, 9, 24, 16, 30);
    await enTelefono(
      tester,
      Builder(
        builder: (context) => ElevatedButton(
          onPressed: () => verHistorialCliente(context, 'María Altagracia de los Santos', [
            CambioCliente(campo: 'direccion', antes: 'Calle Duarte #45, Los Alcarrizos, Santo Domingo Oeste', despues: 'Av. Independencia km 12, Residencial Las Palmas, edificio 4, apto 3B', fecha: f),
            CambioCliente(campo: 'telefono', antes: '809-555-1111', despues: '829-555-2222', fecha: f),
            CambioCliente(campo: 'ingreso_mensual', antes: null, despues: '35000', fecha: DateTime(2026, 9, 20)),
          ]),
          child: const Text('abrir'),
        ),
      ),
    );
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
    expect(find.text('809-555-1111'), findsOneWidget);
    expect(find.text('829-555-2222'), findsOneWidget);
    expect(find.text('RD\$35,000'), findsOneWidget);
    expect(find.text('24 sep 4:30 pm'), findsOneWidget);
  });

  testWidgets('Corregir datos: la sección de fotos cabe en un teléfono', (tester) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData.dark(),
      home: const EditarClienteScreen(cliente: {
        'id': 'c1',
        'prestamista_id': 'p1',
        'nombre': 'José Pérez',
        'cedula': '00112345678',
        'telefono': '8095551234',
      }),
    ));
    await tester.pump();
    expect(find.text('Cédula frente'), findsOneWidget);
    expect(find.text('Cambiar'), findsNWidgets(3));
  });
}
