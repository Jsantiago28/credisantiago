import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestamistas_rd/logic/fotos.dart';
import 'package:prestamistas_rd/screens/contrato_firmado_screen.dart';
import 'package:prestamistas_rd/services/supabase_service.dart';

void main() {
  test('los archivos del contrato van en la carpeta del prestamista; el PDF se reconoce', () {
    final pdf = rutaNuevaFoto(
        prestamistaId: 'abc', tipo: 'contrato', ahora: DateTime(2026, 10, 18), azar: 7, extension: 'pdf');
    expect(pdf, startsWith('abc/contrato_'));
    expect(esPdf(pdf), isTrue);
    expect(esPdf('abc/contrato_1_2.jpg'), isFalse);
  });

  test('la lista del contrato firmado se lee como viene de Supabase', () {
    expect(SupabaseService.contratoFirmadoDe({'contrato_firmado': ['a.pdf', 'b.jpg']}),
        ['a.pdf', 'b.jpg']);
    expect(SupabaseService.contratoFirmadoDe({}), isEmpty); // préstamo de antes
  });

  testWidgets('sin contrato: explica qué subir y ofrece fotos o PDF', (tester) async {
    tester.view.physicalSize = const Size(360, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(
      home: ContratoFirmadoScreen(prestamo: {'id': 'p', 'monto': 10000}, cliente: 'Juan Pérez'),
    ));
    expect(tester.takeException(), isNull);
    expect(find.text('Agregar fotos'), findsOneWidget);
    expect(find.text('Agregar PDF'), findsOneWidget);
    expect(find.textContaining('Solo tú puedes verlo'), findsOneWidget);
    expect(find.textContaining('Todavía no has subido'), findsOneWidget);
  });

  testWidgets('con un PDF subido lo muestra para abrirlo', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: ContratoFirmadoScreen(
          prestamo: {'id': 'p', 'monto': 10000, 'contrato_firmado': ['abc/contrato_1_2.pdf']},
          cliente: 'Juan Pérez'),
    ));
    expect(find.text('PDF 1'), findsOneWidget);
    expect(find.textContaining('Todavía no has subido'), findsNothing);
  });
}
