import 'calculo_prestamo.dart';

/// Un cobro, con lo mínimo que necesitan las gráficas.
class CobroGrafica {
  final String prestamoId;
  final DateTime fecha;
  final double monto;
  final double montoMora;
  final bool anulado;

  /// Interés perdonado al saldar antes de tiempo (no es dinero).
  final double descuento;

  const CobroGrafica({
    required this.prestamoId,
    required this.fecha,
    required this.monto,
    this.montoMora = 0,
    this.anulado = false,
    this.descuento = 0,
  });

  double get montoCuota => monto - montoMora;

  factory CobroGrafica.desdeFila(Map<String, dynamic> fila) => CobroGrafica(
        prestamoId: fila['prestamo_id'] as String,
        fecha: DateTime.parse(fila['fecha_pago'] as String).toLocal(),
        monto: (fila['monto'] as num).toDouble(),
        montoMora: (fila['monto_mora'] as num?)?.toDouble() ?? 0,
        anulado: fila['anulado'] == true,
        descuento: (fila['descuento'] as num?)?.toDouble() ?? 0,
      );
}

DateTime _dia(DateTime f) => DateTime(f.year, f.month, f.day);
DateTime _mes(DateTime f) => DateTime(f.year, f.month);

/// Los últimos [meses] meses, el más viejo primero (termina en el de hoy).
List<DateTime> ultimosMeses(DateTime hoy, int meses) =>
    [for (var i = meses - 1; i >= 0; i--) DateTime(hoy.year, hoy.month - i)];

/// Lo cobrado cada uno de los últimos [dias] días (el más viejo primero),
/// separado en cuotas y mora. Los días sin cobros salen en cero. Sin anulados.
List<({DateTime dia, double cuotas, double mora})> cobradoPorDia(
    List<CobroGrafica> cobros, DateTime hoy,
    {int dias = 30}) {
  final hoyDia = _dia(hoy);
  final lista = [
    for (var i = dias - 1; i >= 0; i--) DateTime(hoyDia.year, hoyDia.month, hoyDia.day - i)
  ];
  final cuotas = {for (final d in lista) d: 0.0};
  final mora = {for (final d in lista) d: 0.0};
  for (final c in cobros.where((c) => !c.anulado)) {
    final d = _dia(c.fecha);
    if (!cuotas.containsKey(d)) continue;
    cuotas[d] = cuotas[d]! + c.montoCuota;
    mora[d] = mora[d]! + c.montoMora;
  }
  return [for (final d in lista) (dia: d, cuotas: cuotas[d]!, mora: mora[d]!)];
}

/// Qué parte de cada peso cobrado a cuotas es interés: (total - prestado) /
/// total. Es la misma proporción que usa "Ya llevas".
double parteInteres(Map<String, dynamic> prestamo) {
  final total = montoTotalGuardado(prestamo);
  if (total <= 0) return 0;
  final monto = (prestamo['monto'] as num?)?.toDouble() ?? 0;
  return ((total - monto) / total).clamp(0.0, 1.0);
}

/// La parte de interés de un cobro. Si saldó antes de tiempo, al cobro le
/// toca la proporción normal menos el interés que se perdonó (así la suma de
/// todos los cobros da justo el interés que de verdad se ganó).
double interesDelCobro(CobroGrafica c, double parte) {
  final interes = c.montoCuota * parte - c.descuento * (1 - parte);
  return interes < 0 ? 0 : interes;
}

/// Ganancia que entró cada mes (el más viejo primero): el interés de lo
/// cobrado a cuotas y la mora cobrada. Sin anulados.
List<({DateTime mes, double interes, double mora})> gananciaPorMes(
  List<CobroGrafica> cobros,
  Map<String, Map<String, dynamic>> prestamos,
  DateTime hoy, {
  int meses = 6,
}) {
  final lista = ultimosMeses(hoy, meses);
  final interes = {for (final m in lista) m: 0.0};
  final mora = {for (final m in lista) m: 0.0};
  for (final c in cobros.where((c) => !c.anulado)) {
    final m = _mes(c.fecha);
    if (!interes.containsKey(m)) continue;
    final p = prestamos[c.prestamoId];
    interes[m] = interes[m]! + (p == null ? 0 : interesDelCobro(c, parteInteres(p)));
    mora[m] = mora[m]! + c.montoMora;
  }
  return [for (final m in lista) (mes: m, interes: interes[m]!, mora: mora[m]!)];
}

/// Lo prestado (por fecha de desembolso) y lo cobrado (cuotas + mora) cada
/// mes, el más viejo primero. Los préstamos cancelados no cuentan.
List<({DateTime mes, double prestado, double cobrado})> prestadoVsCobrado(
  List<Map<String, dynamic>> prestamos,
  List<CobroGrafica> cobros,
  DateTime hoy, {
  int meses = 6,
}) {
  final lista = ultimosMeses(hoy, meses);
  final prestado = {for (final m in lista) m: 0.0};
  final cobrado = {for (final m in lista) m: 0.0};
  for (final p in prestamos) {
    if (p['estado'] == 'cancelado' || p['estado'] == 'borrador') continue;
    final f = DateTime.tryParse(p['fecha_desembolso'] as String? ?? '');
    if (f == null) continue;
    final m = _mes(f);
    if (!prestado.containsKey(m)) continue;
    prestado[m] = prestado[m]! + ((p['monto'] as num?)?.toDouble() ?? 0);
  }
  for (final c in cobros.where((c) => !c.anulado)) {
    final m = _mes(c.fecha);
    if (!cobrado.containsKey(m)) continue;
    cobrado[m] = cobrado[m]! + c.monto;
  }
  return [
    for (final m in lista) (mes: m, prestado: prestado[m]!, cobrado: cobrado[m]!)
  ];
}

/// Cómo está el dinero en la calle hoy: al día, lo que vence hoy y lo
/// atrasado (con su mora). Suma lo que debe cada préstamo en la calle.
({double alDia, double venceHoy, double atrasado}) carteraPorEstado(
    List<EstadoPrestamo> enLaCalle, DateTime hoy) {
  var alDia = 0.0, venceHoy = 0.0, atrasado = 0.0;
  for (final e in enLaCalle) {
    final d = cobroDelDia(e, hoy);
    atrasado += d.atrasado;
    venceHoy += d.venceHoy;
    alDia += (e.balance - d.atrasado - d.venceHoy).clamp(0.0, double.infinity);
  }
  return (alDia: alDia, venceHoy: venceHoy, atrasado: atrasado);
}
