import 'calculo_prestamo.dart';

/// Cómo se hizo la gestión de cobro.
const tiposGestion = {
  'visita': 'Visita',
  'llamada': 'Llamada',
  'whatsapp': 'WhatsApp',
  'otro': 'Otro',
};

/// Qué pasó en la gestión.
const resultadosGestion = {
  'pago': 'Pagó',
  'promesa': 'Prometió pagar',
  'no_estaba': 'No estaba',
  'se_nego': 'Se negó a pagar',
  'otro': 'Otro',
};

/// Una gestión de cobro: visita, llamada o WhatsApp al cliente, con lo que
/// pasó, el acuerdo por escrito y, si prometió pagar, cuándo y cuánto.
class Gestion {
  final String? id;
  final String prestamoId;
  final DateTime fecha;
  final String tipo;
  final String resultado;
  final String? acuerdo;

  /// Solo el día (sin hora).
  final DateTime? promesaFecha;
  final double? promesaMonto;

  const Gestion({
    this.id,
    required this.prestamoId,
    required this.fecha,
    required this.tipo,
    required this.resultado,
    this.acuerdo,
    this.promesaFecha,
    this.promesaMonto,
  });

  bool get esPromesa => resultado == 'promesa' && promesaFecha != null;

  String get nombreTipo => tiposGestion[tipo] ?? tipo;
  String get nombreResultado => resultadosGestion[resultado] ?? resultado;

  factory Gestion.desdeFila(Map<String, dynamic> fila) {
    final promesa = DateTime.tryParse(fila['promesa_fecha'] as String? ?? '');
    return Gestion(
      id: fila['id'] as String?,
      prestamoId: fila['prestamo_id'] as String,
      fecha: DateTime.parse(fila['created_at'] as String).toLocal(),
      tipo: fila['tipo'] as String,
      resultado: fila['resultado'] as String,
      acuerdo: fila['acuerdo'] as String?,
      promesaFecha: promesa == null ? null : DateTime(promesa.year, promesa.month, promesa.day),
      promesaMonto: (fila['promesa_monto'] as num?)?.toDouble(),
    );
  }
}

/// Cómo va una promesa de pago.
enum EstadoPromesa {
  /// Todavía no llega el día.
  pendiente,

  /// El día prometido es hoy y todavía no ha pagado lo prometido.
  venceHoy,

  /// Pagó lo prometido (o, si no se puso monto, pagó algo).
  cumplida,

  /// Pasó el día y no pagó lo prometido.
  incumplida,
}

/// Una promesa con lo que se ha pagado desde que se hizo.
class InfoPromesa {
  final Gestion gestion;
  final EstadoPromesa estado;
  final double pagado;

  /// Después del día prometido se anotó otra gestión: ya se le dio
  /// seguimiento, así que no se sigue avisando.
  final bool conSeguimiento;

  const InfoPromesa(this.gestion, this.estado, this.pagado, {this.conSeguimiento = false});

  /// Hay que avisar en Inicio: vence hoy, o no se cumplió (y nadie le ha
  /// dado seguimiento).
  bool get esAviso =>
      estado == EstadoPromesa.venceHoy ||
      (estado == EstadoPromesa.incumplida && !conSeguimiento);
}

DateTime _dia(DateTime f) => DateTime(f.year, f.month, f.day);

/// Cuánto ha pagado el cliente desde que hizo la promesa (sin anulados), y
/// si con eso la cumplió.
InfoPromesa estadoPromesa(Gestion promesa, List<PagoRegistrado> pagos, DateTime hoy) {
  final pagado = pagosValidos(pagos)
      .where((p) => p.fecha.isAfter(promesa.fecha))
      .fold<double>(0, (s, p) => s + p.monto);
  final monto = promesa.promesaMonto;
  final cumplida = monto == null || monto <= 0 ? pagado > 0 : pagado >= monto - 0.005;

  final EstadoPromesa estado;
  if (cumplida) {
    estado = EstadoPromesa.cumplida;
  } else {
    final dia = _dia(promesa.promesaFecha ?? promesa.fecha);
    final hoyDia = _dia(hoy);
    estado = hoyDia.isBefore(dia)
        ? EstadoPromesa.pendiente
        : hoyDia == dia
            ? EstadoPromesa.venceHoy
            : EstadoPromesa.incumplida;
  }
  return InfoPromesa(promesa, estado, pagado);
}

/// La última promesa de pago del préstamo y cómo va, o null si nunca
/// prometió. Una promesa no cumplida deja de avisarse cuando se anota otra
/// gestión después del día prometido (ya se le dio seguimiento).
InfoPromesa? ultimaPromesa(List<Gestion> gestiones, List<PagoRegistrado> pagos, DateTime hoy) {
  final promesas = gestiones.where((g) => g.esPromesa).toList()
    ..sort((a, b) => b.fecha.compareTo(a.fecha));
  if (promesas.isEmpty) return null;
  final info = estadoPromesa(promesas.first, pagos, hoy);
  if (info.estado != EstadoPromesa.incumplida) return info;
  final dia = info.gestion.promesaFecha!;
  final siguienteDia = DateTime(dia.year, dia.month, dia.day + 1);
  return InfoPromesa(info.gestion, info.estado, info.pagado,
      conSeguimiento: gestiones.any((g) => !g.fecha.isBefore(siguienteDia)));
}
