import 'calculo_prestamo.dart';

// Contrato de préstamo: todo lo que se escribe en él sale del préstamo, del
// cliente y del perfil del prestamista. Solo las firmas van a mano.

const _unidades = [
  '', 'un', 'dos', 'tres', 'cuatro', 'cinco', 'seis', 'siete', 'ocho', 'nueve',
  'diez', 'once', 'doce', 'trece', 'catorce', 'quince', 'dieciséis', 'diecisiete',
  'dieciocho', 'diecinueve', 'veinte', 'veintiún', 'veintidós', 'veintitrés',
  'veinticuatro', 'veinticinco', 'veintiséis', 'veintisiete', 'veintiocho', 'veintinueve',
];
const _decenas = [
  '', '', '', 'treinta', 'cuarenta', 'cincuenta', 'sesenta', 'setenta', 'ochenta', 'noventa',
];
const _centenas = [
  '', 'ciento', 'doscientos', 'trescientos', 'cuatrocientos', 'quinientos', 'seiscientos',
  'setecientos', 'ochocientos', 'novecientos',
];

String _hasta999(int n) {
  if (n == 100) return 'cien';
  final partes = <String>[];
  final centena = n ~/ 100;
  final resto = n % 100;
  if (centena > 0) partes.add(_centenas[centena]);
  if (resto > 0) {
    if (resto < 30) {
      partes.add(_unidades[resto]);
    } else {
      final u = resto % 10;
      partes.add(u == 0 ? _decenas[resto ~/ 10] : '${_decenas[resto ~/ 10]} y ${_unidades[u]}');
    }
  }
  return partes.join(' ');
}

/// Número en letras, como va delante de "pesos": 21 → "veintiún",
/// 1500 → "mil quinientos", 2000000 → "dos millones".
String numeroEnLetras(int n) {
  if (n == 0) return 'cero';
  final millones = n ~/ 1000000;
  final miles = (n ~/ 1000) % 1000;
  final resto = n % 1000;
  final partes = <String>[
    if (millones == 1) 'un millón' else if (millones > 1) '${_hasta999(millones)} millones',
    if (miles == 1) 'mil' else if (miles > 1) '${_hasta999(miles)} mil',
    if (resto > 0) _hasta999(resto),
  ];
  return partes.join(' ');
}

/// "DIEZ MIL QUINIENTOS PESOS DOMINICANOS CON 00/100".
String montoEnLetras(double monto) {
  final pesos = monto.floor();
  final centavos = ((monto - pesos) * 100).round();
  final letras = numeroEnLetras(pesos);
  // "un millón de pesos", pero "un millón doscientos pesos".
  final de = pesos >= 1000000 && pesos % 1000000 == 0 ? ' de' : '';
  final nombre = pesos == 1 ? 'peso dominicano' : 'pesos dominicanos';
  return '$letras$de $nombre con ${centavos.toString().padLeft(2, '0')}/100'.toUpperCase();
}

const _mesesLargos = [
  'enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio', 'julio', 'agosto',
  'septiembre', 'octubre', 'noviembre', 'diciembre',
];

/// "13 de octubre de 2026".
String fechaContrato(DateTime f) => '${f.day} de ${_mesesLargos[f.month - 1]} de ${f.year}';

/// Una cuota del calendario de pagos.
typedef CuotaContrato = ({int numero, DateTime fecha, double monto});

/// Lo que se escribe en el contrato. Lo que falta (null) sale como una
/// raya para llenarla a mano.
class DatosContrato {
  final DateTime fecha;
  final String? ciudad;

  final String prestamista;
  final String? prestamistaCedula;

  /// Nombre de la persona cuando el prestamista firma como negocio.
  final String? representante;
  final String? prestamistaDomicilio;

  final String cliente;
  final String? clienteCedula;
  final String? clienteDomicilio;

  final double monto;
  final double tasaMensual;

  /// Sobre saldo (cuota fija), fijo sobre el monto o solo réditos.
  final TipoInteres tipoInteres;
  final double montoTotal;
  final String frecuencia;
  final double moraDiaria;
  final int diasGracia;
  final List<CuotaContrato> cuotas;

