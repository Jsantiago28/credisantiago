// Ticket para impresora térmica (ESC/POS): el mismo recibo del PDF, en
// texto, para papel de 58 mm (32 letras por línea) o de 80 mm (48).

import 'dart:typed_data';

import 'package:intl/intl.dart';

import '../recibos/recibo_pdf.dart' show NegocioRecibo, numeroReciboTexto;
import 'calculo_prestamo.dart';

/// Letras por línea según el papel.
int anchoPapel(int mm) => mm >= 80 ? 48 : 32;

/// Una línea del ticket: texto, alineación y si va grande o en negrita.
class LineaTicket {
  final String texto;
  final bool centro;
  final bool negrita;

  /// Doble de alto y de ancho (para el nombre del negocio).
  final bool grande;

  const LineaTicket(this.texto, {this.centro = false, this.negrita = false, this.grande = false});
}

String _rd(double v) =>
    'RD\$${NumberFormat(v == v.roundToDouble() ? '#,##0' : '#,##0.00', 'en_US').format(v)}';

String _fecha(DateTime f) => '${f.day}/${f.month}/${f.year}';

String _fechaHora(DateTime f) {
  final hora = f.hour % 12 == 0 ? 12 : f.hour % 12;
  return '${_fecha(f)} $hora:${f.minute.toString().padLeft(2, '0')} ${f.hour < 12 ? 'am' : 'pm'}';
}

/// Texto a la izquierda y valor a la derecha en una línea de [ancho]. Si no
/// caben, el valor baja a la línea siguiente, pegado a la derecha.
List<String> filaDosColumnas(String izquierda, String derecha, int ancho) {
  final espacio = ancho - izquierda.length - derecha.length;
  if (espacio >= 1) return [izquierda + ' ' * espacio + derecha];
  return [
    ..._partir(izquierda, ancho),
    for (final l in _partir(derecha, ancho)) l.padLeft(ancho),
  ];
}

/// Parte un texto largo en líneas de [ancho], sin cortar palabras si se puede.
List<String> _partir(String texto, int ancho) {
  final lineas = <String>[];
  var actual = '';
  for (final palabra in texto.split(RegExp(r'\s+')).where((p) => p.isNotEmpty)) {
    var p = palabra;
    while (p.length > ancho) {
      if (actual.isNotEmpty) {
        lineas.add(actual);
        actual = '';
      }
      lineas.add(p.substring(0, ancho));
      p = p.substring(ancho);
    }
    if (actual.isEmpty) {
      actual = p;
    } else if (actual.length + 1 + p.length <= ancho) {
      actual = '$actual $p';
    } else {
      lineas.add(actual);
      actual = p;
    }
  }
  if (actual.isNotEmpty) lineas.add(actual);
  return lineas;
}

