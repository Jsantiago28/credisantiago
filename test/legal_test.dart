import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestamistas_rd/screens/login_screen.dart';
import 'package:prestamistas_rd/screens/solicitud_publica_screen.dart';
import 'package:prestamistas_rd/widgets/legal.dart';
import 'package:prestamistas_rd/widgets/primeros_pasos.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> abrir(WidgetTester tester, Widget pantalla, {double alto = 1600}) async {
  tester.view.physicalSize = Size(400, alto);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(home: pantalla));
  await tester.pump();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('para registrarse hay que aceptar los Términos y la Privacidad', (tester) async {
    await abrir(tester, const LoginScreen());
    await tester.tap(find.text('Registrarme'));
    await tester.pump();
    expect(find.text('Términos de uso'), findsOneWidget);
    expect(find.text('Política de privacidad'), findsOneWidget);

    await tester.enterText(find.byType(TextField).at(0), 'juan@correo.com');
    await tester.enterText(find.byType(TextField).at(1), 'clave1234');
    await tester.enterText(find.byType(TextField).at(2), 'clave1234');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Crear cuenta'));
    await tester.pump();
    expect(find.textContaining('acepta los Términos'), findsOneWidget);
  });

  testWidgets('el cliente autoriza el uso de sus datos antes de enviar', (tester) async {
    await abrir(tester, const SolicitudPublicaScreen(slug: 'prueba', pasoInicial: 4));
    expect(find.textContaining('a guardar y usar mis datos'), findsOneWidget);
    expect(find.text('Política de privacidad'), findsOneWidget);
    expect(find.text('Términos de uso'), findsNothing); // el cliente no tiene cuenta
  });

  testWidgets('borrar la cuenta pide escribir BORRAR', (tester) async {
    await abrir(tester, const Scaffold(body: BotonBorrarCuenta(queSeBorra: 'Se borra todo.')));
    await tester.tap(find.text('Borrar mi cuenta'));
    await tester.pumpAndSettle();
    expect(find.text('Se borra todo.'), findsOneWidget);
    final boton = find.widgetWithText(TextButton, 'Borrar mi cuenta').last;
    expect(tester.widget<TextButton>(boton).onPressed, isNull);
    await tester.enterText(find.byType(TextField), 'borrar');
    await tester.pump();
    expect(tester.widget<TextButton>(boton).onPressed, isNotNull);
  });

  testWidgets('primeros pasos: marca lo hecho y se puede ocultar', (tester) async {
    await abrir(
      tester,
      Scaffold(
        body: ListView(children: [
          PrimerosPasos(
            perfil: const {'id': 'x', 'slug': 'mi-negocio', 'recibo_logo': 'x/logo.jpg'},
            tienePrestamos: false,
            onCambio: () {},
          ),
        ]),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Primeros pasos'), findsOneWidget);
    expect(find.text('1 de 5'), findsOneWidget); // solo el logo
    await tester.tap(find.text('Ocultar'));
    await tester.pump();
    expect(find.text('Primeros pasos'), findsNothing);
  });

  test('las páginas legales y la presentación existen y Cloudflare las sirve', () {
    for (final pagina in ['terminos', 'privacidad', 'borrar-cuenta', 'presentacion']) {
      final html = File('web/$pagina.html').readAsStringSync();
      expect(html, contains('<title>'), reason: pagina);
      expect(html, contains('/sitio.css'), reason: pagina);
    }
    // Reglas de Cloudflare Pages: sin comentarios ni líneas vacías.
    final reglas = File('web/_redirects')
        .readAsLinesSync()
        .map((r) => r.trim())
        .where((r) => r.isNotEmpty && !r.startsWith('#'))
        .toList();
    expect(reglas.first, startsWith('/ ')); // la presentación en la dirección principal
    expect(reglas.any((r) => r.startsWith('/s/*')), isTrue); // link de solicitudes
    expect(reglas.any((r) => r.startsWith('/i/*')), isTrue); // link de invitación
    // Cloudflare quita el ".html" solo: un destino con ".html" daría vueltas.
    expect(reglas.any((r) => r.contains('.html')), isFalse);
    expect(File('web/presentacion.html').readAsStringSync(), contains('no presta dinero'));
  });
}
