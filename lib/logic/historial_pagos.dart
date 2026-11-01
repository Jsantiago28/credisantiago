import 'calculo_prestamo.dart';

// Historial de pagos de un cliente: todos sus préstamos (los de ahora y los
// ya saldados) con cada cobro. Es lo que se le da al cliente cuando lo pide.

/// Un préstamo con sus cobros, en el orden en que se hicieron.
class PrestamoHistorial {
  final DateTime? desde;
  final double monto;
  final double montoTotal;

  /// 'en_calle', 'pagado' o 'cancelado'.
  final String estado;

  /// Todos los cobros, también los anulados (se muestran tachados).
  final List<PagoRegistrado> pagos;

  /// Lo que falta por pagar hoy (cuotas y mora). 0 si está saldado.
  final double balance;
  final double moraPendiente;

  const PrestamoHistorial({
    required this.desde,
    required this.monto,
    required this.montoTotal,
    required this.estado,
    required this.pagos,
    required this.balance,
    required this.moraPendiente,
  });

  List<PagoRegistrado> get validos => pagosValidos(pagos);
  double get pagado => validos.fold(0, (s, p) => s + p.monto);
  double get moraPagada => validos.fold(0, (s, p) => s + p.montoMora);
  bool get enLaCalle => estado == 'en_calle';

  String get estadoTexto => switch (estado) {
        'pagado' => 'Saldado',
        'cancelado' => 'Cancelado',
        _ => 'En la calle',
      };
}

/// Arma el historial de los préstamos de un cliente. El más reciente
/// primero; se dejan fuera los préstamos por confirmar (borrador) y los
/// cancelados sin ningún cobro (se hicieron por error).
List<PrestamoHistorial> historialPagos(
  List<({Map<String, dynamic> prestamo, List<PagoRegistrado> pagos})> prestamos,
  DateTime hoy,
) {
  final lista = <PrestamoHistorial>[];
  for (final (:prestamo, :pagos) in prestamos) {
    final estado = prestamo['estado'] as String? ?? '';
    if (estado == 'borrador') continue;
    if (estado == 'cancelado' && pagos.isEmpty) continue;
    final e = estadoPrestamo(prestamo, pagos, hoy);
    lista.add(PrestamoHistorial(
      desde: DateTime.tryParse(prestamo['fecha_desembolso'] as String? ?? ''),
      monto: (prestamo['monto'] as num?)?.toDouble() ?? 0,
      montoTotal: montoTotalGuardado(prestamo),
      estado: estado,
      // La marca de 0 de un préstamo importado no es un cobro: no se muestra.
      pagos: [for (final p in pagos) if (!p.esMarcaImportacion) p]
        ..sort((a, b) => a.fecha.compareTo(b.fecha)),
      balance: estado == 'en_calle' ? e.balance : 0,
      moraPendiente: estado == 'en_calle' ? e.moraPendiente : 0,
    ));
  }
  lista.sort((a, b) => (b.desde ?? DateTime(1900)).compareTo(a.desde ?? DateTime(1900)));
  return lista;
}
