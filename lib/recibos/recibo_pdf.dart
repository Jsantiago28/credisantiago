import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../logic/calculo_prestamo.dart';

/// Lo que el prestamista pone en el encabezado y el pie de sus recibos
/// (Perfil → Mi recibo). Lo que deja vacío toma un valor de siempre.
class NegocioRecibo {
  final String nombre;
  final String? telefono;
  final String? direccion;
  final String mensaje;

  /// Ubicación del logo en el bucket de fotos (null si no puso logo).
  final String? logo;

  static const mensajeDeSiempre = 'Gracias por su pago.';

  const NegocioRecibo({
    required this.nombre,
    this.telefono,
    this.direccion,
    this.mensaje = mensajeDeSiempre,
    this.logo,
  });

  /// Nombre: el del negocio o, si no hay, el del prestamista. Teléfono: el
  /// del recibo o, si no hay, su WhatsApp o el de su cuenta.
  factory NegocioRecibo.dePerfil(Map<String, dynamic>? perfil) {
    String? texto(String campo) {
      final v = (perfil?[campo] as String?)?.trim();
      return v == null || v.isEmpty ? null : v;
    }

    return NegocioRecibo(
      nombre: texto('negocio') ?? texto('nombre') ?? 'Prestamista',
      telefono: texto('recibo_telefono') ?? texto('whatsapp') ?? texto('phone'),
      direccion: texto('recibo_direccion'),
      mensaje: texto('recibo_mensaje') ?? mensajeDeSiempre,
      logo: texto('recibo_logo'),
    );
  }
}

/// La letra estándar del PDF solo trae las letras del español y poco más:
/// un emoji o unas comillas "curvas" lo dañan. Las comillas y rayas se
/// cambian por las rectas y lo demás se quita.
String textoPdf(String texto) {
  const cambios = {
    '‘': "'", '’': "'", '“': '"', '”': '"', '–': '-', '—': '-', '…': '...', '•': '-',
  };
  final salida = StringBuffer();
  for (final letra in texto.runes) {
    final c = String.fromCharCode(letra);
    if (cambios.containsKey(c)) {
      salida.write(cambios[c]);
    } else if (letra == 0x0A || (letra >= 0x20 && letra <= 0x7E) || (letra >= 0xA0 && letra <= 0xFF)) {
      salida.write(c);
    }
  }
  return salida.toString().replaceAll(RegExp(r'[ \t]+'), ' ').trim();
}

/// Número de recibo como se imprime: #000012.
String numeroReciboTexto(int? numero) =>
    numero == null ? 'S/N' : '#${numero.toString().padLeft(6, '0')}';

String _rd(double v) {
  final formato = NumberFormat(v == v.roundToDouble() ? '#,##0' : '#,##0.00', 'en_US');
  return 'RD\$ ${formato.format(v)}';
}

String _fecha(DateTime f) => '${f.day}/${f.month}/${f.year}';

String _fechaHora(DateTime f) {
  final hora = f.hour % 12 == 0 ? 12 : f.hour % 12;
  final ampm = f.hour < 12 ? 'am' : 'pm';
  return '${_fecha(f)} $hora:${f.minute.toString().padLeft(2, '0')} $ampm';
}

