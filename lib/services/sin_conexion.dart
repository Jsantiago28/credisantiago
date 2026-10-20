import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../logic/calculo_prestamo.dart';
import 'supabase_service.dart';

/// Cobrar sin internet (solo en la app de Android).
///
/// Con señal, cada vez que carga el Inicio se guarda en el teléfono la ruta
/// (los préstamos en la calle con lo justo para cobrar: nombre, dirección,
/// teléfono, ubicación, cuotas y cobros; nada de cédulas, fotos ni
/// ingresos). Todo va CIFRADO (Android Keystore) y vence a los [validez].
///
/// Sin señal, el cobro queda en una cola en el teléfono y se sube solo
/// cuando vuelve. La base de datos revisa cada uno (ver
/// migracion_2026_10_19_sin_conexion.sql): si algo no cuadra, el prestamista
/// lo ve marcado para revisar en la Caja.
///
/// Sin señal solo se puede ver la ruta y cobrar: prestar, anular, saldar o
/// anotar gestiones esperan a que haya internet.
class SinConexion {
  /// Cuánto sirve la ruta guardada. Pasado eso se borra y hay que conectarse.
  static const validez = Duration(days: 3);

  static bool get disponible => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static FlutterSecureStorage _almacen = const FlutterSecureStorage();

  @visibleForTesting
  static set almacenParaPruebas(FlutterSecureStorage almacen) => _almacen = almacen;

  /// Cobros guardados en el teléfono que todavía no suben.
  static final pendientes = ValueNotifier<int>(0);

  /// La última vez que se intentó, no había señal.
  static final sinSenal = ValueNotifier<bool>(false);

  /// Si la ruta que se ve es la guardada: desde cuándo (null = en vivo).
  static final rutaGuardadaDe = ValueNotifier<DateTime?>(null);

  static String? get _uid => SupabaseService.instance.usuarioActual?.id;
  static String _clave(String que) => 'sc_${que}_$_uid';

  /// El error es por falta de internet (y no otro problema).
  static bool esFaltaDeConexion(Object e) {
    final t = '$e';
    return e is TimeoutException ||
        t.contains('SocketException') ||
        t.contains('Failed host lookup') ||
        t.contains('ClientException') ||
        t.contains('Connection closed') ||
        t.contains('Connection refused') ||
        t.contains('Connection reset') ||
        t.contains('Network is unreachable') ||
        t.contains('AuthRetryableFetchException');
  }

  // ---------------------------------------------------------------------------
  // Guardar y leer (cifrado)
  // ---------------------------------------------------------------------------

  static Future<Object?> _leer(String que) async {
    if (!disponible || _uid == null) return null;
    try {
      final texto = await _almacen.read(key: _clave(que));
      return texto == null ? null : jsonDecode(texto);
    } catch (_) {
      return null;
    }
  }

  static Future<void> _escribir(String que, Object? valor) async {
    if (!disponible || _uid == null) return;
    try {
      if (valor == null) {
        await _almacen.delete(key: _clave(que));
      } else {
        await _almacen.write(key: _clave(que), value: jsonEncode(valor));
      }
    } catch (e) {
      // ignore: avoid_print
      print('ERROR REAL GUARDAR SIN CONEXION: $e');
    }
  }

  /// Quién entra (perfil del prestamista o fila del jefe del cobrador), para
  /// poder abrir la app sin señal.
  static Future<void> guardarIdentidad(String que, Map<String, dynamic> datos) =>
      _escribir('id_$que', datos);

  static Future<Map<String, dynamic>?> identidad(String que) async {
    final v = await _leer('id_$que');
    return v is Map ? Map<String, dynamic>.from(v) : null;
  }

  /// Guarda la ruta que se acaba de cargar con señal.
  static Future<void> guardarRuta(List<PrestamoConDatos> cartera) async {
    rutaGuardadaDe.value = null;
    sinSenal.value = false;
    await _escribir('ruta', {
      'guardada': DateTime.now().toUtc().toIso8601String(),
      'cartera': [for (final d in cartera) rutaAFila(d)],
    });
  }

