import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../logic/contrato.dart';
import '../services/supabase_service.dart';
import 'recibo_pdf.dart' show textoPdf;

const _raya = '______________________';

String _rd(double v) {
  final formato = NumberFormat(v == v.roundToDouble() ? '#,##0' : '#,##0.00', 'en_US');
  return 'RD\$ ${formato.format(v)}';
}

String _fecha(DateTime? f) => f == null ? '____/____/______' : '${f.day}/${f.month}/${f.year}';

/// PDF del contrato, en papel carta, listo para imprimir y firmar a mano.
/// [logo] son los bytes de la imagen; si no se pueden leer, sale sin logo.
Future<Uint8List> contratoPdf(DatosContrato d, {Uint8List? logo}) {
  pw.ImageProvider? imagenLogo;
  if (logo != null) {
    try {
      imagenLogo = pw.MemoryImage(logo);
    } catch (_) {
      imagenLogo = null; // formato que el PDF no entiende
    }
  }

  const normal = pw.TextStyle(fontSize: 10, lineSpacing: 2);
  final negrita = pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold);
  final titulo = pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold);

  String t(String? texto) => texto == null ? _raya : textoPdf(texto);

  final prestamista = textoPdf(d.prestamista).toUpperCase();
  final cliente = d.cliente.isEmpty ? _raya : textoPdf(d.cliente).toUpperCase();

  /// Cláusula: el nombre en negrita y el texto seguido.
  pw.Widget clausula(String nombre, String texto) => pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 9),
        child: pw.RichText(
          textAlign: pw.TextAlign.justify,
          text: pw.TextSpan(
            style: normal,
            children: [
              pw.TextSpan(text: '$nombre. ', style: negrita),
              pw.TextSpan(text: texto),
            ],
          ),
        ),
      );

  final cuota = d.cuota;
  final ultima = d.ultimaCuota;
  final condiciones = <(String, String)>[
    ('Monto principal', _rd(d.monto)),
    ('Tasa de interés', d.tasaTexto),
    ('Monto total a pagar', _rd(d.montoTotal)),
    ('Cantidad de cuotas', d.cuotas.isEmpty ? _raya : '${d.cuotas.length}'),
    (
      'Valor de cada cuota',
      cuota == null
          ? _raya
          : ultima != null && ultima != cuota && d.cuotas.length > 1
              ? '${_rd(cuota)} (la última de ${_rd(ultima)})'
              : _rd(cuota),
    ),
    ('Frecuencia', d.frecuenciaTexto),
    ('Fecha del primer pago', _fecha(d.primerPago)),
    ('Fecha del último pago', _fecha(d.ultimoPago)),
    ('Mora por atraso', d.moraTexto ?? 'No aplica'),
    ('Medio o lugar de pago', 'En efectivo al prestamista o a su cobrador, o por transferencia'),
  ];

  pw.Widget firma(String parte, String nombre, String? cedula, String etiquetaCedula) =>
      pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.SizedBox(height: 50), // espacio para firmar con lapicero
          pw.Container(width: 210, height: 0.8, color: PdfColors.black),
          pw.SizedBox(height: 3),
          pw.Text(parte, style: negrita),
          pw.Text('Nombre: $nombre', style: normal),
          pw.Text('$etiquetaCedula: ${t(cedula)}', style: normal),
          pw.Text('Fecha: ${_fecha(d.fecha)}', style: normal),
        ],
      );

  final representada = d.representante == null
      ? ''
      : ', representado por ${textoPdf(d.representante!).toUpperCase()}';
  final domicilioPrestamista = d.prestamistaDomicilio == null
      ? ''
      : ', con domicilio en ${textoPdf(d.prestamistaDomicilio!)}';
  final lugar = d.ciudad == null ? _raya : textoPdf(d.ciudad!);
  final mora = d.moraTexto;

  final doc = pw.Document(title: 'Contrato de préstamo - ${textoPdf(d.cliente)}', author: prestamista);
  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.letter,
      margin: const pw.EdgeInsets.symmetric(horizontal: 56, vertical: 48),
      footer: (contexto) => pw.Align(
        alignment: pw.Alignment.centerRight,
        child: pw.Text('Página ${contexto.pageNumber} de ${contexto.pagesCount}',
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
      ),
      build: (_) => [
        if (imagenLogo != null)
          pw.Center(
            child: pw.ConstrainedBox(
              constraints: const pw.BoxConstraints(maxHeight: 55, maxWidth: 160),
              child: pw.Image(imagenLogo, fit: pw.BoxFit.contain),
            ),
          ),
        pw.Center(child: pw.Text('CONTRATO DE PRÉSTAMO', style: titulo)),
        pw.SizedBox(height: 2),
        pw.Center(child: pw.Text(prestamista, style: negrita)),
        pw.SizedBox(height: 16),
        pw.RichText(
          text: pw.TextSpan(style: normal, children: [
            pw.TextSpan(text: 'Lugar y fecha: ', style: negrita),
            pw.TextSpan(text: '$lugar, ${fechaContrato(d.fecha)}.'),
          ]),
        ),
        pw.SizedBox(height: 12),
        clausula(
          'PRIMERA: IDENTIFICACIÓN DE LAS PARTES',
          'De una parte, $prestamista, cédula/RNC núm. ${t(d.prestamistaCedula)}'
              '$representada$domicilioPrestamista, en lo adelante "EL PRESTAMISTA"; '
              'y de la otra parte, $cliente, cédula núm. ${t(d.clienteCedula)}, '
              'domiciliado(a) en ${t(d.clienteDomicilio)}, en lo adelante "EL PRESTATARIO", '
              'acuerdan lo siguiente:',
        ),
        clausula(
          'SEGUNDA: MONTO DEL PRÉSTAMO',
          'EL PRESTAMISTA entrega a EL PRESTATARIO, en calidad de préstamo, la suma de '
              '${_rd(d.monto)} (${montoEnLetras(d.monto)}), que EL PRESTATARIO declara '
              'haber recibido conforme a las condiciones indicadas en este documento.',
        ),
        clausula('TERCERA: CONDICIONES DE PAGO',
            'Las partes acuerdan el siguiente plan de pago:'),
        pw.Table(
          border: pw.TableBorder.all(width: 0.6),
          columnWidths: const {0: pw.FlexColumnWidth(2), 1: pw.FlexColumnWidth(3)},
          children: [
            for (final (etiqueta, valor) in condiciones)
              pw.TableRow(children: [
                pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 3),
                  child: pw.Text(etiqueta, style: negrita),
                ),
                pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 3),
                  child: pw.Text(valor, style: normal),
                ),
              ]),
          ],
        ),
        pw.SizedBox(height: 10),
        clausula(
          'CUARTA: COMPROMISO DE PAGO',
          'EL PRESTATARIO se compromete a pagar las cuotas en las fechas acordadas, según '
              'el calendario de pagos al final de este documento, y a conservar los '
              'comprobantes de pago. Cualquier modificación del calendario o de las '
              'condiciones deberá constar por escrito y ser aceptada por ambas partes.',
        ),
        clausula(
          'QUINTA: ATRASOS Y GESTIONES DE COBRO',
          '${mora == null ? 'Este préstamo no genera cargos por mora. ' : 'Si una cuota no se paga a tiempo, se cobrará una mora de $mora, como se indica en la cláusula TERCERA. '}'
              'En caso de atraso, EL PRESTAMISTA podrá realizar las gestiones de cobro que '
              'correspondan conforme a este contrato y a la legislación vigente.',
        ),
        clausula(
          'SEXTA: ACEPTACIÓN',
          'Las partes declaran haber leído y comprendido las condiciones indicadas y firman '
              'voluntariamente dos ejemplares del mismo tenor, en el lugar y fecha señalados.',
        ),
        pw.SizedBox(height: 12),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            firma('EL PRESTAMISTA', textoPdf(d.representante ?? d.prestamista),
                d.prestamistaCedula, 'Cédula/RNC'),
            firma('EL PRESTATARIO', d.cliente.isEmpty ? _raya : textoPdf(d.cliente),
                d.clienteCedula, 'Cédula'),
          ],
        ),
        if (d.cuotas.isNotEmpty) ...[
          pw.SizedBox(height: 24),
          pw.Text('CALENDARIO DE PAGOS', style: negrita),
          pw.SizedBox(height: 6),
          pw.TableHelper.fromTextArray(
            headers: ['Cuota', 'Fecha', 'Monto'],
            data: [
              for (final c in d.cuotas) ['${c.numero}', _fecha(c.fecha), _rd(c.monto)],
            ],
            border: pw.TableBorder.all(width: 0.5),
            headerStyle: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
            cellStyle: const pw.TextStyle(fontSize: 9),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
            cellAlignments: {
              0: pw.Alignment.center,
              1: pw.Alignment.center,
              2: pw.Alignment.centerRight,
            },
            cellPadding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          ),
          pw.SizedBox(height: 4),
          pw.Align(
            alignment: pw.Alignment.centerRight,
            child: pw.Text('Total: ${_rd(d.montoTotal)}', style: negrita),
          ),
        ],
      ],
    ),
  );
  return doc.save();
}

/// Arma el contrato de `prestamo` y abre el menú para compartirlo (en
/// Android) o lo descarga (en la web).
Future<void> compartirContrato(Map<String, dynamic> prestamo) async {
  final servicio = SupabaseService.instance;
  final perfil = await servicio.perfilDelNegocio();
  final cliente = await servicio.obtenerClienteDePrestamo(prestamo);
  final datos = datosContrato(
    prestamo: prestamo,
    cliente: cliente,
    perfil: perfil,
    hoy: DateTime.now(),
  );
  final bytes = await contratoPdf(
    datos,
    logo: await servicio.bajarFoto(perfil?['recibo_logo'] as String?),
  );
  final nombre = textoPdf(datos.cliente).toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_');
  await Printing.sharePdf(bytes: bytes, filename: 'contrato_$nombre.pdf');
}
