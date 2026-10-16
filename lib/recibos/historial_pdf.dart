import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../logic/historial_pagos.dart';
import '../services/supabase_service.dart';
import 'recibo_pdf.dart' show NegocioRecibo, numeroReciboTexto, textoPdf;

String _rd(double v) {
  final formato = NumberFormat(v == v.roundToDouble() ? '#,##0' : '#,##0.00', 'en_US');
  return 'RD\$ ${formato.format(v)}';
}

String _fecha(DateTime f) => '${f.day}/${f.month}/${f.year}';

/// PDF del historial de pagos de un cliente, en papel carta: un bloque por
/// préstamo con cada cobro, y los totales.
Future<Uint8List> historialPdf({
  required List<PrestamoHistorial> prestamos,
  required NegocioRecibo negocio,
  required String cliente,
  String? cedula,
  required DateTime hoy,
  Uint8List? logo,
}) {
  pw.ImageProvider? imagenLogo;
  if (logo != null) {
    try {
      imagenLogo = pw.MemoryImage(logo);
    } catch (_) {
      imagenLogo = null; // formato que el PDF no entiende
    }
  }
  const normal = pw.TextStyle(fontSize: 10);
  const chico = pw.TextStyle(fontSize: 8, color: PdfColors.grey700);
  final negrita = pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold);
  final nombreNegocio = textoPdf(negocio.nombre).toUpperCase();
  final telefono = textoPdf(negocio.telefono ?? '');
  final direccion = textoPdf(negocio.direccion ?? '');

  pw.Widget bloque(PrestamoHistorial p) => pw.Container(
        margin: const pw.EdgeInsets.only(bottom: 14),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            pw.Container(
              color: PdfColors.grey200,
              padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              child: pw.Text(
                'Préstamo de ${_rd(p.monto)}'
                '${p.desde == null ? '' : ' - desde el ${_fecha(p.desde!)}'}'
                ' - total a pagar ${_rd(p.montoTotal)} - ${p.estadoTexto.toUpperCase()}',
                style: negrita,
              ),
            ),
            if (p.pagos.isEmpty)
              pw.Padding(
                padding: const pw.EdgeInsets.all(6),
                child: pw.Text('Sin pagos todavía.', style: normal),
              )
            else
              pw.TableHelper.fromTextArray(
                headers: ['Fecha', 'Recibo', 'Monto', 'A mora', 'Nota'],
                data: [
                  for (final pago in p.pagos)
                    [
                      _fecha(pago.fecha),
                      numeroReciboTexto(pago.numeroRecibo),
                      _rd(pago.monto),
                      pago.montoMora > 0 ? _rd(pago.montoMora) : '-',
                      pago.anulado
                          ? textoPdf('ANULADO${(pago.motivoAnulacion ?? '').trim().isEmpty ? '' : ': ${pago.motivoAnulacion}'}')
                          : '',
                    ],
                ],
                border: pw.TableBorder.all(width: 0.4, color: PdfColors.grey500),
                headerStyle: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
                cellStyle: const pw.TextStyle(fontSize: 9),
                cellAlignments: {
                  0: pw.Alignment.centerLeft,
                  1: pw.Alignment.center,
                  2: pw.Alignment.centerRight,
                  3: pw.Alignment.centerRight,
                  4: pw.Alignment.centerLeft,
                },
                cellPadding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              ),
            pw.SizedBox(height: 4),
            pw.Align(
              alignment: pw.Alignment.centerRight,
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Text(
                    'Pagado: ${_rd(p.pagado)}'
                    '${p.moraPagada > 0 ? ' (incluye mora ${_rd(p.moraPagada)})' : ''}',
                    style: negrita,
                  ),
                  if (p.enLaCalle)
                    pw.Text(
                      'Falta por pagar: ${_rd(p.balance)}'
                      '${p.moraPendiente > 0 ? ' (incluye mora ${_rd(p.moraPendiente)})' : ''}',
                      style: negrita,
                    ),
                ],
              ),
            ),
          ],
        ),
      );

  final totalPagado = prestamos.fold<double>(0, (s, p) => s + p.pagado);
  final totalPendiente = prestamos.fold<double>(0, (s, p) => s + p.balance);

  final doc = pw.Document(title: 'Historial de pagos - ${textoPdf(cliente)}', author: nombreNegocio);
  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.letter,
      margin: const pw.EdgeInsets.symmetric(horizontal: 48, vertical: 40),
      footer: (c) => pw.Align(
        alignment: pw.Alignment.centerRight,
        child: pw.Text('Página ${c.pageNumber} de ${c.pagesCount}', style: chico),
      ),
      build: (_) => [
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            if (imagenLogo != null)
              pw.Padding(
                padding: const pw.EdgeInsets.only(right: 12),
                child: pw.ConstrainedBox(
                  constraints: const pw.BoxConstraints(maxHeight: 50, maxWidth: 110),
                  child: pw.Image(imagenLogo, fit: pw.BoxFit.contain),
                ),
              ),
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(nombreNegocio,
                      style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
                  if (direccion.isNotEmpty) pw.Text(direccion, style: chico),
                  if (telefono.isNotEmpty) pw.Text('Tel. $telefono', style: chico),
                ],
              ),
            ),
          ],
        ),
        pw.SizedBox(height: 14),
        pw.Text('HISTORIAL DE PAGOS', style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 4),
        pw.Text('Cliente: ${textoPdf(cliente)}', style: normal),
        if (cedula != null && cedula.trim().isNotEmpty) pw.Text('Cédula: $cedula', style: normal),
        pw.Text('Emitido el ${_fecha(hoy)}', style: normal),
        pw.SizedBox(height: 14),
        if (prestamos.isEmpty) pw.Text('Este cliente no tiene préstamos con pagos.', style: normal),
        for (final p in prestamos) bloque(p),
        if (prestamos.length > 1) ...[
          pw.Divider(),
          pw.Align(
            alignment: pw.Alignment.centerRight,
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Text('Total pagado en todos los préstamos: ${_rd(totalPagado)}', style: negrita),
                if (totalPendiente > 0)
                  pw.Text('Total que falta por pagar: ${_rd(totalPendiente)}', style: negrita),
              ],
            ),
          ),
        ],
        pw.SizedBox(height: 10),
        pw.Text('Los cobros anulados se muestran pero no cuentan en los totales.', style: chico),
      ],
    ),
  );
  return doc.save();
}

/// Arma el PDF del historial y abre el menú para compartirlo (en Android)
/// o lo descarga (en la web).
Future<void> compartirHistorial({
  required List<PrestamoHistorial> prestamos,
  required String cliente,
  String? cedula,
}) async {
  final servicio = SupabaseService.instance;
  final perfil = await servicio.perfilDelNegocio();
  final negocio = NegocioRecibo.dePerfil(perfil);
  final bytes = await historialPdf(
    prestamos: prestamos,
    negocio: negocio,
    cliente: cliente,
    cedula: cedula,
    hoy: DateTime.now(),
    logo: await servicio.bajarFoto(negocio.logo),
  );
  final nombre = textoPdf(cliente).toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_');
  await Printing.sharePdf(bytes: bytes, filename: 'historial_$nombre.pdf');
}
