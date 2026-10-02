/// Cálculos de dinero de un préstamo, como funciones puras (sin Supabase ni
/// Flutter). Prestar, Cobrar y Reportes usan SOLO estas funciones, para que
/// los tres muestren siempre los mismos números y se puedan probar.

/// Tolerancia para comparar montos (sumas de doubles).
const _centavo = 0.005;

/// Resultado de calcular un préstamo nuevo antes de confirmarlo.
class PlanPrestamo {
  /// Días por los que se cobra interés. Se completan los períodos: ej. 30
  /// días semanal → 5 semanas → 35 días; 45 días mensual → 2 meses → 60.
  final int diasCobrados;
  final double interesTotal;

  /// Total a devolver, en pesos enteros.
  final double montoTotal;
  final int cantidadCuotas;

  /// Cuota normal, en pesos enteros.
  final double cuota;

  /// La última cuota absorbe la diferencia del redondeo (≥ cuota).
  final double ultimaCuota;

  const PlanPrestamo({
    required this.diasCobrados,
    required this.interesTotal,
    required this.montoTotal,
    required this.cantidadCuotas,
    required this.cuota,
    required this.ultimaCuota,
  });
}

/// Frecuencias de cobro que se pueden elegir al prestar.
const frecuencias = ['diario', 'semanal', 'quincenal', 'mensual'];

/// Días que cubre cada cuota (para el interés). Mensual cuenta 30 días.
int diasPorCuota(String frecuencia) => switch (frecuencia) {
      'diario' => 1,
      'semanal' => 7,
      'quincenal' => 15,
      'mensual' => 30,
      _ => throw ArgumentError.value(frecuencia, 'frecuencia'),
    };

/// "cuotas diarias", "cuota semanal", etc.
String nombreCuotas(String frecuencia, {bool plural = true}) {
  final adjetivo = switch (frecuencia) {
    'diario' => 'diaria',
    'semanal' => 'semanal',
    'quincenal' => 'quincenal',
    _ => 'mensual',
  };
  if (!plural) return 'cuota $adjetivo';
  return 'cuotas ${adjetivo == 'diaria' ? 'diarias' : '${adjetivo}es'}';
}

/// "día", "semana", "quincena", "mes".
String nombrePeriodo(String frecuencia) => switch (frecuencia) {
      'diario' => 'día',
      'semanal' => 'semana',
      'quincenal' => 'quincena',
      _ => 'mes',
    };

/// "días", "semanas", "quincenas", "meses".
String nombrePeriodos(String frecuencia) => switch (frecuencia) {
      'diario' => 'días',
      'semanal' => 'semanas',
      'quincenal' => 'quincenas',
      _ => 'meses',
    };

/// Fecha en que vence la cuota #numero. Mensual: el mismo día de cada mes
/// (si ese mes es más corto, el último día del mes).
DateTime fechaCuota(DateTime desembolso, String frecuencia, int numero) {
  if (frecuencia != 'mensual') {
    return desembolso.add(Duration(days: numero * diasPorCuota(frecuencia)));
  }
  final mes = DateTime(desembolso.year, desembolso.month + numero, 1);
  final ultimoDia = DateTime(mes.year, mes.month + 1, 0).day;
  return DateTime(mes.year, mes.month,
      desembolso.day <= ultimoDia ? desembolso.day : ultimoDia);
}

