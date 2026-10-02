// Importar clientes (y su préstamo, si tienen uno en la calle) desde un
// Excel o CSV: para el prestamista que ya lleva su cartera anotada.
//
// El archivo tiene una fila de títulos (los de la plantilla, o parecidos) y
// una fila por cliente. Cada fila se revisa con las mismas reglas de la app
// (cédula, teléfono, nombre) antes de guardar nada.

import 'dart:convert';
import 'dart:typed_data';

import 'package:excel/excel.dart';

import 'calculo_prestamo.dart';
import 'validacion.dart';

/// Columnas de la plantilla, en orden: (clave, título).
const columnasImportacion = [
  ('nombre', 'Nombre y apellido'),
  ('cedula', 'Cédula'),
  ('telefono', 'Teléfono'),
  ('direccion', 'Dirección'),
  ('monto', 'Monto prestado'),
  ('interes', 'Interés mensual %'),
  ('frecuencia', 'Frecuencia'),
  ('plazo', 'Plazo en días'),
  ('fecha', 'Fecha del préstamo'),
  ('pagado', 'Ya pagó'),
  ('mora', 'Mora diaria %'),
  ('gracia', 'Días de gracia'),
];

/// Otras formas de escribir cada título (sin acentos ni mayúsculas).
const _sinonimos = {
  'nombre': ['nombre', 'nombre completo', 'nombre y apellido', 'cliente'],
  'cedula': ['cedula', 'cedula de identidad', 'documento', 'id'],
  'telefono': ['telefono', 'celular', 'tel', 'whatsapp', 'telefono celular'],
  'direccion': ['direccion', 'direccion de la casa', 'casa'],
  'monto': ['monto prestado', 'monto', 'prestado', 'capital', 'prestamo'],
  'interes': ['interes mensual %', 'interes mensual', 'interes', 'tasa', 'interes %'],
  'frecuencia': ['frecuencia', 'frecuencia de pago', 'forma de pago', 'pago'],
  'plazo': ['plazo en dias', 'plazo', 'dias', 'plazo dias'],
  'fecha': ['fecha del prestamo', 'fecha', 'fecha de desembolso', 'desembolso', 'fecha prestamo'],
  'pagado': ['ya pago', 'pagado', 'abonado', 'ha pagado', 'ya pago rd'],
  'mora': ['mora diaria %', 'mora diaria', 'mora', 'mora %'],
  'gracia': ['dias de gracia', 'gracia'],
};

