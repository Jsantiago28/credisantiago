// Arma un NEGOCIO DE DEMOSTRACIÓN (30 clientes, 2 cobradores, préstamos de
// todos los tipos, cobros, atrasos, promesas, gastos, cierres de caja y
// solicitudes) para la cuenta que se le diga, y lo escribe como SQL.
//
//   dart run tool/negocio_demo.dart <id-del-prestamista> > demo.sql
//
// Los préstamos y cobros salen de lib/logic/calculo_prestamo.dart (lo mismo
// que usa la app), así cuotas, mora y balances cuadran con lo que se ve.
// Todo lo de la demo tiene ids que empiezan con "de300000" y se borra con
// supabase/demo_borrar.sql. Nada es de personas reales: cédulas 999-...,
// teléfonos 809-555-..., correos @example.com.

import 'dart:io';
import 'dart:math';

import 'package:prestamistas_rd/logic/calculo_prestamo.dart' as calc;

final _azar = Random(2026);
var _contador = 0;

/// Ids reconocibles de la demo.
String _id() =>
    'de300000-0000-4000-8000-${(++_contador).toRadixString(16).padLeft(12, '0')}';

String _q(Object? v) {
  if (v == null) return 'null';
  if (v is num || v is bool) return '$v';
  return "'${v.toString().replaceAll("'", "''")}'";
}

/// Fecha y hora de República Dominicana (UTC-4, sin horario de verano).
String _ts(DateTime f) => "'${f.toIso8601String().substring(0, 19)}-04:00'";

T _uno<T>(List<T> l) => l[_azar.nextInt(l.length)];

final hoy = DateTime.now();
final hoyDia = DateTime(hoy.year, hoy.month, hoy.day);
DateTime _dia(int desdeHoy) => hoyDia.add(Duration(days: desdeHoy));

/// Una hora del día para un cobro; si es hoy, antes de ahora.
DateTime _hora(DateTime dia) {
  final tope = dia == hoyDia ? max(9, hoy.hour) : 18;
  final h = 8 + _azar.nextInt(max(1, tope - 8));
  return DateTime(dia.year, dia.month, dia.day, h, _azar.nextInt(60));
}

const _nombres = [
  'María Altagracia Rodríguez',
  'José Miguel Peña',
  'Ana Mercedes Tavárez',
  'Luis Alberto Almonte',
  'Yokasta Durán',
  'Ramón Antonio Germán',
  'Carmen Rosa Batista',
  'Félix Manuel Reyes',
  'Rosanna Espinal',
  'Juan Carlos Vargas',
  'Yudelka Martínez',
  'Pedro Pablo Cruz',
  'Milagros Jiménez',
  'Wilson Rafael Taveras',
  'Dayana Collado',
  'Héctor Bienvenido Núñez',
  'Francisca Ureña',
  'Ángel Daniel Rosario',
  'Kenia Marte',
  'Rafael Leónidas Polanco',
  'Esperanza Gómez',
  'Domingo Antonio Liriano',
  'Paola Vásquez',
  'Manuel de Jesús Fermín',
  'Altagracia Santos',
  'Edwin Alexander Guzmán',
  'Yesenia Cabrera',
  'Julio César Estévez',
  'Belkis Hernández',
  'Franklin Ventura',
];

const _sectores = [
  'Los Jardines Metropolitanos',
  'Cienfuegos',
  'Pekín',
  'Gurabo',
  'Bella Vista',
  'Los Pepines',
  'Villa Olga',
  'Cerros de Gurabo',
  'La Joya',
  'Baracoa',
  'Hoya del Caimito',
  'Ensanche Bermúdez',
  'Reparto Peralta',
  'Pueblo Nuevo',
  'Los Salados',
  'Villa Verde',
  'El Ejido',
  'Nibaje',
];

const _trabajos = [
  ('Colmado La Esquina', 'Comerciante'),
  ('Zona Franca Santiago', 'Operaria'),
  ('Salón de belleza propio', 'Estilista'),
  ('Taller de motores', 'Mecánico'),
  ('Banca de lotería', 'Vendedora'),
  ('Motoconcho', 'Motoconchista'),
  ('Frutería del mercado', 'Vendedor'),
  ('Ferretería Ochoa', 'Despachador'),
  ('Cafetería escolar', 'Cocinera'),
  ('Construcción', 'Maestro de obra'),
];