/// REGLA DE INTERÉS: la tasa que pone el prestamista es MENSUAL. Se escala
/// según los días que dura el préstamo (30 días = 1 mes completo).
/// Ejemplo: 20% con 30 días diario = 20% de interés total.
///          20% con 60 días diario = 40% de interés total.
///
/// Cuotas: una por período (diario 1 día, semanal 7, quincenal 15, mensual
/// 30), redondeando hacia arriba (30 días semanal → 5 semanas), y el interés
/// se cobra por esos períodos completos (35 días), porque el préstamo dura
/// eso. Mensual: cada cuota es un mes de interés.
///
/// Redondeo: el total se redondea a pesos enteros, las cuotas son pesos
/// enteros y la última cuota absorbe la diferencia (ej: 6,500 en 45 cuotas
/// → 44 de 144 y una última de 164).
PlanPrestamo calcularPlan({
  required double monto,
  required double tasaInteresMensual,
  required int diasPlazo,
  required String frecuencia, // diario / semanal / quincenal / mensual
}) {
  if (monto <= 0) throw ArgumentError.value(monto, 'monto', 'debe ser mayor que 0');
  if (diasPlazo < 1) {
    throw ArgumentError.value(diasPlazo, 'diasPlazo', 'debe ser al menos 1 día');
  }
  if (tasaInteresMensual < 0) {
    throw ArgumentError.value(tasaInteresMensual, 'tasaInteresMensual', 'no puede ser negativa');
  }

  final periodo = diasPorCuota(frecuencia);
  final cantidadCuotas = (diasPlazo / periodo).ceil();
  final diasCobrados = cantidadCuotas * periodo;

  final montoTotal =
      (monto + monto * (tasaInteresMensual / 100) * (diasCobrados / 30)).roundToDouble();
  final cuota = (montoTotal / cantidadCuotas).floorToDouble();
  if (cuota < 1) {
    throw ArgumentError.value(monto, 'monto', 'es muy poco para $cantidadCuotas cuotas');
  }
  return PlanPrestamo(
    diasCobrados: diasCobrados,
    interesTotal: montoTotal - monto,
    montoTotal: montoTotal,
    cantidadCuotas: cantidadCuotas,
    cuota: cuota,
    ultimaCuota: montoTotal - cuota * (cantidadCuotas - 1),
  );
}

/// El monto total a devolver de un préstamo YA GUARDADO. Usar SIEMPRE esta
/// función en vez de recalcular "monto + interés" a mano, para que el
/// balance sea el que se le mostró al prestamista al confirmar.
double montoTotalGuardado(Map<String, dynamic> prestamo) {
  final guardado = (prestamo['monto_total'] as num?)?.toDouble() ?? 0;
  if (guardado > 0) return guardado;

  // Préstamos creados antes de guardar monto_total: cuota × cantidad.
  final cuota = (prestamo['cuota'] as num?)?.toDouble() ?? 0;
  final cantidadCuotas = (prestamo['cantidad_cuotas'] as num?)?.toInt() ?? 0;
  if (cuota > 0 && cantidadCuotas > 0) {
    return cuota * cantidadCuotas;
  }
  // Préstamos más viejos aún, sin cantidad_cuotas: fórmula plana (monto +
  // interés simple), aunque no escale por plazo.
  final monto = (prestamo['monto'] as num?)?.toDouble() ?? 0;
  final tasa = (prestamo['tasa_interes'] as num?)?.toDouble() ?? 0;
  return monto + (monto * tasa / 100);
}

/// Si con lo pagado hasta ahora el préstamo ya quedó saldado.
bool estaSaldado(Map<String, dynamic> prestamo, double totalPagado) {
  final montoTotal = montoTotalGuardado(prestamo);
  return montoTotal > 0 && totalPagado >= montoTotal - _centavo;
}

