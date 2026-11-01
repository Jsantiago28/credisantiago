import 'calculo_prestamo.dart';

/// La ruta del día: cuánto se lleva cobrado, quién paga mañana y cómo
/// viene la semana. Todo sale de la cartera que ya cargó Inicio (préstamos
/// en la calle con sus pagos), sin ir a la base de datos.

const _centavo = 0.005;

DateTime _dia(DateTime f) => DateTime(f.year, f.month, f.day);

bool _mismoDia(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// Dinero que entró ese día en estos pagos: sin anulados ni importados de
/// Excel (lo importado no es dinero de la caja). Cuenta los cobrados sin
/// señal que todavía no suben.
double cobradoEnDia(List<PagoRegistrado> pagos, DateTime dia) => pagos
    .where((p) => !p.anulado && !p.importado && _mismoDia(p.fecha, dia))
    .fold(0.0, (s, p) => s + p.monto);

/// Una parada de la ruta de hoy: lo que falta por cobrarle y lo que ya dio hoy.
typedef ParadaDelDia = ({double aCobrar, double cobradoHoy});

/// Ya pagó hoy y no le queda nada pendiente para hoy.
bool yaCobradoHoy(ParadaDelDia p) => p.cobradoHoy >= _centavo && p.aCobrar < _centavo;

/// Entra en la lista de hoy: le falta algo por cobrar o ya pagó hoy.
bool esDeHoy(ParadaDelDia p) => p.aCobrar >= _centavo || p.cobradoHoy >= _centavo;

/// Cómo va la ruta de hoy: "Cobrados 7 de 15 · RD$X de RD$Y".
class ProgresoRuta {
  /// Paradas que ya pagaron todo lo de hoy.
  final int cobrados;

  /// Todas las paradas de hoy (las que faltan y las que ya pagaron).
  final int total;

  /// Lo que entró hoy de esas paradas.
  final double montoCobrado;

  /// Lo cobrado más lo que falta por cobrar hoy.
  final double montoTotal;

  const ProgresoRuta({
    required this.cobrados,
    required this.total,
    required this.montoCobrado,
    required this.montoTotal,
  });

  /// De 0 a 1, por el dinero (0 si no hay nada que cobrar).
  double get fraccion =>
      montoTotal < _centavo ? 0 : (montoCobrado / montoTotal).clamp(0.0, 1.0);

  bool get completo => total > 0 && cobrados == total;
}

/// Suma la ruta de hoy. Una parada que pagó una parte y todavía debe algo
/// de hoy cuenta su dinero, pero no cuenta como cobrada.
ProgresoRuta progresoRuta(Iterable<ParadaDelDia> paradas) {
  var cobrados = 0, total = 0;
  var cobrado = 0.0, falta = 0.0;
  for (final p in paradas.where(esDeHoy)) {
    total++;
    if (yaCobradoHoy(p)) cobrados++;
    cobrado += p.cobradoHoy;
    falta += p.aCobrar;
  }
  return ProgresoRuta(
      cobrados: cobrados, total: total, montoCobrado: cobrado, montoTotal: cobrado + falta);
}

/// Lo que le toca pagar ese día según el cronograma y lo que ya se cobró:
/// lo que falta de las cuotas que vencen ese día (con su mora, si tiene).
double pendienteDelDia(EstadoPrestamo estado, DateTime dia) => estado.cuotas
    .where((c) => _mismoDia(c.fecha, dia))
    .fold(0.0, (s, c) => s + c.porCobrar);

/// Lo que el cronograma dice que vence ese día (el monto completo de las
/// cuotas, haya pagado o no).
double programadoDelDia(EstadoPrestamo estado, DateTime dia) => estado.cuotas
    .where((c) => _mismoDia(c.fecha, dia))
    .fold(0.0, (s, c) => s + c.monto);

/// Los que pagan mañana (con lo que les falta de la cuota de mañana), en
/// el mismo orden de la lista. Los que ya la pagaron por adelantado no salen.
List<({T item, double monto, DateTime fecha})> pagosDeManana<T>(
  Iterable<T> cartera,
  EstadoPrestamo Function(T) estado,
  DateTime hoy,
) {
  final manana = DateTime(hoy.year, hoy.month, hoy.day + 1);
  return [
    for (final x in cartera)
      if (pendienteDelDia(estado(x), manana) case final m when m >= _centavo)
        (item: x, monto: m, fecha: manana),
  ];
}

/// Lunes a domingo de la semana de [hoy].
List<DateTime> diasDeLaSemana(DateTime hoy) {
  final lunes = _dia(hoy).subtract(Duration(days: hoy.weekday - DateTime.monday));
  return [for (var i = 0; i < 7; i++) DateTime(lunes.year, lunes.month, lunes.day + i)];
}

/// Un día de la semana: lo que vence según el cronograma y lo que se cobró.
typedef DiaSemana = ({DateTime dia, double programado, double cobrado, int clientes});

/// Lunes a domingo de esta semana con lo que vence cada día (cronograma) y
/// lo que entró (pagos de ese día). [clientes] es cuántos préstamos tienen
/// cuota ese día.
List<DiaSemana> totalesDeLaSemana<T>(
  Iterable<T> cartera,
  EstadoPrestamo Function(T) estado,
  List<PagoRegistrado> Function(T) pagos,
  DateTime hoy,
) {
  final estados = [for (final x in cartera) (estado(x), pagos(x))];
  return [
    for (final d in diasDeLaSemana(hoy))
      (
        dia: d,
        programado: estados.fold(0.0, (s, e) => s + programadoDelDia(e.$1, d)),
        cobrado: estados.fold(0.0, (s, e) => s + cobradoEnDia(e.$2, d)),
        clientes: estados.where((e) => programadoDelDia(e.$1, d) >= _centavo).length,
      ),
  ];
}
