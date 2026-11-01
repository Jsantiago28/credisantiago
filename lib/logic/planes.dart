/// Planes de suscripción: qué plan vale hoy, cuántos clientes permite y
/// cuánto le queda. Misma regla que la base de datos (limite_clientes).
library;

/// Días que el plan pagado sigue valiendo después de vencer, para que el
/// prestamista renueve sin perder nada. Misma regla en la base de datos
/// (limite_clientes y limite_cobradores).
const diasDeGracia = 7;

/// El plan que vale hoy: si venció hace más de [diasDeGracia] días, cuenta
/// como Gratis.
String planEfectivo(Map<String, dynamic> perfil, DateTime hoy) {
  final plan = (perfil['plan'] as String?) ?? 'gratis';
  final vence = DateTime.tryParse(perfil['plan_vence'] as String? ?? '');
  final hoyDia = DateTime(hoy.year, hoy.month, hoy.day);
  if (vence != null && vence.add(const Duration(days: diasDeGracia)).isBefore(hoyDia)) {
    return 'gratis';
  }
  return plan;
}

/// Cómo está el plan del prestamista.
class EstadoPlan {
  final String planId;
  final String nombre;

  /// Máximo de clientes (null = sin límite). 0 si la cuenta no está aprobada.
  final int? limite;
  final int usados;
  final DateTime? vence;

  /// El plan pagado ya venció (quedó en Gratis).
  final bool vencido;

  const EstadoPlan({
    required this.planId,
    required this.nombre,
    required this.limite,
    required this.usados,
    required this.vence,
    required this.vencido,
  });

  bool get puedeAgregar => limite == null || usados < limite!;

  /// Ya venció pero sigue en los días de gracia: cuántos le quedan (null si
  /// no está en gracia).
  int? diasDeGraciaQuedan(DateTime hoy) {
    final dias = diasParaVencer(hoy);
    if (vencido || dias == null || dias >= 0) return null;
    return diasDeGracia + dias + 1;
  }
  int? get quedan => limite == null ? null : (limite! - usados).clamp(0, limite!);

  /// Días que faltan para que venza (null si no vence).
  int? diasParaVencer(DateTime hoy) => vence == null
      ? null
      : DateTime(vence!.year, vence!.month, vence!.day)
          .difference(DateTime(hoy.year, hoy.month, hoy.day))
          .inDays;
}

EstadoPlan estadoPlan({
  required Map<String, dynamic> perfil,
  required List<Map<String, dynamic>> planes,
  required int clientes,
  required DateTime hoy,
}) {
  final pagado = (perfil['plan'] as String?) ?? 'gratis';
  final efectivo = planEfectivo(perfil, hoy);
  final datos = planes.firstWhere((p) => p['id'] == efectivo,
      orElse: () => {'id': efectivo, 'nombre': efectivo, 'max_clientes': 10});
  // Antes de la migración de planes no hay "aprobado": se toma como aprobado.
  final aprobado = perfil['aprobado'] != false;
  return EstadoPlan(
    planId: efectivo,
    nombre: datos['nombre'] as String? ?? efectivo,
    limite: aprobado ? (datos['max_clientes'] as num?)?.toInt() : 0,
    usados: clientes,
    vence: DateTime.tryParse(perfil['plan_vence'] as String? ?? ''),
    vencido: pagado != efectivo,
  );
}

/// Nueva fecha de vencimiento al pagar `meses`: se suma desde hoy o desde
/// el vencimiento actual si todavía no ha llegado (no se pierden días).
DateTime nuevaFechaVence(DateTime? venceActual, DateTime hoy, {int meses = 1}) {
  final hoySinHora = DateTime(hoy.year, hoy.month, hoy.day);
  final base = venceActual != null && venceActual.isAfter(hoySinHora) ? venceActual : hoySinHora;
  final mes = DateTime(base.year, base.month + meses, 1);
  final ultimoDia = DateTime(mes.year, mes.month + 1, 0).day;
  return DateTime(mes.year, mes.month, base.day <= ultimoDia ? base.day : ultimoDia);
}


// ---------------------------------------------------------------------------
// PAGAR 1, 3 O 12 MESES
// ---------------------------------------------------------------------------

/// Por cuántos meses se puede pagar un plan.
const periodosPlan = [1, 3, 12];

/// "1 mes", "3 meses", "12 meses".
String nombrePeriodoPlan(int meses) => meses == 1 ? '1 mes' : '$meses meses';

/// Descuentos por pagar varios meses (editables en Administrar).
class DescuentosPlan {
  /// % menos al pagar 3 meses.
  final int descuento3;