/// PDF del recibo, en formato de rollo de 80 mm (como un recibo de caja).
/// [logo] son los bytes de la imagen (se bajan aparte); si no se pueden
/// leer, el recibo sale sin logo.
Future<Uint8List> reciboPdf({
  required DatosRecibo r,
  required NegocioRecibo negocio,
  Uint8List? logo,
  String? cobradoPor,
  required String cliente,
  String? cedula,
}) {
  pw.ImageProvider? imagenLogo;
  if (logo != null) {
    try {
      imagenLogo = pw.MemoryImage(logo);
    } catch (_) {
      imagenLogo = null; // formato que el PDF no entiende
    }
  }
  final nombreNegocio = textoPdf(negocio.nombre);
  final telefono = textoPdf(negocio.telefono ?? '');
  final direccion = textoPdf(negocio.direccion ?? '');
  final mensaje = textoPdf(negocio.mensaje);

  const chico = pw.TextStyle(fontSize: 8);
  const normal = pw.TextStyle(fontSize: 9);
  final negrita = pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold);

  pw.Widget fila(String etiqueta, String valor, {pw.TextStyle? estilo, double sangria = 0}) =>
      pw.Padding(
        padding: pw.EdgeInsets.only(left: sangria, top: 1, bottom: 1),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [pw.Text(etiqueta, style: estilo ?? normal), pw.Text(valor, style: estilo ?? normal)],
        ),
      );

  pw.Widget linea() => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 4),
        child: pw.Divider(thickness: 0.5, borderStyle: pw.BorderStyle.dashed),
      );

  final doc = pw.Document(title: 'Recibo ${numeroReciboTexto(r.numero)}', author: nombreNegocio);
  doc.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.roll80,
      build: (_) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          if (imagenLogo != null)
            pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 4),
              child: pw.Center(
                child: pw.ConstrainedBox(
                  constraints: const pw.BoxConstraints(maxHeight: 50, maxWidth: 120),
                  child: pw.Image(imagenLogo, fit: pw.BoxFit.contain),
                ),
              ),
            ),
          pw.Text(nombreNegocio.toUpperCase(),
              textAlign: pw.TextAlign.center,
              style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
          if (direccion.isNotEmpty)
            pw.Text(direccion, textAlign: pw.TextAlign.center, style: chico),
          if (telefono.isNotEmpty)
            pw.Text('Tel. $telefono', textAlign: pw.TextAlign.center, style: chico),
          pw.SizedBox(height: 6),
          pw.Text('RECIBO DE PAGO', textAlign: pw.TextAlign.center, style: negrita),
          pw.Text(numeroReciboTexto(r.numero), textAlign: pw.TextAlign.center, style: normal),
          pw.Text(_fechaHora(r.fecha), textAlign: pw.TextAlign.center, style: chico),
          linea(),
          fila('Cliente', textoPdf(cliente)),
          if (cedula != null && cedula.isNotEmpty) fila('Cédula', cedula),
          if (cobradoPor != null && cobradoPor.trim().isNotEmpty)
            fila('Cobrado por', textoPdf(cobradoPor)),
          linea(),
          fila('MONTO RECIBIDO', _rd(r.monto), estilo: negrita),
          fila('A cuota', _rd(r.aCuota), sangria: 8),
          if (r.aMora > 0) fila('A mora', _rd(r.aMora), sangria: 8),
          if (r.cubre.isNotEmpty) ...[
            pw.SizedBox(height: 4),
            pw.Text('Cubre:', style: normal),
            for (final c in r.cubre)
              pw.Padding(
                padding: const pw.EdgeInsets.only(left: 8),
                // Guion y no viñeta: la fuente estándar del PDF no trae "•".
                child: pw.Text('- $c', style: normal),
              ),
          ],
          linea(),
          if (r.saldado)
            pw.Text('PRÉSTAMO SALDADO', textAlign: pw.TextAlign.center, style: negrita)
          else ...[
            fila('Balance pendiente', _rd(r.balanceDespues), estilo: negrita),
            if (r.moraPendienteDespues > 0)
              fila('Incluye mora', _rd(r.moraPendienteDespues), sangria: 8),
            if (r.proximoPagoFecha != null) ...[
              pw.SizedBox(height: 4),
              fila('Próximo pago', _fecha(r.proximoPagoFecha!)),
              fila('Monto', _rd(r.proximoPagoMonto), sangria: 8),
            ],
          ],
          linea(),
          if (mensaje.isNotEmpty)
            pw.Text(mensaje, textAlign: pw.TextAlign.center, style: chico),
        ],
      ),
    ),
  );
  return doc.save();
}
