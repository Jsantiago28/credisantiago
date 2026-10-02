// Gastos del negocio y ganancia real: interés cobrado + mora − gastos.

/// Categorías de gasto: (valor guardado, texto que se ve).
const categoriasGasto = [
  ('gasolina', 'Gasolina'),
  ('cobrador', 'Pago al cobrador'),
  ('telefono', 'Teléfono y recargas'),
  ('comida', 'Comida'),
  ('transporte', 'Transporte'),
  ('otro', 'Otro'),
];

String nombreCategoria(String categoria) =>
    categoriasGasto.firstWhere((c) => c.$1 == categoria, orElse: () => ('otro', 'Otro')).$2;

class Gasto {
  final String? id;

  /// El día del gasto (sin hora).
  final DateTime fecha;
  final double monto;
  final String categoria;
  final String? nota;

  const Gasto({
    this.id,
    required this.fecha,
    required this.monto,
    this.categoria = 'otro',
    this.nota,
  });

  factory Gasto.desdeFila(Map<String, dynamic> fila) => Gasto(
        id: fila['id'] as String?,
        fecha: DateTime.parse(fila['fecha'] as String),
        monto: (fila['monto'] as num).toDouble(),
        categoria: (fila['categoria'] as String?) ?? 'otro',
        nota: fila['nota'] as String?,
      );

  /// Nota si tiene, o el nombre de la categoría.
  String get descripcion {
    final n = nota?.trim() ?? '';
    return n.isEmpty ? nombreCategoria(categoria) : '${nombreCategoria(categoria)} · $n';
  }
}

bool _mismoDia(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

/// Los gastos de ese día.
List<Gasto> gastosDelDia(List<Gasto> gastos, DateTime dia) =>
    gastos.where((g) => _mismoDia(g.fecha, dia)).toList();

/// Los gastos del mes de [mes], el más reciente primero.
List<Gasto> gastosDelMes(List<Gasto> gastos, DateTime mes) =>
    gastos.where((g) => g.fecha.year == mes.year && g.fecha.month == mes.month).toList()
      ..sort((a, b) => b.fecha.compareTo(a.fecha));

double totalGastos(Iterable<Gasto> gastos) => gastos.fold(0.0, (s, g) => s + g.monto);

/// Cuánto se gastó en cada categoría, la de más gasto primero. Solo las
/// categorías con gastos.
List<({String categoria, double total})> gastosPorCategoria(Iterable<Gasto> gastos) {
  final totales = <String, double>{};
  for (final g in gastos) {
    totales[g.categoria] = (totales[g.categoria] ?? 0) + g.monto;
  }
  return [
    for (final e in totales.entries) (categoria: e.key, total: e.value),
  ]..sort((a, b) => b.total.compareTo(a.total));
}

/// Ganancia real de un período: lo que ganó (interés de lo cobrado a cuotas
/// y mora) menos lo que gastó. Puede salir negativa.
({double interes, double mora, double gastos, double real}) gananciaReal({
  required double interes,
  required double mora,
  required double gastos,
}) =>
    (interes: interes, mora: mora, gastos: gastos, real: interes + mora - gastos);
