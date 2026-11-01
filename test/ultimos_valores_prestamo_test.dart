import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestamistas_rd/logic/ultimos_valores_prestamo.dart';
import 'package:prestamistas_rd/logic/whatsapp.dart';
import 'package:prestamistas_rd/screens/prestar_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

const valores = UltimosValoresPrestamo(
    tasa: 15, plazo: 3, enMeses: true, frecuencia: 'semanal', mora: 2.5, gracia: 3);

TextField campo(WidgetTester tester, String etiqueta) => tester.widget<TextField>(find.ancestor(
    of: find.text(etiqueta), matching: find.byType(TextField)));

Future<void> abrir(WidgetTester tester, PrestarScreen pantalla) async {
  tester.view.physicalSize = const Size(400, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(theme: ThemeData.dark(), home: pantalla));
  await tester.pump();
  await tester.pump();
}

void main() {
  group('Últimos valores del préstamo', () {
    test('se guardan y se leen igual', () {
      final v = UltimosValoresPrestamo.decodificar(valores.codificar())!;
      expect(v.tasa, 15);
      expect(v.plazo, 3);
      expect(v.enMeses, isTrue);
      expect(v.frecuencia, 'semanal');
      expect(v.mora, 2.5);
      expect(v.gracia, 3);
    });

    test('datos raros no se usan', () {
      expect(UltimosValoresPrestamo.decodificar(null), isNull);
      expect(UltimosValoresPrestamo.decodificar('basura'), isNull);
      expect(
          UltimosValoresPrestamo.decodificar(
              '{"tasa":20,"plazo":30,"frecuencia":"anual","mora":5,"gracia":1}'),
          isNull);
      expect(
          UltimosValoresPrestamo.decodificar(
              '{"tasa":-1,"plazo":30,"frecuencia":"diario","mora":5,"gracia":1}'),
          isNull);
    });

    test('número corto', () {
      expect(numeroCorto(20), '20');
      expect(numeroCorto(2.5), '2.5');
    });

    testWidgets('Prestar abre con los últimos valores', (tester) async {
      SharedPreferences.setMockInitialValues({'ultimos_valores_prestamo': valores.codificar()});
      await abrir(
          tester,
          const PrestarScreen(
              cliente: {'nombre': 'José'}, prestamo: {'id': 'p1', 'monto': 5000}));
      expect(campo(tester, 'Interés mensual (%)').controller!.text, '15');
      expect(campo(tester, 'Plazo total (meses)').controller!.text, '3');
      expect(campo(tester, 'Mora diaria (%)').controller!.text, '2.5');
      expect(campo(tester, 'Días de gracia').controller!.text, '3');
      expect(campo(tester, 'Monto a prestar (RD\$)').controller!.text, '5000');
    });

    testWidgets('lo que manda la calculadora gana', (tester) async {
      SharedPreferences.setMockInitialValues({'ultimos_valores_prestamo': valores.codificar()});
      await abrir(
          tester,
          const PrestarScreen(
            cliente: {'nombre': 'José'},
            prestamo: {'id': 'p1'},
            tasaInicial: 25,
            diasInicial: 45,
            frecuenciaInicial: 'diario',
          ));
      expect(campo(tester, 'Interés mensual (%)').controller!.text, '25');
      expect(campo(tester, 'Plazo total (días)').controller!.text, '45');
      expect(campo(tester, 'Mora diaria (%)').controller!.text, '2.5'); // no viene de la calculadora
    });

    testWidgets('sin nada guardado: 20%, 30 días', (tester) async {
      SharedPreferences.setMockInitialValues({});
      await abrir(tester, const PrestarScreen(cliente: {'nombre': 'José'}, prestamo: {'id': 'p1'}));
      expect(campo(tester, 'Interés mensual (%)').controller!.text, '20');
      expect(campo(tester, 'Plazo total (días)').controller!.text, '30');
    });
  });

  group('Mensajes al aprobar o rechazar una solicitud', () {
    test('aprobada: saluda por el primer nombre y dice el monto', () {
      final m = mensajeSolicitudAprobada(
          nombreCliente: 'José Martínez', negocio: 'Préstamos Núñez', monto: 15000);
      expect(m, startsWith('Hola José, le saluda Préstamos Núñez.'));
      expect(m, contains('RD\$15,000'));
      expect(m, contains('aprobada'));
    });

    test('aprobada sin monto ni nombre', () {
      final m = mensajeSolicitudAprobada(nombreCliente: '', negocio: 'Préstamos Núñez');
      expect(m, startsWith('Hola, le saluda'));
      expect(m, isNot(contains('RD\$')));
    });

    test('rechazada: amable, sin dar razones', () {
      final m = mensajeSolicitudRechazada(nombreCliente: 'Ana Gómez', negocio: 'Préstamos Núñez');
      expect(m, startsWith('Hola Ana, le saluda Préstamos Núñez.'));
      expect(m, contains('Gracias'));
      expect(m, contains('no podemos aprobarle'));
    });
  });
}