/// Cronograma de cuotas a partir del préstamo guardado y lo ya cobrado. No
/// se guarda en la base de datos. Cada cuota trae:
///  - 'monto': lo que vale (la última absorbe el redondeo),
///  - 'interes': la parte de ganancia de esa cuota (proporcional),
///  - 'pendiente': lo que falta por cobrarle (0 si está pagada),
///  - 'pagada' y 'fecha'.
/// Los pagos van cubriendo las cuotas en orden: una cuota está pagada
/// cuando lo cobrado alcanza la suma de ella y todas las anteriores.
List<Map<String, dynamic>> generarCronograma({
  required Map<String, dynamic> prestamo,
  required double totalPagado,
}) {
  final cuota = (prestamo['cuota'] as num?)?.toDouble() ?? 0;
  final cantidadCuotas = (prestamo['cantidad_cuotas'] as num?)?.toInt() ?? 0;
  final frecuencia = prestamo['frecuencia'] as String? ?? 'diario';
  final fechaDesembolsoStr = prestamo['fecha_desembolso'] as String?;
  final fechaDesembolso =
      fechaDesembolsoStr != null ? DateTime.tryParse(fechaDesembolsoStr) : null;

  if (cuota <= 0 || cantidadCuotas <= 0 || fechaDesembolso == null) return [];

  final montoTotal = montoTotalGuardado(prestamo);
  final monto = (prestamo['monto'] as num?)?.toDouble() ?? 0;
  final proporcionInteres = montoTotal > 0 ? (montoTotal - monto) / montoTotal : 0.0;
  final ultimaCuota = montoTotal - cuota * (cantidadCuotas - 1);

  var acumulado = 0.0;
  return List.generate(cantidadCuotas, (i) {
    final numero = i + 1;
    final montoCuota = numero == cantidadCuotas ? ultimaCuota : cuota;
    acumulado += montoCuota;
    final pendiente = (acumulado - totalPagado).clamp(0.0, montoCuota);
    final fecha = fechaCuota(fechaDesembolso, frecuencia, numero);
    return {
      'numero': numero,
      'fecha': fecha,
      'monto': montoCuota,
      'interes': montoCuota * proporcionInteres,
      'pendiente': pendiente < _centavo ? 0.0 : pendiente,
      'pagada': pendiente < _centavo,
    };
  });
}

/// Fecha de la primera cuota que falta por cobrar según el cronograma, o
/// null si ya está todo pagado (o el préstamo no tiene cronograma).
DateTime? proximoPago(Map<String, dynamic> prestamo, double totalPagado) {
  for (final c in generarCronograma(prestamo: prestamo, totalPagado: totalPagado)) {
    if (!(c['pagada'] as bool)) return c['fecha'] as DateTime;
  }
  return null;
}

/// La parte de ganancia (interés) que ya se cobró de un préstamo. Cada
/// peso cobrado se reparte entre capital e interés en la misma proporción
/// que tiene cada cuota del cronograma (ej: en 12,000 con 2,000 de interés,
/// de cada 1,000 cobrados 167 son ganancia).
double interesCobrado(Map<String, dynamic> prestamo, double totalPagado) {
  final cronograma = generarCronograma(prestamo: prestamo, totalPagado: totalPagado);
  if (cronograma.isEmpty) {
    // Préstamos viejos sin cronograma: misma proporción sobre el total.
    final montoTotal = montoTotalGuardado(prestamo);
    if (montoTotal <= 0) return 0;
    final monto = (prestamo['monto'] as num?)?.toDouble() ?? 0;
    return totalPagado.clamp(0.0, montoTotal) * (montoTotal - monto) / montoTotal;
  }
  var interes = 0.0;
  for (final c in cronograma) {
    final monto = c['monto'] as double;
    final cobradoDeEsta = monto - (c['pendiente'] as double);
    interes += (c['interes'] as double) * (cobradoDeEsta / monto);
  }
  return interes;
}

/// Números de la tarjeta "Ganancia proyectada este mes" de Reportes.
/// Recibe las filas del reporte (préstamo guardado + 'total_pagado').
({double proyectada, double yaLlevas, double falta}) gananciaDelMes(
  List<Map<String, dynamic>> filas,
  DateTime hoy,
) {
  final deEsteMes = filas.where((p) {
    final fecha = DateTime.tryParse(p['fecha_desembolso'] as String? ?? '');
    return fecha != null && fecha.year == hoy.year && fecha.month == hoy.month;
  });
  var proyectada = 0.0;
  var yaLlevas = 0.0;
  for (final p in deEsteMes) {
    proyectada += montoTotalGuardado(p) - ((p['monto'] as num?)?.toDouble() ?? 0);
    yaLlevas += interesCobrado(p, (p['total_pagado'] as num).toDouble());
  }
  final falta = (proyectada - yaLlevas).clamp(0.0, double.infinity);
  return (proyectada: proyectada, yaLlevas: yaLlevas, falta: falta);
}