  /// Meses de regalo al pagar 12 (2 = paga 10 y se lleva 12).
  final int mesesGratis12;

  const DescuentosPlan({this.descuento3 = 10, this.mesesGratis12 = 2});

  factory DescuentosPlan.desde(Map<String, dynamic>? ajustes) => DescuentosPlan(
        descuento3: (ajustes?['descuento_3_meses'] as num?)?.toInt() ?? 10,
        mesesGratis12: (ajustes?['meses_gratis_12'] as num?)?.toInt() ?? 2,
      );

  /// "10% menos", "2 meses gratis" (null si no hay descuento).
  String? etiqueta(int meses) => switch (meses) {
        3 when descuento3 > 0 => '$descuento3% menos',
        12 when mesesGratis12 > 0 => '$mesesGratis12 ${mesesGratis12 == 1 ? 'mes' : 'meses'} gratis',
        _ => null,
      };
}

/// Lo que cuesta pagar el plan por [meses]. Con descuento se redondea a
/// los RD$10 (RD$690 × 3 − 10% = RD$1,863 → RD$1,860).
double precioPeriodo(num mensual, int meses, [DescuentosPlan d = const DescuentosPlan()]) {
  final double total = switch (meses) {
    3 => mensual * 3 * (100 - d.descuento3) / 100,
    12 => mensual * (12 - d.mesesGratis12).clamp(0, 12),
    _ => mensual * meses,
  }.toDouble();
  final conDescuento = (meses == 3 && d.descuento3 > 0) || (meses == 12 && d.mesesGratis12 > 0);
  return conDescuento ? (total / 10).round() * 10.0 : total;
}

String _pesos(num v) {
  final s = v.round().toString();
  final conComas = s.replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');
  return 'RD\$$conComas';
}

/// Lo que el prestamista le escribe al administrador para pedir un plan.
/// La cuenta para depositar se la manda el administrador por WhatsApp.
/// [yaPago]: las cuentas están publicadas en la app y el prestamista ya
/// pagó (manda el comprobante); si no, pregunta a qué cuenta depositar.
String mensajePedidoPlan({
  required String prestamista,
  required String plan,
  required int meses,
  required num precio,
  bool yaPago = false,
}) =>
    yaPago
        ? 'Hola, soy $prestamista. Elegí el plan $plan por ${nombrePeriodoPlan(meses)} '
            '(${_pesos(precio)}) y ya pagué. Te envío el comprobante para que me lo actives.'
        : 'Hola, soy $prestamista. Quiero el plan $plan por ${nombrePeriodoPlan(meses)} '
            '(${_pesos(precio)}). ¿A qué cuenta te deposito?';

/// Recordatorio que el administrador le manda al prestamista.
String mensajeRecordatorioPlan({
  required String prestamista,
  required String plan,
  required DateTime vence,
  required DateTime hoy,
}) {
  final nombre = prestamista.trim().split(RegExp(r'\s+')).first;
  final dias = DateTime(vence.year, vence.month, vence.day)
      .difference(DateTime(hoy.year, hoy.month, hoy.day))
      .inDays;
  final cuando = dias > 1
      ? 'vence en $dias días'
      : dias == 1
          ? 'vence mañana'
          : dias == 0
              ? 'vence hoy'
              : 'venció hace ${-dias} día${dias == -1 ? '' : 's'}';
  return 'Hola $nombre, tu plan $plan de CrediSantiago $cuando. '
      'Para renovarlo por 1, 3 o 12 meses escríbeme y te paso la cuenta. ¡Gracias!';
}

/// Prestamistas con plan pagado que vencen en los próximos [dias] días o
/// que vencieron hace poco (hasta [vencidosHasta] días), el más urgente
/// primero. Sin los admin.
List<Map<String, dynamic>> vencenPronto(
  List<Map<String, dynamic>> prestamistas,
  DateTime hoy, {
  int dias = 7,
  int vencidosHasta = 30,
}) {
  final hoyDia = DateTime(hoy.year, hoy.month, hoy.day);
  int faltan(Map<String, dynamic> p) =>
      DateTime.parse(p['plan_vence'] as String).difference(hoyDia).inDays;
  return prestamistas.where((p) {
    if (p['es_admin'] == true || p['plan'] == 'gratis') return false;
    if (DateTime.tryParse(p['plan_vence'] as String? ?? '') == null) return false;
    final f = faltan(p);
    return f <= dias && f >= -vencidosHasta;
  }).toList()
    ..sort((a, b) => faltan(a).compareTo(faltan(b)));
}
