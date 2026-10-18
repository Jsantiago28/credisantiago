import 'package:intl/intl.dart';

import 'gastos.dart';

/// Caja por día: cuánto dinero entró cada día (sin los cobros anulados).

/// Un cobro visto desde la caja (con el nombre del cliente).
class CobroCaja {
  final String? id;
  final int? numeroRecibo;
  final DateTime fecha;
  final double monto;
  final double montoMora;
  final bool anulado;
  final String cliente;

  /// El cobrador que lo cobró (null si lo cobró el prestamista).
  final String? cobradorId;

  /// Dónde se hizo el cobro (null si el teléfono no dio la ubicación).
  final ({double lat, double lng})? ubicacion;

  const CobroCaja({
    this.id,
    this.numeroRecibo,
    required this.fecha,
    required this.monto,
    this.montoMora = 0,
    this.anulado = false,
    required this.cliente,
    this.cobradorId,
    this.ubicacion,
  });

  double get montoCuota => monto - montoMora;

  /// Fila de `pagos` con el préstamo y el cliente embebidos
  /// (`prestamos(clientes(nombre))`).
  factory CobroCaja.desdeFila(Map<String, dynamic> fila) {
    final prestamo = fila['prestamos'] as Map<String, dynamic>?;
    final cliente = prestamo?['clientes'] as Map<String, dynamic>?;
    return CobroCaja(
      id: fila['id'] as String?,
      numeroRecibo: (fila['numero_recibo'] as num?)?.toInt(),
      fecha: DateTime.parse(fila['fecha_pago'] as String).toLocal(),
      monto: (fila['monto'] as num).toDouble(),
      montoMora: (fila['monto_mora'] as num?)?.toDouble() ?? 0,
      anulado: fila['anulado'] == true,
      cliente: (cliente?['nombre'] as String?) ?? 'Cliente',
      cobradorId: fila['cobrador_id'] as String?,
      ubicacion: switch ((fila['lat'], fila['lng'])) {
        (final num lat, final num lng) => (lat: lat.toDouble(), lng: lng.toDouble()),
        _ => null,
      },
    );
  }
}

/// Resumen de un día de caja.
class DiaCaja {
  /// El día (sin hora).
  final DateTime dia;

  /// Todos los cobros del día, del más temprano al más tarde (también los
  /// anulados, para que se vean tachados).
  final List<CobroCaja> cobros;

  const DiaCaja(this.dia, this.cobros);

  List<CobroCaja> get validos => cobros.where((c) => !c.anulado).toList();
  double get total => validos.fold(0.0, (s, c) => s + c.monto);
  double get mora => validos.fold(0.0, (s, c) => s + c.montoMora);
  double get cuotas => total - mora;
  int get cantidad => validos.length;
  int get anulados => cobros.length - validos.length;
}

DateTime _soloDia(DateTime f) => DateTime(f.year, f.month, f.day);

/// Agrupa los cobros por día, el día más reciente primero. Los días que
/// solo tienen cobros anulados también salen (con total 0).
List<DiaCaja> cajaPorDia(List<CobroCaja> cobros) {
  final porDia = <DateTime, List<CobroCaja>>{};
  for (final c in cobros) {
    porDia.putIfAbsent(_soloDia(c.fecha), () => []).add(c);
  }
  final dias = porDia.entries
      .map((e) => DiaCaja(e.key, e.value..sort((a, b) => a.fecha.compareTo(b.fecha))))
      .toList()
    ..sort((a, b) => b.dia.compareTo(a.dia));
  return dias;
}

/// "2026-09-23" (como se guarda la fecha del cierre).
String claveDia(DateTime dia) =>
    '${dia.year}-${dia.month.toString().padLeft(2, '0')}-${dia.day.toString().padLeft(2, '0')}';

String _rd(double v) =>
    'RD\$${NumberFormat(v == v.roundToDouble() ? '#,##0' : '#,##0.00', 'en_US').format(v)}';

