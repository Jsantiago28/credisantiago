import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestamistas_rd/logic/caja.dart';
import 'package:prestamistas_rd/logic/cobradores.dart';
import 'package:prestamistas_rd/logic/historial.dart';
import 'package:prestamistas_rd/screens/cobrador_shell.dart';
import 'package:prestamistas_rd/screens/cobradores_screen.dart';
import 'package:prestamistas_rd/widgets/selector_cobrador.dart';

const planes = [
  {'id': 'gratis', 'max_cobradores': 0},
  {'id': 'basico', 'max_cobradores': 1},
  {'id': 'pro', 'max_cobradores': 3},
  {'id': 'premium', 'max_cobradores': null},
];

final hoy = DateTime(2026, 9, 30, 10);

const juan = Cobrador(id: 'c1', nombre: 'Juan Pérez', email: 'juan@correo.com', userId: 'u1');
const pedro = Cobrador(id: 'c2', nombre: 'Pedro Díaz', email: 'pedro@correo.com');
const luis = Cobrador(id: 'c3', nombre: 'Luis Gómez', email: 'luis@correo.com', activo: false);

Future<void> enTelefono(WidgetTester tester, Widget pantalla, {double alto = 780}) async {
  tester.view.physicalSize = Size(360, alto);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(theme: ThemeData.dark(), home: pantalla));
}