/// Si un préstamo en la calle está atrasado: su próxima cuota pendiente
/// (según el cronograma) vence hoy o antes.
bool estaAtrasado(Map<String, dynamic> prestamo, double totalPagado, DateTime hoy) {
  if (prestamo['estado'] != 'en_calle') return false;
  final proximo = proximoPago(prestamo, totalPagado);
  if (proximo == null) return false;
  return !proximo.isAfter(DateTime(hoy.year, hoy.month, hoy.day));
}

/// Días de atraso respecto a la próxima cuota pendiente (0 si no hay).
int diasAtraso(Map<String, dynamic> prestamo, double totalPagado, DateTime hoy) {
  final proximo = proximoPago(prestamo, totalPagado);
  if (proximo == null) return 0;
  final dias = DateTime(hoy.year, hoy.month, hoy.day).difference(proximo).inDays;
  return dias < 0 ? 0 : dias;
}

/// Fecha como la guarda Supabase en columnas `date` (AAAA-MM-DD).
String fechaSql(DateTime fecha) => fecha.toIso8601String().substring(0, 10);

// ---------------------------------------------------------------------------
// MORA (recargo por atraso)
// ---------------------------------------------------------------------------
//
// Reglas (fijadas en cada préstamo al prestar: mora_diaria y dias_gracia):
//  - Recargo diario = mora_diaria % de LO QUE FALTA de la cuota vencida,
//    redondeado a pesos. Sin tope.
//  - Días de gracia = días completos después del vencimiento sin recargo.
//    Ej: vence el 12/9 con 1 día de gracia → el 13/9 no genera mora, el
//    14/9 es el primer día con recargo.
//  - Un día se cobra con lo que faltaba al empezar ese día: si paga el
//    14/9, el 14/9 ya generó mora.
//  - Cada pago cubre en orden: lo que falta de la cuota #1, su mora, lo que
//    falta de la #2, su mora, etc. Si no alcanza para la cuota, es un abono
//    a la cuota y la mora queda pendiente.
//  - Cada pago guarda cuánto fue a cuota y cuánto a mora (pagos.monto_mora),
//    para el recibo.

/// Un pago ya guardado (fila de la tabla `pagos`).
class PagoRegistrado {
  final String? id;

  /// Consecutivo del recibo, propio de cada prestamista (lo pone la base de
  /// datos al guardar el pago).
  final int? numeroRecibo;
  final DateTime fecha;
  final double monto;
  final double montoMora;

  /// Cobro anulado (mal digitado): no cuenta para nada, pero no se borra
  /// para que quede rastro. Su número de recibo no se reusa.
  final bool anulado;
  final String? motivoAnulacion;
  final DateTime? anuladoEn;

  /// El cobrador que lo cobró (null si lo cobró el prestamista).
  final String? cobradorId;

  const PagoRegistrado({
    this.id,
    this.numeroRecibo,
    required this.fecha,
    required this.monto,
    this.montoMora = 0,
    this.anulado = false,
    this.motivoAnulacion,
    this.anuladoEn,
    this.cobradorId,
  });

  double get montoCuota => monto - montoMora;