const _meses = ['ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'sep', 'oct', 'nov', 'dic'];

String _hora(DateTime f) {
  final h = f.hour % 12 == 0 ? 12 : f.hour % 12;
  return '$h:${f.minute.toString().padLeft(2, '0')} ${f.hour < 12 ? 'am' : 'pm'}';
}

/// Texto del resumen del día para mandarlo por WhatsApp.
/// Si hubo [gastos] ese día, también los pone y cuánto queda.
String resumenCajaTexto(DiaCaja d,
    {required String negocio,
    String? nota,
    List<Gasto> gastos = const [],
    Map<String, String> nombresCobradores = const {}}) {
  final gastado = totalGastos(gastos);
  final porCobrador = cajaPorCobrador(d);
  final conCobradores = porCobrador.any((c) => c.cobradorId != null);
  final lineas = <String>[
    'Caja del ${d.dia.day} ${_meses[d.dia.month - 1]} ${d.dia.year} — $negocio',
    'Total recibido: ${_rd(d.total)} (${d.cantidad} cobro${d.cantidad == 1 ? '' : 's'})',
    '  A cuotas: ${_rd(d.cuotas)}',
    if (d.mora > 0) '  A mora: ${_rd(d.mora)}',
    '',
    for (final c in d.validos) '• ${_hora(c.fecha)} ${c.cliente}: ${_rd(c.monto)}',
    if (d.anulados > 0) '(${d.anulados} cobro(s) anulado(s), no cuentan)',
    if (conCobradores) ...[
      '',
      'Por cobrador:',
      for (final c in porCobrador)
        '• ${c.cobradorId == null ? 'Yo' : (nombresCobradores[c.cobradorId] ?? 'Cobrador')}: '
            '${_rd(c.total)} (${c.cantidad})',
    ],
    if (gastos.isNotEmpty) ...[
      '',
      'Gastos: ${_rd(gastado)}',
      for (final g in gastos) '• ${g.descripcion}: ${_rd(g.monto)}',
      'Te queda: ${_rd(d.total - gastado)}',
    ],
    if (nota != null && nota.trim().isNotEmpty) ...['', 'Nota: ${nota.trim()}'],
  ];
  return lineas.join('\n');
}

/// Lo que cobró cada quien en un día: cada cobrador y el prestamista
/// (cobradorId null). Sin anulados. El que más cobró primero; el
/// prestamista al final. Solo quien cobró algo.
List<({String? cobradorId, double total, double mora, int cantidad})> cajaPorCobrador(DiaCaja d) {
  final totales = <String?, ({double total, double mora, int cantidad})>{};
  for (final c in d.validos) {
    final t = totales[c.cobradorId] ?? (total: 0.0, mora: 0.0, cantidad: 0);
    totales[c.cobradorId] =
        (total: t.total + c.monto, mora: t.mora + c.montoMora, cantidad: t.cantidad + 1);
  }
  final lista = [
    for (final e in totales.entries)
      (cobradorId: e.key, total: e.value.total, mora: e.value.mora, cantidad: e.value.cantidad),
  ]..sort((a, b) {
      if ((a.cobradorId == null) != (b.cobradorId == null)) return a.cobradorId == null ? 1 : -1;
      return b.total.compareTo(a.total);
    });
  return lista;
}

/// Lo que un cobrador le entregó al prestamista un día.
class Entrega {
  final String? id;
  final String cobradorId;
  final DateTime fecha;

  /// Lo que había cobrado cuando se anotó la entrega.
  final double cobrado;
  final double entregado;
  final String? nota;

  const Entrega({
    this.id,
    required this.cobradorId,
    required this.fecha,
    required this.cobrado,
    required this.entregado,
    this.nota,
  });

  factory Entrega.desdeFila(Map<String, dynamic> fila) => Entrega(
        id: fila['id'] as String?,
        cobradorId: fila['cobrador_id'] as String,
        fecha: DateTime.parse(fila['fecha'] as String),
        cobrado: (fila['cobrado'] as num).toDouble(),
        entregado: (fila['entregado'] as num).toDouble(),
        nota: fila['nota'] as String?,
      );
}

/// Si la entrega cuadra con lo cobrado: diferencia = entregado − cobrado
/// (negativa: falta; positiva: sobra). Centavos no cuentan.
({double diferencia, String texto}) cuadre({required double cobrado, required double entregado}) {
  final d = entregado - cobrado;
  if (d.abs() < 0.5) return (diferencia: 0, texto: 'Cuadra');
  return d < 0
      ? (diferencia: d, texto: 'Falta ${_rd(-d)}')
      : (diferencia: d, texto: 'Sobra ${_rd(d)}');
}
