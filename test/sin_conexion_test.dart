import 'package:flutter_test/flutter_test.dart';
import 'package:prestamistas_rd/logic/caja.dart';
import 'package:prestamistas_rd/logic/calculo_prestamo.dart';
import 'package:prestamistas_rd/logic/ticket.dart';
import 'package:prestamistas_rd/recibos/recibo_pdf.dart' show NegocioRecibo;
import 'package:prestamistas_rd/services/sin_conexion.dart';
import 'package:prestamistas_rd/services/supabase_service.dart';

PrestamoConDatos prestamo() => PrestamoConDatos(
      prestamo: {
        'id': 'p1',
        'prestamista_id': 'jefe',
        'monto': 1000,
        'monto_total': 1200,
        'cuota': 300,
        'cantidad_cuotas': 4,
        'frecuencia': 'semanal',
        'fecha_desembolso': '2026-10-01',
        'contrato_firmado': ['jefe/contrato.jpg'],
      },
      cliente: {
        'nombre': 'Ana Pérez',
        'direccion': 'Calle 1',
        'telefono': '8095551234',
        'cedula': '001-0000000-1',
        'foto_cedula_frente_url': 'jefe/cedula.jpg',
        'ingreso_mensual': 50000,
      },
      pagos: [PagoRegistrado(id: 'x1', numeroRecibo: 7, fecha: DateTime(2026, 10, 8), monto: 300)],
    );

void main() {
  test('la ruta guardada lleva solo lo necesario para cobrar', () {
    final fila = rutaAFila(prestamo());
    final cliente = fila['cliente'] as Map;
    expect(cliente['nombre'], 'Ana Pérez');
    expect(cliente.containsKey('cedula'), isFalse);
    expect(cliente.containsKey('foto_cedula_frente_url'), isFalse);
    expect(cliente.containsKey('ingreso_mensual'), isFalse);
    expect((fila['prestamo'] as Map).containsKey('contrato_firmado'), isFalse);

    final vuelta = rutaDesdeFila(fila);
    expect(vuelta.nombre, 'Ana Pérez');
    expect(vuelta.pagos.single.numeroRecibo, 7);
    expect(vuelta.estado(DateTime(2026, 10, 9)).balanceCuotas, 900);
  });

  test('los cobros sin subir se suman a lo que debe (una sola vez)', () {
    final cobro = CobroPendiente(
        id: 'n1',
        prestamoId: 'p1',
        prestamistaId: 'jefe',
        monto: 300,
        montoMora: 0,
        fecha: DateTime(2026, 10, 15),
        ubicacion: (lat: 19.4, lng: -70.7));
    final vuelta = CobroPendiente.desdeFila(cobro.aFila());
    expect(vuelta.ubicacion, (lat: 19.4, lng: -70.7));
    expect(vuelta.fecha, cobro.fecha);

    var cartera = SinConexion.mezclar([prestamo()], [vuelta]);
    cartera = SinConexion.mezclar(cartera, [vuelta]); // no se duplica
    expect(cartera.single.pagos.length, 2);
    expect(cartera.single.pagos.last.sinSubir, isTrue);
    expect(cartera.single.estado(DateTime(2026, 10, 16)).balanceCuotas, 600);
  });

  test('cada cobro sin señal tiene su propio id (UUID)', () {
    final a = SinConexion.nuevoId();
    final b = SinConexion.nuevoId();
    expect(a, isNot(b));
    expect(RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')
        .hasMatch(a), isTrue);
  });

  test('distingue la falta de internet de otros errores', () {
    expect(SinConexion.esFaltaDeConexion(Exception('SocketException: Failed host lookup')), isTrue);
    expect(SinConexion.esFaltaDeConexion(Exception('ClientException with SocketException')), isTrue);
    expect(SinConexion.esFaltaDeConexion(Exception('permission denied for table pagos')), isFalse);
  });

  test('el recibo de un cobro sin señal dice que está pendiente de subir', () {
    final d = prestamo();
    final pendiente =
        PagoRegistrado(id: 'n1', fecha: DateTime(2026, 10, 15), monto: 300, sinSubir: true);
    final r = datosRecibo(d.prestamo, [...d.pagos, pendiente], pendiente);
    expect(r.pendiente, isTrue);
    expect(r.numero, isNull);
    final lineas = lineasTicket(
        r: r, negocio: const NegocioRecibo(nombre: 'Mi negocio'), cliente: 'Ana', papelMm: 58);
    expect(lineas.any((l) => l.texto.contains('PENDIENTE DE SUBIR')), isTrue);
  });

  test('la caja trae la marca de revisar que puso la base de datos', () {
    final c = CobroCaja.desdeFila({
      'fecha_pago': '2026-10-15T14:00:00Z',
      'monto': 300,
      'sin_conexion': true,
      'revisar': 'se subió 30 horas después de cobrarlo',
      'prestamos': {'clientes': {'nombre': 'Ana'}},
    });
    expect(c.sinConexion, isTrue);
    expect(c.revisar, contains('30 horas'));
  });
}