  /// La ruta guardada, o null si no hay o ya venció (y entonces se borra).
  static Future<({DateTime guardada, List<PrestamoConDatos> cartera})?> ruta() async {
    final v = await _leer('ruta');
    if (v is! Map) return null;
    final guardada = DateTime.tryParse(v['guardada'] as String? ?? '')?.toLocal();
    if (guardada == null || DateTime.now().difference(guardada) > validez) {
      await _escribir('ruta', null);
      return null;
    }
    return (
      guardada: guardada,
      cartera: [for (final f in v['cartera'] as List) rutaDesdeFila(Map<String, dynamic>.from(f))],
    );
  }

  /// Al salir de la cuenta: se borra la ruta y quién entró. Los cobros sin
  /// subir NO se borran (son dinero recibido): suben cuando vuelva a entrar.
  static Future<void> olvidarDatos() async {
    await _escribir('ruta', null);
    await _escribir('id_perfil', null);
    await _escribir('id_jefe', null);
    rutaGuardadaDe.value = null;
  }

  // ---------------------------------------------------------------------------
  // Cola de cobros sin subir
  // ---------------------------------------------------------------------------

  static Future<List<CobroPendiente>> cola() async {
    final v = await _leer('cola');
    final lista = v is List
        ? [for (final f in v) CobroPendiente.desdeFila(Map<String, dynamic>.from(f))]
        : <CobroPendiente>[];
    pendientes.value = lista.length;
    return lista;
  }

  static Future<void> _guardarCola(List<CobroPendiente> lista) async {
    await _escribir('cola', [for (final c in lista) c.aFila()]);
    pendientes.value = lista.length;
  }

  static Future<void> agregar(CobroPendiente cobro) async {
    final lista = await cola();
    await _guardarCola([...lista, cobro]);
  }

  static Future<void>? _subiendo;

  /// Sube los cobros guardados, uno por uno y en orden. Se detiene si no hay
  /// señal. Uno que la base de datos ya tiene (mismo id) se da por subido.
  static Future<void> subir() {
    if (!disponible) return Future.value();
    return _subiendo ??= _subirTodo().whenComplete(() => _subiendo = null);
  }

  static Future<void> _subirTodo() async {
    final lista = await cola();
    final quedan = [...lista];
    for (final c in lista) {
      try {
        await SupabaseService.instance.registrarPago(
          prestamoId: c.prestamoId,
          prestamistaId: c.prestamistaId,
          monto: c.monto,
          ubicacion: c.ubicacion,
          id: c.id,
          fechaSinConexion: c.fecha,
        );
        quedan.remove(c);
      } on PostgrestException catch (e) {
        if (e.code == '23505') {
          quedan.remove(c); // ya estaba subido
        } else {
          // ignore: avoid_print
          print('ERROR REAL SUBIR COBRO: $e');
        }
      } catch (e) {
        if (esFaltaDeConexion(e)) {
          sinSenal.value = true;
          break;
        }
        // ignore: avoid_print
        print('ERROR REAL SUBIR COBRO: $e');
      }
      await _guardarCola(quedan);
    }
    pendientes.value = quedan.length;
  }

  /// Le suma a cada préstamo los cobros que todavía no suben, para que lo
  /// que debe se vea al día.
  static List<PrestamoConDatos> mezclar(
      List<PrestamoConDatos> cartera, List<CobroPendiente> cola) {
    if (cola.isEmpty) return cartera;
    return [
      for (final d in cartera)
        PrestamoConDatos(
          prestamo: d.prestamo,
          cliente: d.cliente,
          gestiones: d.gestiones,
          pagos: [
            ...d.pagos,
            for (final c in cola)
              if (c.prestamoId == d.prestamo['id'] && !d.pagos.any((p) => p.id == c.id))
                c.comoPago,
          ],
        ),
    ];
  }

