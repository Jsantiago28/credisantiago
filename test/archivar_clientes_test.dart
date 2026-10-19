import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestamistas_rd/logic/archivo_clientes.dart';
import 'package:prestamistas_rd/screens/clientes_screen.dart';
import 'package:prestamistas_rd/services/supabase_service.dart';

void main() {
  test('archivado = tiene fecha de archivo', () {
    expect(estaArchivado({'id': '1'}), isFalse);
    expect(estaArchivado({'id': '1', 'archivado_en': null}), isFalse);
    expect(estaArchivado({'id': '1', 'archivado_en': '2026-10-18T05:00:00Z'}), isTrue);
  });

  test('solo un préstamo con dinero en la calle impide eliminar al cliente', () {
    for (final e in ['en_calle', 'por_cobrar', 'atrasado']) {
      expect(prestamoActivo(e), isTrue, reason: e);
    }
    for (final e in ['pagado', 'cancelado', 'borrador', null]) {
      expect(prestamoActivo(e), isFalse, reason: '$e');
    }
  });

  test('si la cédula es de un cliente eliminado, dice que se restaure', () {
    expect('${const ClienteRepetido('Ana')}', isNot(contains('Eliminados')));
    expect('${const ClienteRepetido('Ana', eliminado: true)}', contains('Eliminados'));
  });

  testWidgets('la pantalla de eliminados muestra cada cliente con Restaurar', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: ClientesEliminadosScreen(clientes: [
        {'id': '1', 'nombre': 'Ana Pérez', 'cedula': '001-0000000-1', 'archivado_en': 'x'},
        {'id': '2', 'nombre': 'Luis Gómez', 'archivado_en': 'x'},
      ]),
    ));
    expect(find.text('Ana Pérez'), findsOneWidget);
    expect(find.text('Luis Gómez'), findsOneWidget);
    expect(find.text('Restaurar'), findsNWidgets(2));
  });
}