/// Las líneas del ticket (sin los comandos de la impresora). Es lo que se
/// prueba y lo que luego se convierte a bytes con [ticketEscPos].
List<LineaTicket> lineasTicket({
  required DatosRecibo r,
  required NegocioRecibo negocio,
  required String cliente,
  String? cedula,
  String? cobradoPor,
  int papelMm = 58,
}) {
  final ancho = anchoPapel(papelMm);
  final raya = '-' * ancho;
  List<LineaTicket> fila(String a, String b, {bool negrita = false}) => [
        for (final l in filaDosColumnas(a, b, ancho)) LineaTicket(l, negrita: negrita),
      ];
  List<LineaTicket> centrado(String texto, {bool negrita = false}) => [
        for (final l in _partir(texto, ancho)) LineaTicket(l, centro: true, negrita: negrita),
      ];

  return [
    // Grande = doble de ancho: caben la mitad de letras.
    for (final l in _partir(negocio.nombre.toUpperCase(), ancho ~/ 2))
      LineaTicket(l, centro: true, negrita: true, grande: true),
    if ((negocio.direccion ?? '').trim().isNotEmpty) ...centrado(negocio.direccion!.trim()),
    if ((negocio.telefono ?? '').trim().isNotEmpty) ...centrado('Tel. ${negocio.telefono!.trim()}'),
    const LineaTicket(''),
    const LineaTicket('RECIBO DE PAGO', centro: true, negrita: true),
    LineaTicket(numeroReciboTexto(r.numero), centro: true),
    LineaTicket(_fechaHora(r.fecha), centro: true),
    LineaTicket(raya),
    ...fila('Cliente', cliente),
    if (cedula != null && cedula.isNotEmpty) ...fila('Cédula', cedula),
    if (cobradoPor != null && cobradoPor.trim().isNotEmpty) ...fila('Cobrado por', cobradoPor),
    LineaTicket(raya),
    ...fila('MONTO RECIBIDO', _rd(r.monto), negrita: true),
    ...fila('  A cuota', _rd(r.aCuota)),
    if (r.aMora > 0) ...fila('  A mora', _rd(r.aMora)),
    if (r.cubre.isNotEmpty) ...[
      const LineaTicket('Cubre:'),
      for (final c in r.cubre)
        for (final l in _partir('- $c', ancho - 2)) LineaTicket('  $l'),
    ],
    LineaTicket(raya),
    if (r.saldado)
      const LineaTicket('PRÉSTAMO SALDADO', centro: true, negrita: true)
    else ...[
      ...fila('Balance pendiente', _rd(r.balanceDespues), negrita: true),
      if (r.moraPendienteDespues > 0) ...fila('  Incluye mora', _rd(r.moraPendienteDespues)),
      if (r.proximoPagoFecha != null) ...[
        ...fila('Próximo pago', _fecha(r.proximoPagoFecha!)),
        ...fila('  Monto', _rd(r.proximoPagoMonto)),
      ],
    ],
    LineaTicket(raya),
    if (negocio.mensaje.trim().isNotEmpty) ...centrado(negocio.mensaje.trim()),
  ];
}

/// Letras del español en la tabla de caracteres PC850 (la que traen casi
/// todas las impresoras térmicas). Lo que no está en la tabla se cambia por
/// la letra sin acento o se quita.
const _pc850 = {
  'á': 0xA0, 'é': 0x82, 'í': 0xA1, 'ó': 0xA2, 'ú': 0xA3, 'ñ': 0xA4, 'Ñ': 0xA5,
  'Á': 0xB5, 'É': 0x90, 'Í': 0xD6, 'Ó': 0xE0, 'Ú': 0xE9, 'ü': 0x81, 'Ü': 0x9A,
  '¿': 0xA8, '¡': 0xAD, '°': 0xF8,
};

const _sinAcento = {
  '“': '"', '”': '"', '‘': "'", '’': "'", '–': '-', '—': '-', '…': '...', '•': '-',
  'à': 'a', 'è': 'e', 'ì': 'i', 'ò': 'o', 'ù': 'u', 'À': 'A', 'È': 'E', 'Ì': 'I', 'Ò': 'O', 'Ù': 'U',
};

List<int> textoPc850(String texto) {
  final bytes = <int>[];
  for (final runa in texto.runes) {
    final c = String.fromCharCode(runa);
    if (runa >= 0x20 && runa <= 0x7E) {
      bytes.add(runa);
    } else if (_pc850.containsKey(c)) {
      bytes.add(_pc850[c]!);
    } else if (_sinAcento.containsKey(c)) {
      bytes.addAll(_sinAcento[c]!.codeUnits);
    }
    // Emojis y demás: se quitan.
  }
  return bytes;
}

/// Comandos ESC/POS del ticket: listo para mandar a la impresora.
Uint8List ticketEscPos(List<LineaTicket> lineas) {
  const esc = 0x1B, gs = 0x1D;
  final b = <int>[
    esc, 0x40, // reiniciar
    esc, 0x74, 2, // tabla de caracteres PC850 (acentos y ñ)
  ];
  for (final l in lineas) {
    b.addAll([esc, 0x61, l.centro ? 1 : 0]); // alineación
    b.addAll([esc, 0x45, l.negrita ? 1 : 0]); // negrita
    b.addAll([gs, 0x21, l.grande ? 0x11 : 0x00]); // tamaño
    b.addAll(textoPc850(l.texto));
    b.add(0x0A);
  }
  b.addAll([esc, 0x61, 0, esc, 0x45, 0, gs, 0x21, 0]);
  b.addAll([esc, 0x64, 4]); // avanzar 4 líneas para poder arrancar el papel
  b.addAll([gs, 0x56, 66, 0]); // cortar (si la impresora tiene cuchilla)
  return Uint8List.fromList(b);
}
