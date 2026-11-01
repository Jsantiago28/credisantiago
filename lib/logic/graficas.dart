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

  /// Para ordenar dos cobros de la misma hora.
  final int? numeroRecibo;

  /// Lo que ya había pagado un cliente importado de Excel: cuenta para lo
  /// que debe, pero no es dinero que entró (ni cobro, ni ganancia).
  final bool importado;

  const CobroGrafica({
    required this.prestamoId,
    required this.fecha,
    required this.monto,
    this.montoMora = 0,
    this.anulado = false,
    this.descuento = 0,
    this.numeroRecibo,
    this.importado = false,
  });

  double get montoCuota => monto - montoMora;

  /// Dinero que entró (sin anulados ni importados).
  bool get entro => !anulado && !importado;

  factory CobroGrafica.desdeFila(Map<String, dynamic> fila) => CobroGrafica(
        prestamoId: fila['prestamo_id'] as String,
        fecha: DateTime.parse(fila['fecha_pago'] as String).toLocal(),
        monto: (fila['monto'] as num).toDouble(),
        montoMora: (fila['monto_mora'] as num?)?.toDouble() ?? 0,
        anulado: fila['anulado'] == true,
        descuento: (fila['descuento'] as num?)?.toDouble() ?? 0,
        numeroRecibo: (fila['numero_recibo'] as num?)?.toInt(),
        importado: fila['metodo'] == 'importado',
      );
}

DateTime _dia(DateTime f) => DateTime(f.year, f.month, f.day);
DateTime _mes(DateTime f) => DateTime(f.year, f.month);

/// Los últimos [meses] meses, el más viejo primero (termina en el de hoy).
List<DateTime> ultimosMeses(DateTime hoy, int meses) =>
    [for (var i = meses - 1; i >= 0; i--) DateTime(hoy.year, hoy.month - i)];

/// Lo cobrado cada uno de los últimos [dias] días (el más viejo primero),
/// separado en cuotas y mora. Los días sin cobros salen en cero. Sin anulados
/// ni importados.
List<({DateTime dia, double cuotas, double mora})> cobradoPorDia(
    List<CobroGrafica> cobros, DateTime hoy,
    {int dias = 30}) {
  final hoyDia = _dia(hoy);
  final lista = [
    for (var i = dias - 1; i >= 0; i--) DateTime(hoyDia.year, hoyDia.month, hoyDia.day - i)
  ];
  final cuotas = {for (final d in lista) d: 0.0};
  final mora = {for (final d in lista) d: 0.0};
  for (final c in cobros.where((c) => c.entro)) {
    final d = _dia(c.fecha);
    if (!cuotas.containsKey(d)) continue;
    cuotas[d] = cuotas[d]! + c.montoCuota;
    mora[d] = mora[d]! + c.montoMora;
  }
  return [for (final d in lista) (dia: d, cuotas: cuotas[d]!, mora: mora[d]!)];
}

/// La ganancia (interés) de cada cobro: lo que subió el interés cobrado del
/// préstamo (ver [interesCobrado]) con ese cobro. Los cobros de cada
/// préstamo se recorren en orden (fecha y número de recibo, sin anulados):
/// en un préstamo sobre saldo las primeras cuotas son casi todo interés y
/// las últimas casi todo capital, así que el orden importa.
///
/// Si saldó antes de tiempo, el descuento baja las cuotas pero es interés
/// que no se cobró: se le resta a ese cobro. Así la suma de todos los cobros
/// da justo el interés que de verdad se ganó.
///
/// [cobros] debe traer TODOS los cobros de cada préstamo (también los de
/// antes y los importados), aunque solo se vayan a mostrar los recientes.
Map<CobroGrafica, double> interesPorCobro(
  List<CobroGrafica> cobros,
  Map<String, Map<String, dynamic>> prestamos,
) {
  final resultado = Map<CobroGrafica, double>.identity();
  final porPrestamo = <String, List<CobroGrafica>>{};
  for (final c in cobros.where((c) => !c.anulado)) {
    porPrestamo.putIfAbsent(c.prestamoId, () => []).add(c);
  }
  for (final e in porPrestamo.entries) {
    final p = prestamos[e.key];
    final lista = e.value
      ..sort((a, b) {
        final porFecha = a.fecha.compareTo(b.fecha);
        return porFecha != 0 ? porFecha : (a.numeroRecibo ?? 0).compareTo(b.numeroRecibo ?? 0);
      });
    var acumulado = 0.0;
    var interesAntes = 0.0;
    for (final c in lista) {
      if (p == null) {
        resultado[c] = 0;
        continue;
      }
      acumulado += c.montoCuota + c.descuento;
      final interesDespues = interesCobrado(p, acumulado);
      final interes = interesDespues - interesAntes - c.descuento;
      interesAntes = interesDespues;
      resultado[c] = interes < 0 ? 0 : interes;
    }
  }
  return resultado;
}

/// Ganancia que entró cada mes (el más viejo primero): el interés de lo
/// cobrado a cuotas (ver [interesPorCobro]) y la mora cobrada. Sin anulados
/// ni importados.
List<({DateTime mes, double interes, double mora})> gananciaPorMes(
  List<CobroGrafica> cobros,
  Map<String, Map<String, dynamic>> prestamos,
  DateTime hoy, {
  int meses = 6,
}) {
  final lista = ultimosMeses(hoy, meses);
  final interes = {for (final m in lista) m: 0.0};
  final mora = {for (final m in lista) m: 0.0};
  final porCobro = interesPorCobro(cobros, prestamos);
  for (final c in cobros.where((c) => c.entro)) {
    final m = _mes(c.fecha);
    if (!interes.containsKey(m)) continue;
    interes[m] = interes[m]! + (porCobro[c] ?? 0);
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
  for (final c in cobros.where((c) => c.entro)) {
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