void main() {
  group('Cobrador', () {
    test('estado: esperando, activo o desactivado', () {
      expect(pedro.estado, 'Esperando que entre');
      expect(juan.estado, 'Activo');
      expect(luis.estado, 'Desactivado');
    });

    test('lee la fila de Supabase', () {
      final c = Cobrador.desdeFila({
        'id': 'x',
        'nombre': 'Ana',
        'email': 'ana@correo.com',
        'telefono': '809-555-1234',
        'user_id': null,
        'activo': true,
      });
      expect(c.yaEntro, isFalse);
      expect(c.activo, isTrue);
      expect(c.telefono, '809-555-1234');
    });

    test('sesión del cobrador: datos del jefe para el recibo', () {
      final s = SesionCobrador.desdeFila({
        'cobrador_id': 'c1',
        'cobrador_nombre': 'Juan Pérez',
        'prestamista_id': 'p1',
        'nombre': 'Mitchell Castillo',
        'negocio': 'Inversiones Castillo',
        'whatsapp': '809-555-0000',
        'phone': null,
        'recibo_logo': 'p1/logo.jpg',
        'recibo_telefono': null,
        'recibo_direccion': 'Santiago',
        'recibo_mensaje': null,
      });
      expect(s.prestamistaId, 'p1');
      expect(s.negocio, 'Inversiones Castillo');
      expect(s.jefe['id'], 'p1');
      expect(s.jefe['recibo_logo'], 'p1/logo.jpg');
      expect(s.jefe['recibo_direccion'], 'Santiago');
      final sinNegocio = SesionCobrador.desdeFila({
        'cobrador_id': 'c1',
        'prestamista_id': 'p1',
        'nombre': 'Mitchell Castillo',
        'negocio': ' ',
      });
      expect(sinNegocio.negocio, 'Mitchell Castillo');
    });

    test('correo', () {
      expect(errorCorreo(''), isNotNull);
      expect(errorCorreo('juan'), isNotNull);
      expect(errorCorreo('juan@correo'), isNotNull);
      expect(errorCorreo(' Juan@Correo.com '), isNull);
    });

    test('límite por plan: igual que la base de datos', () {
      int? limite(Map<String, dynamic> perfil) =>
          limiteCobradores(perfil: perfil, planes: planes, hoy: hoy);
      expect(limite({'plan': 'gratis', 'aprobado': true}), 0);
      expect(limite({'plan': 'basico', 'plan_vence': '2026-10-30', 'aprobado': true}), 1);
      expect(limite({'plan': 'pro', 'plan_vence': '2026-10-30', 'aprobado': true}), 3);
      expect(limite({'plan': 'premium', 'plan_vence': '2026-10-30', 'aprobado': true}), isNull);
      // Vencido hace poco: 7 días de gracia con su plan. Pasados, Gratis.
      expect(limite({'plan': 'pro', 'plan_vence': '2026-09-29', 'aprobado': true}), 3);
      expect(limite({'plan': 'pro', 'plan_vence': '2026-09-22', 'aprobado': true}), 0);
      // Sin aprobar = 0.
      expect(limite({'plan': 'premium', 'plan_vence': '2026-12-01', 'aprobado': false}), 0);
      // Sin la migración (la tabla de planes no tiene la columna): 0.
      expect(
          limiteCobradores(
              perfil: {'plan': 'pro', 'plan_vence': '2026-10-30', 'aprobado': true},
              planes: const [{'id': 'pro'}],
              hoy: hoy),
          0);
    });

    test('mensaje para invitarlo por WhatsApp', () {
      final m = mensajeInvitacionCobrador(
          nombre: 'Juan Pérez',
          email: 'juan@correo.com',
          negocio: 'Inversiones Castillo',
          link: 'https://prestamistas-rd.netlify.app');
      expect(m, startsWith('Hola Juan, te agregué como cobrador de Inversiones Castillo.'));
      expect(m, contains('https://prestamistas-rd.netlify.app'));
      expect(m, contains('juan@correo.com'));
      expect(m, contains('código'));
    });

    test('repartir la ruta no sale en el historial del cliente', () {
      final fecha = DateTime(2026, 9, 30, 9);
      final ediciones = agruparCambios([
        CambioCliente(campo: 'cobrador_id', antes: null, despues: 'c1', fecha: fecha),
        CambioCliente(
            campo: 'telefono', antes: '809-000-0000', despues: '809-111-1111', fecha: fecha),
        CambioCliente(campo: 'cobrador_id', antes: 'c1', despues: 'c2', fecha: DateTime(2026, 9, 30, 11)),
      ]);
      expect(ediciones.length, 1);
      expect(ediciones.single.cambios.map((c) => c.campo), ['telefono']);
    });
  });

  group('Pantallas', () {
    testWidgets('tarjeta del cobrador: estado, clientes y botones', (tester) async {
      await enTelefono(
        tester,
        Scaffold(
          body: ListView(children: [
            TarjetaCobrador(
                cobrador: pedro,
                clientes: 12,
                onRepartir: () {},
                onInvitar: () {},
                onCambiarActivo: () {}),
            TarjetaCobrador(
                cobrador: luis,
                clientes: 0,
                onRepartir: () {},
                onInvitar: () {},
                onCambiarActivo: () {}),
          ]),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('Esperando que entre'), findsOneWidget);
      expect(find.text('12 clientes en su ruta'), findsOneWidget);
      expect(find.text('Mándale cómo entrar por WhatsApp.'), findsOneWidget);
      expect(find.text('Repartir clientes'), findsOneWidget); // solo el activo
      expect(find.text('Activar de nuevo'), findsOneWidget);
    });

    testWidgets('formulario: pide nombre, correo y WhatsApp válidos', (tester) async {
      await enTelefono(tester, const Scaffold(body: FormularioCobrador(prestamistaId: 'p1')));
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Guardar y mandarle cómo entrar'));
      await tester.pump();
      expect(find.text('Escribe el correo del cobrador'), findsOneWidget);
    });

    testWidgets('repartir: marca los suyos y avisa de quién es cada cliente', (tester) async {
      await enTelefono(
        tester,
        const RepartirClientesScreen(
          prestamistaId: 'p1',
          cobrador: juan,
          clientes: [
            {'id': 'a', 'nombre': 'Ana Rosario', 'direccion': 'Los Jardines', 'cobrador_id': 'c1'},
            {'id': 'b', 'nombre': 'Bernardo Núñez', 'direccion': 'Gurabo', 'cobrador_id': 'c2'},
            {'id': 'c', 'nombre': 'Carmen Peña', 'direccion': null, 'cobrador_id': null},
          ],
          cobradores: [juan, pedro],
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('Guardar (1 cliente)'), findsOneWidget);
      expect(find.textContaining('Lo cobra Pedro Díaz'), findsOneWidget);

      await tester.tap(find.text('Bernardo Núñez'));
      await tester.pump();
      expect(find.text('Guardar (2 clientes)'), findsOneWidget);
      expect(find.textContaining('Pasa de Pedro Díaz a Juan'), findsOneWidget);

      // Buscar sin acentos.
      await tester.enterText(find.byType(TextField), 'nunez');
      await tester.pump();
      expect(find.text('Ana Rosario'), findsNothing);
      expect(find.text('Bernardo Núñez'), findsOneWidget);
    });

    testWidgets('ficha: "Le cobra" con los activos (y el actual aunque esté sin acceso)',
        (tester) async {
      await enTelefono(
        tester,
        const Scaffold(
          body: SelectorCobrador(
            cliente: {'id': 'a', 'prestamista_id': 'p1', 'cobrador_id': 'c3'},
            cobradores: [juan, pedro, luis],
          ),
        ),
      );
      expect(find.text('Luis Gómez (sin acceso)'), findsOneWidget);
      await tester.tap(find.byType(DropdownButton<String?>));
      await tester.pumpAndSettle();
      expect(find.text('Lo cobro yo'), findsWidgets);
      expect(find.text('Juan Pérez'), findsWidgets);
    });

    testWidgets('ficha: sin cobradores no sale nada', (tester) async {
      await enTelefono(
        tester,
        const Scaffold(
          body: SelectorCobrador(
            cliente: {'id': 'a', 'prestamista_id': 'p1', 'cobrador_id': null},
            cobradores: [luis],
          ),
        ),
      );
      expect(find.text('Le cobra:'), findsNothing);
    });

    testWidgets('mi caja del cobrador: lo que entrega hoy', (tester) async {
      final ahora = DateTime.now();
      await enTelefono(
        tester,
        MiCajaCobrador(cobros: [
          CobroCaja(
              numeroRecibo: 20,
              fecha: DateTime(ahora.year, ahora.month, ahora.day, 9),
              monto: 1100,
              montoMora: 100,
              cliente: 'María Altagracia Rosario de los Santos'),
          CobroCaja(
              numeroRecibo: 21,
              fecha: DateTime(ahora.year, ahora.month, ahora.day, 10),
              monto: 500,
              anulado: true,
              cliente: 'José Pérez'),
        ]),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('RD\$1,100'), findsWidgets);
      expect(find.text('1 cobro'), findsOneWidget);
      expect(find.text('Esto es lo que entregas'), findsOneWidget);
      expect(find.textContaining('ANULADO por tu jefe'), findsOneWidget);
    });
  });
}

// ---------------------------------------------------------------------
// Parte 4: caja por cobrador y cuadre de la entrega.
// ---------------------------------------------------------------------

DiaCaja diaConCobradores() => cajaPorDia([
      CobroCaja(fecha: DateTime(2026, 9, 30, 8), monto: 1000, cliente: 'Ana', cobradorId: 'c1'),
      CobroCaja(
          fecha: DateTime(2026, 9, 30, 9),
          monto: 1500,
          montoMora: 100,
          cliente: 'Bernardo',
          cobradorId: 'c1'),
      CobroCaja(fecha: DateTime(2026, 9, 30, 10), monto: 800, cliente: 'Carmen', cobradorId: 'c2'),
      CobroCaja(
          fecha: DateTime(2026, 9, 30, 11),
          monto: 9999,
          anulado: true,
          cliente: 'Dario',
          cobradorId: 'c2'),
      CobroCaja(fecha: DateTime(2026, 9, 30, 12), monto: 3000, cliente: 'Elena'),
    ]).single;