  /// Un id nuevo (UUID v4) para un cobro hecho sin señal: con él la base de
  /// datos sabe si ya lo recibió (y no lo guarda dos veces).
  static String nuevoId() {
    final r = Random.secure();
    final b = List<int>.generate(16, (_) => r.nextInt(256));
    b[6] = (b[6] & 0x0f) | 0x40;
    b[8] = (b[8] & 0x3f) | 0x80;
    final h = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
    return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-'
        '${h.substring(16, 20)}-${h.substring(20)}';
  }
}

/// Un cobro hecho sin señal que todavía no sube.
class CobroPendiente {
  final String id;
  final String prestamoId;
  final String prestamistaId;
  final double monto;

  /// Cuánto fue a mora (calculado en el teléfono, para el recibo). Al subir,
  /// la base de datos lo vuelve a repartir con los cobros que tenga.
  final double montoMora;

  /// La hora del teléfono cuando se cobró.
  final DateTime fecha;
  final ({double lat, double lng})? ubicacion;

  const CobroPendiente({
    required this.id,
    required this.prestamoId,
    required this.prestamistaId,
    required this.monto,
    required this.montoMora,
    required this.fecha,
    this.ubicacion,
  });

  PagoRegistrado get comoPago =>
      PagoRegistrado(id: id, fecha: fecha, monto: monto, montoMora: montoMora, sinSubir: true);

  Map<String, dynamic> aFila() => {
        'id': id,
        'prestamo_id': prestamoId,
        'prestamista_id': prestamistaId,
        'monto': monto,
        'monto_mora': montoMora,
        'fecha': fecha.toUtc().toIso8601String(),
        if (ubicacion case final u?) ...{'lat': u.lat, 'lng': u.lng},
      };

  factory CobroPendiente.desdeFila(Map<String, dynamic> f) => CobroPendiente(
        id: f['id'] as String,
        prestamoId: f['prestamo_id'] as String,
        prestamistaId: f['prestamista_id'] as String,
        monto: (f['monto'] as num).toDouble(),
        montoMora: (f['monto_mora'] as num?)?.toDouble() ?? 0,
        fecha: DateTime.parse(f['fecha'] as String).toLocal(),
        ubicacion: switch ((f['lat'], f['lng'])) {
          (final num lat, final num lng) => (lat: lat.toDouble(), lng: lng.toDouble()),
          _ => null,
        },
      );
}

/// Los datos del cliente que se guardan en el teléfono: lo justo para
/// encontrarlo y cobrarle (sin cédula, fotos ni ingresos).
const _camposCliente = ['nombre', 'direccion', 'telefono', 'lat', 'lng'];

/// Del préstamo no se guardan los contratos firmados.
const _camposPrestamoFuera = ['contrato_firmado'];

@visibleForTesting
Map<String, dynamic> rutaAFila(PrestamoConDatos d) => {
      'prestamo': {
        for (final e in d.prestamo.entries)
          if (!_camposPrestamoFuera.contains(e.key)) e.key: e.value,
      },
      'cliente': {
        for (final c in _camposCliente) c: d.cliente?[c],
      },
      'pagos': [
        for (final p in d.pagos)
          {
            'id': p.id,
            'numero_recibo': p.numeroRecibo,
            'fecha_pago': p.fecha.toUtc().toIso8601String(),
            'monto': p.monto,
            'monto_mora': p.montoMora,
            'descuento': p.descuento,
            'anulado': p.anulado,
            'cobrador_id': p.cobradorId,
          },
      ],
    };

@visibleForTesting
PrestamoConDatos rutaDesdeFila(Map<String, dynamic> f) => PrestamoConDatos(
      prestamo: Map<String, dynamic>.from(f['prestamo'] as Map),
      cliente: Map<String, dynamic>.from(f['cliente'] as Map),
      pagos: [
        for (final p in f['pagos'] as List) PagoRegistrado.desdeFila(Map<String, dynamic>.from(p)),
      ],
    );
