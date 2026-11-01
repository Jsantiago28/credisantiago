import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestamistas_rd/logic/borrador_solicitud.dart';
import 'package:prestamistas_rd/screens/solicitud_publica_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

BorradorSolicitud borrador(DateTime guardado, {Map<String, String>? textos}) => BorradorSolicitud(
      textos: textos ?? {'nombre': 'José Pérez', 'cedula': '001-1234567-8'},
      opciones: {'tipo_vivienda': 'propia', 'banco': null, 'lat': 18.5},
      paso: 2,
      guardado: guardado,
    );

void main() {
  final ahora = DateTime(2026, 11, 1, 10);

  group('Borrador de la solicitud', () {
    test('se guarda y se lee igual', () {
      final b = BorradorSolicitud.decodificar(borrador(ahora).codificar(), ahora)!;
      expect(b.textos['nombre'], 'José Pérez');
      expect(b.textos['cedula'], '001-1234567-8');
      expect(b.opciones['tipo_vivienda'], 'propia');
      expect(b.opciones['lat'], 18.5);
      expect(b.opciones.containsKey('banco'), isTrue);
      expect(b.paso, 2);
    });

    test('vence a los 2 días', () {
      final texto = borrador(ahora).codificar();
      expect(BorradorSolicitud.decodificar(texto, ahora.add(const Duration(days: 1, hours: 23))),
          isNotNull);
      expect(BorradorSolicitud.decodificar(texto, ahora.add(const Duration(days: 2, minutes: 1))),
          isNull);
    });

    test('sin nada escrito no hay borrador (las opciones solas no cuentan)', () {
      final vacio = borrador(ahora, textos: {'nombre': '  ', 'cedula': ''});
      expect(vacio.tieneDatos, isFalse);
      expect(BorradorSolicitud.decodificar(vacio.codificar(), ahora), isNull);
    });

    test('dañado o ausente: null, sin romperse', () {
      expect(BorradorSolicitud.decodificar(null, ahora), isNull);
      expect(BorradorSolicitud.decodificar('', ahora), isNull);
      expect(BorradorSolicitud.decodificar('{no es json', ahora), isNull);
      expect(BorradorSolicitud.decodificar('[1,2]', ahora), isNull);
      expect(BorradorSolicitud.decodificar('{"guardado":"ayer","textos":{}}', ahora), isNull);
    });

    test('cada link tiene su borrador', () {
      expect(claveBorrador('juan'), isNot(claveBorrador('pedro')));
    });

    test('guardar, leer y borrar en el navegador', () async {
      SharedPreferences.setMockInitialValues({});
      await guardarBorradorSolicitud('juan', borrador(ahora));
      expect((await leerBorradorSolicitud('juan', ahora: ahora))?.textos['nombre'], 'José Pérez');
      expect(await leerBorradorSolicitud('pedro', ahora: ahora), isNull);

      await borrarBorradorSolicitud('juan');
      expect(await leerBorradorSolicitud('juan', ahora: ahora), isNull);
    });

    test('el vencido se borra al leerlo', () async {
      SharedPreferences.setMockInitialValues({claveBorrador('juan'): borrador(ahora).codificar()});
      expect(await leerBorradorSolicitud('juan', ahora: ahora.add(const Duration(days: 3))),
          isNull);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(claveBorrador('juan')), isNull);
    });
  });

  group('Formulario público con borrador', () {
    Future<void> abrir(WidgetTester tester) async {
      tester.view.physicalSize = const Size(400, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(const MaterialApp(home: SolicitudPublicaScreen(slug: 'juan')));
      await tester.pump();
      await tester.pump();
    }

    testWidgets('recupera lo escrito y se puede empezar de nuevo', (tester) async {
      final guardado = BorradorSolicitud(
        textos: {'nombre': 'José Pérez', 'telefono': '829-444-7777'},
        guardado: DateTime.now(),
      );
      SharedPreferences.setMockInitialValues({claveBorrador('juan'): guardado.codificar()});
      await abrir(tester);

      expect(find.text('Recuperamos lo que habías escrito'), findsOneWidget);
      expect(find.text('José Pérez'), findsOneWidget);
      expect(find.text('829-444-7777'), findsOneWidget);

      await tester.tap(find.text('Borrar y empezar de nuevo'));
      await tester.pump();
      expect(find.text('Recuperamos lo que habías escrito'), findsNothing);
      expect(find.text('José Pérez'), findsNothing);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(claveBorrador('juan')), isNull);
    });

    testWidgets('lo que escribe se va guardando', (tester) async {
      SharedPreferences.setMockInitialValues({});
      await abrir(tester);
      expect(find.text('Recuperamos lo que habías escrito'), findsNothing);

      await tester.enterText(find.byType(TextField).first, 'Ana Gómez');
      await tester.pump();
      final b = await leerBorradorSolicitud('juan');
      expect(b?.textos['nombre'], 'Ana Gómez');
    });

    testWidgets('en el paso de fotos explica qué hacer si no abre la cámara', (tester) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = const Size(400, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
          const MaterialApp(home: SolicitudPublicaScreen(slug: 'juan', pasoInicial: 4)));
      await tester.pump();
      expect(find.textContaining('¿No se abre la cámara? Toca "Galería"'), findsOneWidget);
    });
  });
}