  const DatosContrato({
    required this.fecha,
    this.ciudad,
    required this.prestamista,
    this.prestamistaCedula,
    this.representante,
    this.prestamistaDomicilio,
    required this.cliente,
    this.clienteCedula,
    this.clienteDomicilio,
    required this.monto,
    required this.tasaMensual,
    this.tipoInteres = TipoInteres.fijo,
    required this.montoTotal,
    required this.frecuencia,
    required this.moraDiaria,
    required this.diasGracia,
    required this.cuotas,
  });

  /// La cuota normal (la última puede ser un poco distinta por el redondeo).
  double? get cuota => cuotas.isEmpty ? null : cuotas.first.monto;
  double? get ultimaCuota => cuotas.isEmpty ? null : cuotas.last.monto;
  DateTime? get primerPago => cuotas.isEmpty ? null : cuotas.first.fecha;
  DateTime? get ultimoPago => cuotas.isEmpty ? null : cuotas.last.fecha;

  String get frecuenciaTexto => switch (frecuencia) {
        'diario' => 'Diaria',
        'semanal' => 'Semanal',
        'quincenal' => 'Quincenal',
        _ => 'Mensual',
      };

  String get tasaTexto => tasaMensual <= 0
      ? 'No aplica'
      : tipoInteres == TipoInteres.reditos
          ? '${_porcentaje(tasaMensual)}% mensual, solo réditos: cada cuota paga el '
              'interés sobre el monto prestado y la última cuota paga además todo el capital'
          : '${_porcentaje(tasaMensual)}% mensual, ${tipoInteres.nombre}';

  /// Cómo se cobra la mora, o null si el préstamo no tiene mora.
  String? get moraTexto {
    if (moraDiaria <= 0) return null;
    final gracia = diasGracia == 1 ? '1 día' : '$diasGracia días';
    return '${_porcentaje(moraDiaria)}% diario sobre lo que falte de la cuota vencida, '
        'después de $gracia de gracia';
  }
}

/// 20 → "20", 4.5 → "4.5".
String _porcentaje(double v) =>
    v == v.roundToDouble() ? v.toInt().toString() : v.toString();

String? _texto(Map<String, dynamic>? fila, String campo) {
  final v = (fila?[campo] as String?)?.trim();
  return v == null || v.isEmpty ? null : v;
}

/// Junta los datos del contrato de `prestamo`. [perfil] es el del
/// prestamista (el del jefe si lo abre un cobrador).
DatosContrato datosContrato({
  required Map<String, dynamic> prestamo,
  required Map<String, dynamic>? cliente,
  required Map<String, dynamic>? perfil,
  required DateTime hoy,
}) {
  final negocio = _texto(perfil, 'negocio');
  final nombre = _texto(perfil, 'nombre');
  final desembolso = DateTime.tryParse(prestamo['fecha_desembolso'] as String? ?? '');

  return DatosContrato(
    fecha: desembolso ?? hoy,
    ciudad: _texto(perfil, 'contrato_ciudad'),
    prestamista: negocio ?? nombre ?? 'Prestamista',
    prestamistaCedula: _texto(perfil, 'contrato_cedula'),
    representante:
        negocio != null && nombre != null && negocio.toLowerCase() != nombre.toLowerCase()
            ? nombre
            : null,
    prestamistaDomicilio: _texto(perfil, 'recibo_direccion'),
    cliente: _texto(cliente, 'nombre') ?? '',
    clienteCedula: _texto(cliente, 'cedula'),
    clienteDomicilio: _texto(cliente, 'direccion'),
    monto: (prestamo['monto'] as num?)?.toDouble() ?? 0,
    tasaMensual: (prestamo['tasa_interes'] as num?)?.toDouble() ?? 0,
    tipoInteres: tipoInteresDe(prestamo),
    montoTotal: montoTotalGuardado(prestamo),
    frecuencia: prestamo['frecuencia'] as String? ?? 'diario',
    moraDiaria: (prestamo['mora_diaria'] as num?)?.toDouble() ?? 0,
    diasGracia: (prestamo['dias_gracia'] as num?)?.toInt() ?? 1,
    cuotas: [
      for (final c in generarCronograma(prestamo: prestamo, totalPagado: 0))
        (
          numero: c['numero'] as int,
          fecha: c['fecha'] as DateTime,
          monto: (c['monto'] as num).toDouble(),
        ),
    ],
  );
}