const _apellidosRef = [
  'Pérez',
  'García',
  'Fernández',
  'Santana',
  'Acosta',
  'Paulino',
  'Ortiz'
];

final sql = StringBuffer();
void _linea(String s) => sql.writeln(s);

void _insert(String tabla, Map<String, Object?> fila,
    {Set<String> crudos = const {}}) {
  final cols = fila.keys.join(', ');
  final vals = fila.entries
      .map((e) => crudos.contains(e.key) ? e.value : _q(e.value))
      .join(', ');
  _linea('insert into $tabla ($cols) values ($vals);');
}

/// Cómo paga cada cliente.
enum Conducta {
  puntual,
  atrasado,
  parcial,
  adelantado,
  pagado,
  nuevo,
  saldoAntes
}

class Prestamo {
  final String id;
  final String clienteId;
  final String? cobradorId;
  final Map<String, dynamic> datos;
  final List<
      ({
        calc.PagoRegistrado pago,
        String id,
        double lat,
        double lng,
        bool anulado
      })> pagos = [];
  Prestamo(this.id, this.clienteId, this.cobradorId, this.datos);
}

void main(List<String> args) {
  if (args.length != 1) {
    stderr.writeln('Uso: dart run tool/negocio_demo.dart <id-del-prestamista>');
    exit(64);
  }
  final jefe = args.first;

  _linea(
      '-- Negocio de demostración generado por tool/negocio_demo.dart el ${calc.fechaSql(hoy)}.');
  _linea(
      '-- Ids de la demo: de300000-... (se borra con supabase/demo_borrar.sql).');
  _linea('begin;');
  _linea("set local request.jwt.claims to '{}';");
  _linea('');

  // --- Cobradores (con usuario para entrar a la app) ------------------------
  final cobradores = [
    (
      id: _id(),
      usuario: _id(),
      nombre: 'Rafael Cobrador (demo)',
      email: 'rafael.cobrador@example.com',
      tel: '809-555-0201'
    ),
    (
      id: _id(),
      usuario: _id(),
      nombre: 'Yudelka Cobradora (demo)',
      email: 'yudelka.cobradora@example.com',
      tel: '809-555-0202'
    ),
  ];
  _linea(
      '-- Cobradores: entran con su correo y la contraseña Demo-Cobrador-2026');
  for (final c in cobradores) {
    _linea(
        '''insert into auth.users (instance_id, id, aud, role, email, encrypted_password,
  email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
  confirmation_token, email_change, email_change_token_new, recovery_token)
values ('00000000-0000-0000-0000-000000000000', ${_q(c.usuario)}, 'authenticated', 'authenticated',
  ${_q(c.email)}, extensions.crypt('Demo-Cobrador-2026', extensions.gen_salt('bf')), now(),
  '{"provider":"email","providers":["email"]}', '{}', now(), now(), '', '', '', '');''');
    _linea(
        '''insert into auth.identities (id, user_id, provider_id, identity_data, provider, created_at, updated_at, last_sign_in_at)
values (${_q(c.usuario)}, ${_q(c.usuario)}, ${_q(c.usuario)},
  jsonb_build_object('sub', ${_q(c.usuario)}, 'email', ${_q(c.email)}, 'email_verified', true),
  'email', now(), now(), now());''');
    _insert('cobradores', {
      'id': c.id,
      'prestamista_id': jefe,
      'nombre': c.nombre,
      'email': c.email,
      'telefono': c.tel,
      'user_id': c.usuario,
      'activo': true,
    });
  }
  _linea('');

  // --- Clientes ---------------------------------------------------------------
  final clientes = <({
    String id,
    String nombre,
    double lat,
    double lng,
    String? cobrador
  })>[];
  for (var i = 0; i < _nombres.length; i++) {
    final id = _id();
    final lat = 19.4517 + (_azar.nextDouble() - 0.5) * 0.06;
    final lng = -70.6970 + (_azar.nextDouble() - 0.5) * 0.07;
    // Rafael lleva 10, Yudelka 8 y el prestamista cobra el resto.
    final cobrador =
        i < 10 ? cobradores[0].id : (i < 18 ? cobradores[1].id : null);
    final trabajo = _uno(_trabajos);
    final n = (i + 1).toString().padLeft(2, '0');
    _insert(
        'clientes',
        {
          'id': id,
          'prestamista_id': jefe,
          'nombre': _nombres[i],
          'cedula': '999-00000$n-${i % 10}',
          'telefono': '809-555-01$n',
          'direccion':
              'C/ ${1 + _azar.nextInt(40)} #${1 + _azar.nextInt(90)}, ${_uno(_sectores)}, Santiago',
          'lat': double.parse(lat.toStringAsFixed(6)),
          'lng': double.parse(lng.toStringAsFixed(6)),
          'trabajo_lugar': trabajo.$1,
          'trabajo_direccion': '${_uno(_sectores)}, Santiago',
          'ingreso_mensual': (12 + _azar.nextInt(30)) * 1000,
          'tipo_vivienda': _azar.nextBool() ? 'propia' : 'alquilada',
          'ref1_nombre': 'Rosa ${_uno(_apellidosRef)}',
          'ref1_parentesco': 'Hermana',
          'ref1_telefono': '829-555-03$n',
          'ref2_nombre': 'Carlos ${_uno(_apellidosRef)}',
          'ref2_parentesco': 'Vecino',
          'ref2_telefono': '849-555-04$n',
          'metodo_cobro': _azar.nextInt(4) == 0 ? 'transferencia' : 'efectivo',
          'cobrador_id': cobrador,
          'created_at': null,
        }..remove('created_at'));
    clientes.add(
        (id: id, nombre: _nombres[i], lat: lat, lng: lng, cobrador: cobrador));
  }
  // Un cliente eliminado (archivado), para ver "Restaurar".
  _linea(
      'update clientes set archivado_en = now() - interval \'20 days\' where id = ${_q(clientes[29].id)};');
  _linea('');

  // --- Préstamos y cobros -----------------------------------------------------
  // (cliente, monto, tasa mensual, frecuencia, días de plazo, tipo, conducta, días desde el desembolso)
  final planes =
      <(int, double, double, String, int, calc.TipoInteres, Conducta, int)>[
    (0, 5000, 20, 'diario', 40, calc.TipoInteres.fijo, Conducta.puntual, 18),
    (1, 8000, 20, 'diario', 45, calc.TipoInteres.fijo, Conducta.atrasado, 30),
    (2, 3000, 20, 'diario', 30, calc.TipoInteres.fijo, Conducta.puntual, 10),
    (3, 10000, 15, 'semanal', 84, calc.TipoInteres.saldo, Conducta.puntual, 35),
    (4, 15000, 15, 'semanal', 84, calc.TipoInteres.saldo, Conducta.parcial, 49),
    (5, 6000, 20, 'diario', 40, calc.TipoInteres.fijo, Conducta.adelantado, 12),
    (
      6,
      20000,
      10,
      'quincenal',
      180,
      calc.TipoInteres.saldo,
      Conducta.puntual,
      60
    ),
    (7, 4000, 20, 'diario', 30, calc.TipoInteres.fijo, Conducta.atrasado, 22),
    (8, 12000, 15, 'semanal', 70, calc.TipoInteres.saldo, Conducta.nuevo, 1),
    (9, 7000, 20, 'diario', 45, calc.TipoInteres.fijo, Conducta.puntual, 25),
    (
      10,
      25000,
      10,
      'mensual',
      180,
      calc.TipoInteres.reditos,
      Conducta.puntual,
      75
    ),
    (11, 9000, 20, 'diario', 45, calc.TipoInteres.fijo, Conducta.puntual, 15),
    (
      12,
      15000,
      15,
      'semanal',
      84,
      calc.TipoInteres.saldo,
      Conducta.atrasado,
      56
    ),
    (13, 5000, 20, 'diario', 30, calc.TipoInteres.fijo, Conducta.pagado, 45),
    (
      14,
      30000,
      10,
      'quincenal',
      180,
      calc.TipoInteres.saldo,
      Conducta.puntual,
      45
    ),
    (15, 10000, 15, 'semanal', 56, calc.TipoInteres.fijo, Conducta.parcial, 28),
    (16, 4000, 20, 'diario', 30, calc.TipoInteres.fijo, Conducta.puntual, 8),
    (
      17,
      50000,
      8,
      'mensual',
      360,
      calc.TipoInteres.reditos,
      Conducta.puntual,
      100
    ),
    (
      18,
      40000,
      8,
      'mensual',
      240,
      calc.TipoInteres.saldo,
      Conducta.puntual,
      95
    ),
    (
      19,
      8000,
      15,
      'semanal',
      56,
      calc.TipoInteres.saldo,
      Conducta.saldoAntes,
      30
    ),
    (20, 6000, 20, 'diario', 40, calc.TipoInteres.fijo, Conducta.atrasado, 26),
    (
      21,
      20000,
      10,
      'quincenal',
      150,
      calc.TipoInteres.saldo,
      Conducta.adelantado,
      40
    ),
    (22, 3000, 20, 'diario', 30, calc.TipoInteres.fijo, Conducta.pagado, 50),
    (
      23,
      15000,
      12,
      'mensual',
      150,
      calc.TipoInteres.reditos,
      Conducta.atrasado,
      70
    ),
    (
      24,
      10000,
      15,
      'semanal',
      84,
      calc.TipoInteres.saldo,
      Conducta.puntual,
      21
    ),
    (25, 7000, 15, 'semanal', 56, calc.TipoInteres.fijo, Conducta.pagado, 70),
    (26, 12000, 15, 'semanal', 70, calc.TipoInteres.saldo, Conducta.nuevo, 0),
    // Clientes que ya terminaron y volvieron a coger (salen en "Volver a prestar" los de arriba).
    (0, 3000, 20, 'diario', 30, calc.TipoInteres.fijo, Conducta.pagado, 70),
    (3, 6000, 15, 'semanal', 42, calc.TipoInteres.saldo, Conducta.pagado, 90),
    // 27 y 28 sin préstamo (para prestarles en la demo); 29 eliminado.
  ];

  final prestamos = <Prestamo>[];
  for (final (ci, monto, tasa, frec, dias, tipo, conducta, hace) in planes) {
    final cliente = clientes[ci];
    final plan = calc.calcularPlan(
        monto: monto,
        tasaInteresMensual: tasa,
        diasPlazo: dias,
        frecuencia: frec,
        tipo: tipo);
    final desembolso = _dia(-hace);
    final datos = <String, dynamic>{
      'monto': monto,
      'tasa_interes': calc.redondearTasa(tasa),
      'cuota': plan.cuota,
      'cantidad_cuotas': plan.cantidadCuotas,
      'monto_total': plan.montoTotal,
      'mora_diaria': frec == 'diario' ? 2 : 1,
      'dias_gracia': frec == 'diario' ? 1 : 2,
      'frecuencia': frec,
      'tipo_interes': tipo.valor,
      'fecha_desembolso': calc.fechaSql(desembolso),
      'estado': 'en_calle',
    };
    final p = Prestamo(_id(), cliente.id, cliente.cobrador, datos);
    _simular(p, conducta, cliente.lat, cliente.lng);
    prestamos.add(p);
  }

  // Los préstamos (con su próximo pago y estado al día de hoy).
  for (final p in prestamos) {
    final pagos = [
      for (final x in p.pagos)
        if (!x.anulado) x.pago
    ];
    final estado = calc.estadoPrestamo(p.datos, pagos, hoy);
    final fila = {
      'id': p.id,
      'prestamista_id': jefe,
      'cliente_id': p.clienteId,
      ...p.datos,
      'proximo_pago': estado.proximoPago == null
          ? null
          : calc.fechaSql(estado.proximoPago!),
      'estado': estado.saldado ? 'pagado' : 'en_calle',
      'created_at': _ts(DateTime.parse(p.datos['fecha_desembolso'] as String)
          .add(const Duration(hours: 9))),
    };
    _insert('prestamos', fila, crudos: {'created_at'});
  }
  _linea('');

  // Los cobros, en orden de fecha (así los números de recibo van seguidos).
  final todos = [
    for (final p in prestamos)
      for (final x in p.pagos) (p, x)
  ]..sort((a, b) => a.$2.pago.fecha.compareTo(b.$2.pago.fecha));
  for (final (p, x) in todos) {
    _insert('pagos', {
      'id': x.id,
      'prestamo_id': p.id,
      'prestamista_id': jefe,
      'monto': x.pago.monto,
      'monto_mora': x.pago.montoMora,
      'descuento': x.pago.descuento,
      'metodo': x.pago.metodo,
      'fecha_pago': _ts(x.pago.fecha),
      'created_at': _ts(x.pago.fecha),
      'lat': double.parse(x.lat.toStringAsFixed(6)),
      'lng': double.parse(x.lng.toStringAsFixed(6)),
    }, crudos: {
      'fecha_pago',
      'created_at'
    });
  }
  // La base de datos pone el cobrador según quién cobra; aquí se pone después.
  for (final c in cobradores) {
    final ids = [
      for (final (p, x) in todos)
        if (p.cobradorId == c.id && x.pago.descuento == 0) x.id
    ];
    if (ids.isEmpty) continue;
    _linea(
        'update pagos set cobrador_id = ${_q(c.id)} where id in (${ids.map(_q).join(', ')});');
  }
  // Un cobro mal digitado y anulado por el prestamista.
  final anulados = [
    for (final (_, x) in todos)
      if (x.anulado) x.id
  ];
  for (final id in anulados) {
    _linea(
        "update pagos set anulado = true, anulado_en = fecha_pago + interval '20 minutes', "
        "motivo_anulacion = 'Lo cobré dos veces por error' where id = ${_q(id)};");
  }
  // Un cobro sin señal que la base de datos marcó para revisar.
  final sinSenal = todos.lastWhere((t) =>
      t.$1.cobradorId == cobradores[0].id && t.$2.pago.fecha.isBefore(hoyDia));
  _linea("update pagos set sin_conexion = true, reloj_telefono = fecha_pago, "
      "revisar = 'se subió 14 horas después de cobrarlo' where id = ${_q(sinSenal.$2.id)};");
  _linea('');

  // --- Gestiones: promesas y visitas -----------------------------------------
  for (final p in prestamos) {
    final pagos = [
      for (final x in p.pagos)
        if (!x.anulado) x.pago
    ];
    final estado = calc.estadoPrestamo(p.datos, pagos, hoy);
    if (estado.saldado ||
        estado.proximoPago == null ||
        !estado.proximoPago!.isBefore(_dia(-1))) continue;
    _insert('gestiones', {
      'prestamista_id': jefe,
      'prestamo_id': p.id,
      'cliente_id': p.clienteId,
      'tipo': 'visita',
      'resultado': 'no_estaba',
      'acuerdo': null,
      'created_at': _ts(_hora(_dia(-2))),
    }, crudos: {
      'created_at'
    });
    _insert('gestiones', {
      'prestamista_id': jefe,
      'prestamo_id': p.id,
      'cliente_id': p.clienteId,
      'tipo': 'llamada',
      'resultado': 'promesa',
      'acuerdo': 'Dice que cobra el viernes y pone todo al día',
      'promesa_fecha': calc.fechaSql(_dia(_azar.nextInt(3))),
      'promesa_monto': calc.proximaCuotaPorCobrar(estado).roundToDouble(),
      'created_at': _ts(_hora(_dia(-1))),
    }, crudos: {
      'created_at'
    });
  }
  _linea('');

  // --- Entregas de los cobradores (últimos 6 días) ---------------------------
  for (final c in cobradores) {
    for (var d = -6; d <= -1; d++) {
      final dia = _dia(d);
      final efectivo = todos
          .where((t) =>
              t.$1.cobradorId == c.id &&
              !t.$2.anulado &&
              t.$2.pago.metodo == 'efectivo' &&
              DateTime(t.$2.pago.fecha.year, t.$2.pago.fecha.month,
                      t.$2.pago.fecha.day) ==
                  dia)
          .fold(0.0, (s, t) => s + t.$2.pago.monto);
      if (efectivo == 0) continue;
      // Un día Rafael entregó RD$200 de menos, para ver el cuadre.
      final entregado =
          (c == cobradores[0] && d == -2) ? max(0.0, efectivo - 200) : efectivo;
      _insert('entregas_cobrador', {
        'prestamista_id': jefe,
        'cobrador_id': c.id,
        'fecha': calc.fechaSql(dia),
        'cobrado': efectivo,
        'entregado': entregado,
        'nota':
            entregado < efectivo ? 'Dijo que trae lo que falta mañana' : null,
      });
    }
  }
  _linea('');

  // --- Cierres de caja (últimos 7 días) --------------------------------------
  for (var d = -7; d <= -1; d++) {
    final dia = _dia(d);
    final delDia = todos.where((t) =>
        !t.$2.anulado &&
        DateTime(t.$2.pago.fecha.year, t.$2.pago.fecha.month,
                t.$2.pago.fecha.day) ==
            dia);
    if (delDia.isEmpty) continue;
    final total = delDia.fold(0.0, (s, t) => s + t.$2.pago.monto);
    final mora = delDia.fold(0.0, (s, t) => s + t.$2.pago.montoMora);
    _linea(
        'insert into cierres_caja (id, prestamista_id, fecha, total, cuotas, mora, cantidad_cobros) '
        'values (${_q(_id())}, ${_q(jefe)}, ${_q(calc.fechaSql(dia))}, $total, ${total - mora}, $mora, ${delDia.length}) '
        'on conflict do nothing;');
  }
  _linea('');

  // --- Gastos del mes -----------------------------------------------------------
  const gastos = [
    (-1, 450.0, 'gasolina', 'Gasolina de la motor'),
    (-3, 300.0, 'comida', 'Almuerzo de la ruta'),
    (-5, 2500.0, 'cobrador', 'Adelanto a Yudelka'),
    (-8, 450.0, 'gasolina', 'Gasolina de la motor'),
    (-10, 800.0, 'telefono', 'Recarga para WhatsApp'),
    (-12, 350.0, 'transporte', 'Carro público a Gurabo'),
    (-15, 7500.0, 'cobrador', 'Quincena de Rafael'),
    (-15, 7500.0, 'cobrador', 'Quincena de Yudelka'),
    (-18, 450.0, 'gasolina', 'Gasolina de la motor'),
    (-22, 1200.0, 'otro', 'Rollos de papel para la impresora'),
  ];
  for (final (d, monto, cat, nota) in gastos) {
    _insert('gastos', {
      'id': _id(),
      'prestamista_id': jefe,
      'fecha': calc.fechaSql(_dia(d)),
      'monto': monto,
      'categoria': cat,
      'nota': nota,
    });
  }
  _linea('');

  // --- Solicitudes nuevas (por el link) ----------------------------------------
  const solicitudes = [
    (
      'Mariela Sosa (demo)',
      '999-0000101-1',
      '809-555-0301',
      15000,
      'semanal',
      'Colmado Mariela'
    ),
    (
      'Joel Antonio Brito (demo)',
      '999-0000102-2',
      '809-555-0302',
      8000,
      'diario',
      'Motoconcho'
    ),
    (
      'Nancy Peralta (demo)',
      '999-0000103-3',
      '809-555-0303',
      25000,
      'semanal',
      'Zona Franca Santiago'
    ),
  ];
  for (final (nombre, cedula, tel, monto, frec, trabajo) in solicitudes) {
    _insert('solicitudes', {
      'id': _id(),
      'prestamista_id': jefe,
      'nombre': nombre,
      'cedula': cedula,
      'telefono': tel,
      'direccion': '${_uno(_sectores)}, Santiago',
      'trabajo_lugar': trabajo,
      'ingreso_mensual': 25000,
      'tipo_vivienda': 'alquilada',
      'monto_solicitado': monto,
      'frecuencia_pago': frec,
      'metodo_cobro': 'efectivo',
      'ref1_nombre': 'Luisa ${_uno(_apellidosRef)}',
      'ref1_parentesco': 'Madre',
      'ref1_telefono': '829-555-0399',
      'acepto_privacidad_en': 'now()',
    }, crudos: {
      'acepto_privacidad_en'
    });
  }

  _linea('');
  _linea('commit;');
  stdout.write(sql);
  stderr.writeln(
      'Listo: ${clientes.length} clientes, ${prestamos.length} préstamos, ${todos.length} cobros.');
}