String _clave(String titulo) =>
    normalizarTexto(titulo).replaceAll(RegExp(r'[^a-z0-9% ]'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();

/// Qué columna del archivo es cada dato (índice), según los títulos.
Map<String, int> columnasDe(List<Object?> titulos) {
  final resultado = <String, int>{};
  for (var i = 0; i < titulos.length; i++) {
    final t = _clave('${titulos[i] ?? ''}');
    if (t.isEmpty) continue;
    for (final e in _sinonimos.entries) {
      if (!resultado.containsKey(e.key) && e.value.contains(t)) {
        resultado[e.key] = i;
        break;
      }
    }
  }
  return resultado;
}

/// Un préstamo que ya está en la calle, como lo trae el archivo.
class PrestamoImportado {
  final double monto;
  final double interesMensual;
  final String frecuencia;
  final int diasPlazo;
  final DateTime fecha;
  final double yaPago;
  final double moraDiaria;
  final int diasGracia;

  const PrestamoImportado({
    required this.monto,
    required this.interesMensual,
    required this.frecuencia,
    required this.diasPlazo,
    required this.fecha,
    this.yaPago = 0,
    this.moraDiaria = 5,
    this.diasGracia = 1,
  });

  /// Lo que se guarda en la tabla de préstamos (igual que al prestar en la
  /// app, pero con la fecha del archivo). Sin prestamista ni cliente.
  Map<String, dynamic> datos() {
    final plan = calcularPlan(
      monto: monto,
      tasaInteresMensual: interesMensual,
      diasPlazo: diasPlazo,
      frecuencia: frecuencia,
    );
    final d = <String, dynamic>{
      'monto': monto,
      'tasa_interes': interesMensual,
      'cuota': plan.cuota,
      'cantidad_cuotas': plan.cantidadCuotas,
      'monto_total': plan.montoTotal,
      'mora_diaria': moraDiaria,
      'dias_gracia': diasGracia,
      'frecuencia': frecuencia,
      'fecha_desembolso': fechaSql(fecha),
    };
    final saldado = yaPago >= plan.montoTotal;
    d['estado'] = saldado ? 'pagado' : 'en_calle';
    final proximo = proximoPago(d, yaPago);
    if (proximo != null) d['proximo_pago'] = fechaSql(proximo);
    return d;
  }

  double get montoTotal => calcularPlan(
        monto: monto,
        tasaInteresMensual: interesMensual,
        diasPlazo: diasPlazo,
        frecuencia: frecuencia,
      ).montoTotal;
}

/// Una fila del archivo ya revisada.
class FilaImportada {
  /// Número de la fila en el archivo (como lo ve en Excel: la 2 es la
  /// primera después de los títulos).
  final int fila;
  final Map<String, dynamic> cliente;
  final PrestamoImportado? prestamo;

  /// Lo que impide importarla (vacío si está bien).
  final List<String> errores;

  /// Ya hay un cliente con esa cédula (en la app o más arriba en el archivo).
  final bool repetido;

  const FilaImportada({
    required this.fila,
    required this.cliente,
    this.prestamo,
    this.errores = const [],
    this.repetido = false,
  });

  bool get lista => errores.isEmpty && !repetido;
  String get nombre => (cliente['nombre'] as String?) ?? '';
}

String? _texto(Object? v) {
  if (v == null) return null;
  if (v is double && v == v.roundToDouble()) return v.toInt().toString();
  final t = '$v'.trim();
  return t.isEmpty ? null : t;
}

/// Número de una celda: 25000, "25,000", "RD$ 25,000", "20%".
double? _numero(Object? v) {
  if (v is num) return v.toDouble();
  final t = _texto(v);
  if (t == null) return null;
  return double.tryParse(t.replaceAll(RegExp(r'[^0-9.\-]'), ''));
}

/// Fecha de una celda: fecha de Excel, número de serie de Excel, o texto
/// "15/9/2026", "15-09-2026" o "2026-09-15".
DateTime? _fecha(Object? v) {
  if (v is DateTime) return DateTime(v.year, v.month, v.day);
  if (v is num && v > 20000 && v < 80000) {
    // Días desde el 30/12/1899 (como cuenta Excel).
    final f = DateTime.utc(1899, 12, 30).add(Duration(days: v.floor()));
    return DateTime(f.year, f.month, f.day);
  }
  final t = _texto(v);
  if (t == null) return null;
  final iso = RegExp(r'^(\d{4})-(\d{1,2})-(\d{1,2})').firstMatch(t);
  if (iso != null) {
    return _fechaValida(int.parse(iso[1]!), int.parse(iso[2]!), int.parse(iso[3]!));
  }
  final dma = RegExp(r'^(\d{1,2})[/\-.](\d{1,2})[/\-.](\d{2,4})$').firstMatch(t);
  if (dma != null) {
    var anio = int.parse(dma[3]!);
    if (anio < 100) anio += 2000;
    return _fechaValida(anio, int.parse(dma[2]!), int.parse(dma[1]!));
  }
  return null;
}

DateTime? _fechaValida(int anio, int mes, int dia) {
  final f = DateTime(anio, mes, dia);
  return f.year == anio && f.month == mes && f.day == dia ? f : null;
}

String? _frecuencia(Object? v) {
  final t = _clave(_texto(v) ?? '');
  if (t.isEmpty) return null;
  if (t.startsWith('dia') || t == 'd') return 'diario';
  if (t.startsWith('sem') || t == 's') return 'semanal';
  if (t.startsWith('quin') || t == 'q' || t == '15') return 'quincenal';
  if (t.startsWith('mes') || t.startsWith('mens') || t == 'm') return 'mensual';
  return '';
}

/// Revisa las filas del archivo (la primera son los títulos). [cedulasExistentes]:
/// las de los clientes que ya están en la app (solo dígitos). [hoy]: para
/// no aceptar préstamos con fecha futura.
({List<FilaImportada> filas, List<String> faltan}) revisarArchivo(
  List<List<Object?>> celdas, {
  required Set<String> cedulasExistentes,
  required DateTime hoy,
}) {
  if (celdas.isEmpty) return (filas: const [], faltan: const ['El archivo está vacío']);
  final col = columnasDe(celdas.first);
  final faltan = [
    for (final (clave, titulo) in columnasImportacion.take(3))
      if (!col.containsKey(clave)) titulo,
  ];
  if (faltan.isNotEmpty) return (filas: const [], faltan: faltan);

  Object? celda(List<Object?> fila, String clave) {
    final i = col[clave];
    return i == null || i >= fila.length ? null : fila[i];
  }

  final vistas = <String>{...cedulasExistentes};
  final filas = <FilaImportada>[];
  for (var n = 1; n < celdas.length; n++) {
    final f = celdas[n];
    if (f.every((c) => _texto(c) == null)) continue; // fila vacía
    final errores = <String>[];

    final nombre = _texto(celda(f, 'nombre'))?.replaceAll(RegExp(r'\s+'), ' ');
    final cedula = _texto(celda(f, 'cedula'));
    final telefono = _texto(celda(f, 'telefono'));
    for (final e in [errorNombre(nombre), errorCedula(cedula), errorTelefono(telefono)]) {
      if (e != null) errores.add(e);
    }
    final digitosCedula = soloDigitos(cedula);
    final repetido = errorCedula(cedula) == null && !vistas.add(digitosCedula);

    final cliente = <String, dynamic>{
      'nombre': nombre,
      'cedula': formatearCedula(cedula ?? ''),
      'telefono': formatearTelefono(telefono ?? ''),
      if (_texto(celda(f, 'direccion')) case final d?) 'direccion': d,
    };

    PrestamoImportado? prestamo;
    final monto = _numero(celda(f, 'monto'));
    if (monto != null && monto > 0) {
      final interesCelda = _numero(celda(f, 'interes'));
      // 0.2 en una celda con formato de % es 20%.
      final interes = interesCelda == null
          ? null
          : (interesCelda > 0 && interesCelda < 1 ? interesCelda * 100 : interesCelda);
      final frecuencia = _frecuencia(celda(f, 'frecuencia'));
      final plazo = _numero(celda(f, 'plazo'))?.round();
      final fecha = _fecha(celda(f, 'fecha'));
      final pagado = _numero(celda(f, 'pagado')) ?? 0;
      final mora = _numero(celda(f, 'mora'));
      final gracia = _numero(celda(f, 'gracia'))?.round();

      if (interes == null || interes < 0) errores.add('Falta el interés mensual');
      if (frecuencia == null) {
        errores.add('Falta la frecuencia (diario, semanal, quincenal o mensual)');
      } else if (frecuencia.isEmpty) {
        errores.add('Frecuencia no válida: usa diario, semanal, quincenal o mensual');
      }
      if (plazo == null || plazo <= 0) errores.add('Falta el plazo en días');
      if (fecha == null) {
        errores.add('Falta la fecha del préstamo (día/mes/año)');
      } else if (fecha.isAfter(DateTime(hoy.year, hoy.month, hoy.day))) {
        errores.add('La fecha del préstamo es después de hoy');
      }
      if (pagado < 0) errores.add('"Ya pagó" no puede ser negativo');
      if (mora != null && mora < 0) errores.add('La mora no puede ser negativa');
      if (gracia != null && gracia < 0) errores.add('Los días de gracia no pueden ser negativos');

      if (errores.isEmpty) {
        prestamo = PrestamoImportado(
          monto: monto,
          interesMensual: interes!,
          frecuencia: frecuencia!,
          diasPlazo: plazo!,
          fecha: fecha!,
          yaPago: pagado,
          moraDiaria: mora ?? 5,
          diasGracia: gracia ?? 1,
        );
        if (pagado > prestamo.montoTotal) {
          errores.add('"Ya pagó" es más que el total del préstamo (${prestamo.montoTotal.round()})');
          prestamo = null;
        }
      }
    }

    filas.add(FilaImportada(
      fila: n + 1,
      cliente: cliente,
      prestamo: prestamo,
      errores: errores,
      repetido: repetido,
    ));
  }
  return (filas: filas, faltan: const []);
}

/// Las celdas de un Excel (.xlsx, la primera hoja) o de un CSV, como texto,
/// números o fechas.
List<List<Object?>> leerCeldas(Uint8List bytes, String nombreArchivo) {
  if (nombreArchivo.toLowerCase().endsWith('.csv')) return leerCsv(utf8.decode(bytes, allowMalformed: true));
  final excel = Excel.decodeBytes(bytes);
  final hoja = excel.tables.values.firstOrNull;
  if (hoja == null) return const [];
  return [
    for (final fila in hoja.rows)
      [
        for (final c in fila)
          switch (c?.value) {
            null => null,
            TextCellValue(:final value) => value.toString(),
            IntCellValue(:final value) => value,
            DoubleCellValue(:final value) => value,
            DateCellValue(:final year, :final month, :final day) => DateTime(year, month, day),
            DateTimeCellValue(:final year, :final month, :final day) => DateTime(year, month, day),
            final otro => otro.toString(),
          },
      ],
  ];
}

/// CSV separado por comas o por punto y coma (Excel en español usa ";"),
/// con comillas para los textos que llevan el separador.
List<List<Object?>> leerCsv(String texto) {
  final lineas = const LineSplitter().convert(texto.replaceFirst('﻿', ''));
  if (lineas.isEmpty) return const [];
  final sep = lineas.first.split(';').length > lineas.first.split(',').length ? ';' : ',';
  List<Object?> partir(String linea) {
    final celdas = <Object?>[];
    final actual = StringBuffer();
    var comillas = false;
    for (var i = 0; i < linea.length; i++) {
      final c = linea[i];
      if (c == '"') {
        if (comillas && i + 1 < linea.length && linea[i + 1] == '"') {
          actual.write('"');
          i++;
        } else {
          comillas = !comillas;
        }
      } else if (c == sep && !comillas) {
        celdas.add(actual.toString());
        actual.clear();
      } else {
        actual.write(c);
      }
    }
    celdas.add(actual.toString());
    return celdas;
  }

  return [for (final l in lineas) partir(l)];
}

/// La plantilla para llenar: títulos y dos filas de ejemplo.
Uint8List plantillaExcel() {
  final excel = Excel.createExcel();
  excel.rename('Sheet1', 'Clientes');
  final hoja = excel['Clientes'];
  hoja.appendRow([for (final (_, t) in columnasImportacion) TextCellValue(t)]);
  hoja.appendRow([
    TextCellValue('Juan Pérez Rodríguez'),
    TextCellValue('001-1234567-8'),
    TextCellValue('809-555-1234'),
    TextCellValue('C/ Duarte #12, Santiago'),
    IntCellValue(10000),
    IntCellValue(20),
    TextCellValue('semanal'),
    IntCellValue(60),
    TextCellValue('01/09/2026'),
    IntCellValue(4000),
    IntCellValue(5),
    IntCellValue(1),
  ]);
  hoja.appendRow([
    TextCellValue('María Gómez'), // sin préstamo en la calle
    TextCellValue('402-7654321-0'),
    TextCellValue('829-555-6789'),
    TextCellValue('Los Jardines'),
  ]);
  return Uint8List.fromList(excel.encode()!);
}