  factory PagoRegistrado.desdeFila(Map<String, dynamic> fila) => PagoRegistrado(
        id: fila['id'] as String?,
        numeroRecibo: (fila['numero_recibo'] as num?)?.toInt(),
        fecha: DateTime.parse(fila['fecha_pago'] as String).toLocal(),
        monto: (fila['monto'] as num).toDouble(),
        montoMora: (fila['monto_mora'] as num?)?.toDouble() ?? 0,
        anulado: fila['anulado'] == true,
        motivoAnulacion: fila['motivo_anulacion'] as String?,
        anuladoEn: DateTime.tryParse(fila['anulado_en'] as String? ?? '')?.toLocal(),
        cobradorId: fila['cobrador_id'] as String?,
      );
}

/// Solo los cobros que valen (sin los anulados).
List<PagoRegistrado> pagosValidos(List<PagoRegistrado> pagos) =>
    pagos.where((p) => !p.anulado).toList();

/// Orden de los pagos: por fecha y, si coinciden, por número de recibo.
int _compararPagos(PagoRegistrado a, PagoRegistrado b) {
  final porFecha = a.fecha.compareTo(b.fecha);
  if (porFecha != 0) return porFecha;
  return (a.numeroRecibo ?? 0).compareTo(b.numeroRecibo ?? 0);
}

/// Una cuota del cronograma con lo cobrado y la mora a una fecha.
class EstadoCuota {
  final int numero;
  final DateTime fecha;
  final double monto;

  /// Parte de ganancia (interés) de esta cuota.
  final double interes;

  /// Lo que falta por cobrar de la cuota (sin mora).
  double pendiente;
  double moraGenerada = 0;
  double moraPagada = 0;

  EstadoCuota._(this.numero, this.fecha, this.monto, this.interes) : pendiente = monto;

  double get moraPendiente {
    final m = moraGenerada - moraPagada;
    return m < _centavo ? 0 : m;
  }

  /// La cuota en sí está cubierta (puede quedar mora pendiente).
  bool get pagada => pendiente < _centavo;

  /// Lo que hay que cobrar para dejar esta cuota al día (cuota + mora).
  double get porCobrar => (pagada ? 0 : pendiente) + moraPendiente;
}

/// Cómo está un préstamo a una fecha, con pagos y mora.
class EstadoPrestamo {
  final List<EstadoCuota> cuotas;
  final double montoTotal;

  /// Lo cobrado que fue a cuotas (capital + interés), incluye sobrepagos.
  final double cobradoCuotas;
  final double moraCobrada;

  const EstadoPrestamo._(this.cuotas, this.montoTotal, this.cobradoCuotas, this.moraCobrada);

  double get moraGenerada => cuotas.fold(0.0, (s, c) => s + c.moraGenerada);
  double get moraPendiente => cuotas.fold(0.0, (s, c) => s + c.moraPendiente);

  /// Lo que falta de las cuotas, sin mora.
  double get balanceCuotas => montoTotal - cobradoCuotas;

  /// Lo que debe en total: cuotas + mora.
  double get balance => balanceCuotas + moraPendiente;

  bool get saldado => montoTotal > 0 && balanceCuotas < _centavo && moraPendiente < _centavo;

  /// Fecha de la primera cuota que falta por cobrar (null si no hay).
  DateTime? get proximoPago {
    for (final c in cuotas) {
      if (!c.pagada) return c.fecha;
    }
    return null;
  }
}

int _dia(DateTime d) =>
    DateTime.utc(d.year, d.month, d.day).millisecondsSinceEpoch ~/ Duration.millisecondsPerDay;