/// Llena los cobros de [p] según cómo paga el cliente, con el reparto de
/// mora de la app.
void _simular(Prestamo p, Conducta conducta, double lat, double lng) {
  final cronograma = calc.generarCronograma(prestamo: p.datos, totalPagado: 0);
  List<calc.PagoRegistrado> validos() => [
        for (final x in p.pagos)
          if (!x.anulado) x.pago
      ];

  void cobrar(DateTime cuando, double monto,
      {double descuento = 0, bool anulado = false}) {
    final estado = calc.estadoPrestamo(p.datos, validos(), cuando);
    final reparto = calc.repartirPago(estado, monto);
    final metodo = _azar.nextInt(5) == 0 ? 'transferencia' : 'efectivo';
    p.pagos.add((
      pago: calc.PagoRegistrado(
          fecha: cuando,
          monto: monto,
          montoMora: reparto.mora,
          descuento: descuento,
          metodo: metodo),
      id: _id(),
      lat: lat + (_azar.nextDouble() - 0.5) * 0.0006,
      lng: lng + (_azar.nextDouble() - 0.5) * 0.0006,
      anulado: anulado,
    ));
  }

  if (conducta == Conducta.nuevo) return;

  // Cuántas cuotas deja de pagar al final (atrasado) o cuáles paga a medias.
  final vencidas = [
    for (final c in cronograma)
      if (!(c['fecha'] as DateTime).isAfter(hoyDia)) c
  ];
  final dejaDePagar = conducta == Conducta.atrasado ? 2 + _azar.nextInt(3) : 0;
  for (var i = 0; i < vencidas.length; i++) {
    final fecha = vencidas[i]['fecha'] as DateTime;
    if (conducta == Conducta.atrasado && i >= vencidas.length - dejaDePagar)
      break;
    // Hoy: unos ya pagaron (la ruta muestra el avance) y otros no.
    if (fecha == hoyDia && _azar.nextBool()) continue;
    // A veces paga un día tarde (genera un poco de mora).
    var dia = fecha;
    if (conducta != Conducta.adelantado &&
        _azar.nextInt(6) == 0 &&
        fecha.isBefore(_dia(-1))) {
      dia = fecha.add(const Duration(days: 1));
    }
    final cuando = _hora(dia);
    final estado = calc.estadoPrestamo(p.datos, validos(), cuando);
    var monto = calc.proximaCuotaPorCobrar(estado).ceilToDouble();
    if (monto <= 0) continue;
    if (conducta == Conducta.parcial && i.isOdd)
      monto = (monto / 2).roundToDouble();
    if (conducta == Conducta.adelantado && i == vencidas.length - 1) monto *= 2;
    cobrar(cuando, monto);
    // Un cobro repetido por error, que después se anula.
    if (conducta == Conducta.parcial && i == 1)
      cobrar(cuando.add(const Duration(minutes: 3)), monto, anulado: true);
  }

  if (conducta == Conducta.pagado) {
    // Termina de pagar todo lo que le quedaba.
    final ultima = cronograma.last['fecha'] as DateTime;
    final cuando = _hora(ultima.isAfter(_dia(-1)) ? _dia(-2) : ultima);
    final estado = calc.estadoPrestamo(p.datos, validos(), cuando);
    if (!estado.saldado) cobrar(cuando, (estado.balance * 100).ceil() / 100);
  } else if (conducta == Conducta.saldoAntes) {
    // Lo saldó antes de tiempo: se le perdonó el interés que no corrió.
    final cuando = _hora(_dia(-3));
    final s = calc.calcularSaldarHoy(p.datos, validos(), cuando);
    if (s.monto >= 1)
      cobrar(cuando, s.monto, descuento: max(0, s.balance - s.monto));
  }
}