/// Recorre los pagos en orden de fecha y calcula cuotas, mora y balance al
/// día `hoy` (incluido).
EstadoPrestamo estadoPrestamo(
  Map<String, dynamic> prestamo,
  List<PagoRegistrado> pagos,
  DateTime hoy,
) {
  final montoTotal = montoTotalGuardado(prestamo);
  final tasa = ((prestamo['mora_diaria'] as num?)?.toDouble() ?? 0) / 100;
  final gracia = (prestamo['dias_gracia'] as num?)?.toInt() ?? 1;

  final cuotas = [
    for (final c in generarCronograma(prestamo: prestamo, totalPagado: 0))
      EstadoCuota._(c['numero'] as int, c['fecha'] as DateTime, c['monto'] as double,
          c['interes'] as double),
  ];
  // Último día ya considerado para la mora de cada cuota (hasta ahí, gracia).
  final hasta = [for (final c in cuotas) _dia(c.fecha) + gracia];

  void generarMoraHasta(int dia) {
    if (tasa <= 0) return;
    for (var i = 0; i < cuotas.length; i++) {
      final c = cuotas[i];
      if (dia <= hasta[i]) continue;
      if (!c.pagada) c.moraGenerada += (dia - hasta[i]) * (tasa * c.pendiente).roundToDouble();
      hasta[i] = dia;
    }
  }

  final ordenados = pagosValidos(pagos)..sort(_compararPagos);
  var cobradoCuotas = 0.0;
  var moraCobrada = 0.0;

  void abonarCuotas(double monto) {
    var resto = monto;
    for (final c in cuotas) {
      if (resto < _centavo) break;
      final parte = resto < c.pendiente ? resto : c.pendiente;
      c.pendiente -= parte;
      resto -= parte;
    }
  }

  for (final pago in ordenados) {
    generarMoraHasta(_dia(pago.fecha));
    cobradoCuotas += pago.montoCuota;
    moraCobrada += pago.montoMora;
    abonarCuotas(pago.montoCuota);

    var resto = pago.montoMora;
    for (final c in cuotas) {
      if (resto < _centavo) break;
      final debe = c.moraPendiente;
      final parte = resto < debe ? resto : debe;
      c.moraPagada += parte;
      resto -= parte;
    }
    // Mora pagada de más (pasa si se anula un cobro anterior y la mora ya
    // no era tanta): no se pierde, cuenta como abono a las cuotas.
    if (resto >= _centavo) {
      moraCobrada -= resto;
      cobradoCuotas += resto;
      abonarCuotas(resto);
    }
  }
  generarMoraHasta(_dia(hoy));

  return EstadoPrestamo._(cuotas, montoTotal, cobradoCuotas, moraCobrada);
}

/// Reparte un cobro nuevo entre cuota y mora según el orden de las reglas.
/// `estado` debe estar calculado al día del cobro.
({double cuota, double mora}) repartirPago(EstadoPrestamo estado, double monto) {
  var resto = monto;
  var mora = 0.0;
  for (final c in estado.cuotas) {
    if (resto < _centavo) break;
    resto -= resto < c.pendiente ? resto : c.pendiente;
    if (resto < _centavo) break;
    final debeMora = c.moraPendiente;
    final aMora = resto < debeMora ? resto : debeMora;
    mora += aMora;
    resto -= aMora;
  }
  // Todo lo que no fue a mora cuenta como cuota (incluye si pagó de más).
  mora = double.parse(mora.toStringAsFixed(2));
  return (cuota: monto - mora, mora: mora);
}

/// Mora cobrada en el mes de `hoy` (por fecha del cobro).
double moraCobradaEnMes(List<PagoRegistrado> pagos, DateTime hoy) => pagos
    .where((p) => !p.anulado && p.fecha.year == hoy.year && p.fecha.month == hoy.month)
    .fold(0.0, (s, p) => s + p.montoMora);

// ---------------------------------------------------------------------------
// RECIBOS
// ---------------------------------------------------------------------------

/// Lo que dice el recibo de un pago: cómo quedó el préstamo justo después
/// de ese cobro (aunque el recibo se genere días más tarde).
class DatosRecibo {
  final int? numero;
  final DateTime fecha;
  final double monto;
  final double aCuota;
  final double aMora;

  /// Ej: ["Cuota #5 (12/9/2026)", "Abono a la cuota #6: RD$ 60"].
  final List<String> cubre;
  final double balanceDespues;
  final double moraPendienteDespues;

  /// Primera cuota con algo por cobrar después del pago (null si saldó).
  final DateTime? proximoPagoFecha;
  final double proximoPagoMonto;
  final bool saldado;

  const DatosRecibo({
    required this.numero,
    required this.fecha,
    required this.monto,
    required this.aCuota,
    required this.aMora,
    required this.cubre,
    required this.balanceDespues,
    required this.moraPendienteDespues,
    required this.proximoPagoFecha,
    required this.proximoPagoMonto,
    required this.saldado,
  });
}

String _fechaCorta(DateTime f) => '${f.day}/${f.month}/${f.year}';

String _pesosTexto(double v) =>
    v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);

/// Arma el recibo del pago `pago` (debe estar dentro de `pagos`).
DatosRecibo datosRecibo(
  Map<String, dynamic> prestamo,
  List<PagoRegistrado> pagos,
  PagoRegistrado pago,
) {
  if (pago.anulado) throw ArgumentError('Este cobro está anulado: no tiene recibo válido');
  final ordenados = pagosValidos(pagos)..sort(_compararPagos);
  final i = ordenados.indexOf(pago);
  if (i < 0) throw ArgumentError('El pago no pertenece a la lista');

  final antes = estadoPrestamo(prestamo, ordenados.sublist(0, i), pago.fecha);
  final despues = estadoPrestamo(prestamo, ordenados.sublist(0, i + 1), pago.fecha);

  final cubre = <String>[];
  for (var k = 0; k < despues.cuotas.length; k++) {
    final b = antes.cuotas[k];
    final a = despues.cuotas[k];
    final abonado = b.pendiente - a.pendiente;
    if (abonado < _centavo) continue;
    if (a.pagada) {
      cubre.add('Cuota #${a.numero} (${_fechaCorta(a.fecha)})');
    } else {
      cubre.add('Abono a la cuota #${a.numero}: RD\$ ${_pesosTexto(abonado)}');
    }
  }

  EstadoCuota? proxima;
  for (final c in despues.cuotas) {
    if (c.porCobrar >= _centavo) {
      proxima = c;
      break;
    }
  }

  return DatosRecibo(
    numero: pago.numeroRecibo,
    fecha: pago.fecha,
    monto: pago.monto,
    aCuota: pago.montoCuota,
    aMora: pago.montoMora,
    cubre: cubre,
    balanceDespues: despues.balance,
    moraPendienteDespues: despues.moraPendiente,
    proximoPagoFecha: proxima?.fecha,
    proximoPagoMonto: proxima?.porCobrar ?? 0,
    saldado: despues.saldado,
  );
}

// ---------------------------------------------------------------------------
// COBROS DEL DÍA (tablero de Inicio)
// ---------------------------------------------------------------------------

/// Qué hay que cobrarle hoy a un préstamo:
///  - atrasado: cuotas que vencieron ANTES de hoy (lo que falta + su mora),
///  - venceHoy: la cuota que vence hoy,
///  - diasAtraso: desde la cuota vencida más vieja que sigue sin cubrir.
({double atrasado, double venceHoy, int diasAtraso}) cobroDelDia(
    EstadoPrestamo estado, DateTime hoy) {
  final hoyDia = _dia(hoy);
  var atrasado = 0.0;
  var venceHoy = 0.0;
  var diasAtraso = 0;
  for (final c in estado.cuotas) {
    final porCobrar = c.porCobrar;
    if (porCobrar < _centavo) continue;
    final dia = _dia(c.fecha);
    if (dia < hoyDia) {
      atrasado += porCobrar;
      if (diasAtraso == 0) diasAtraso = hoyDia - dia;
    } else if (dia == hoyDia) {
      venceHoy += porCobrar;
    }
  }
  return (atrasado: atrasado, venceHoy: venceHoy, diasAtraso: diasAtraso);
}
