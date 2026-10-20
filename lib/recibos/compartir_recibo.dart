import 'dart:typed_data';

import 'package:printing/printing.dart';

import '../logic/calculo_prestamo.dart';
import '../services/supabase_service.dart';
import 'recibo_pdf.dart';

/// Todo lo que lleva un recibo (el PDF y el ticket de la impresora).
typedef ReciboListo = ({
  DatosRecibo r,
  NegocioRecibo negocio,
  String cliente,
  String? cedula,
  String? cobradoPor,
  int? numero,
});

/// Junta los datos del recibo de `pago`: cómo quedó el préstamo después de
/// ese cobro, el negocio, el cliente y quién cobró.
///
/// Un cobro hecho sin señal ([PagoRegistrado.sinSubir]) se arma con lo que
/// ya hay en el teléfono: [pagosLocales] (los cobros del préstamo, con ese)
/// y [cliente].
Future<ReciboListo> prepararRecibo({
  required Map<String, dynamic> prestamo,
  required PagoRegistrado pago,
  List<PagoRegistrado>? pagosLocales,
  Map<String, dynamic>? cliente,
}) async {
  final servicio = SupabaseService.instance;
  if (pago.sinSubir) {
    final pagos = [...?pagosLocales];
    if (!pagos.contains(pago)) pagos.add(pago);
    final perfil = await servicio.perfilDelNegocio();
    return (
      r: datosRecibo(prestamo, pagos, pago),
      negocio: NegocioRecibo.dePerfil(perfil),
      cliente: cliente?['nombre'] as String? ?? '',
      cedula: null,
      cobradoPor: servicio.sesionCobrador?.cobradorNombre,
      numero: null,
    );
  }
  final pagos = await servicio.obtenerPagos(prestamo['id']);
  // El pago ya está guardado; se usa la versión de la lista para que el
  // recibo se calcule con el mismo orden que el resto de la app.
  final guardado = pagos.firstWhere((p) => p.id == pago.id, orElse: () => pago);
  if (!pagos.contains(guardado)) pagos.add(guardado);

  final perfil = await servicio.perfilDelNegocio();
  final datosCliente = await servicio.obtenerClienteDePrestamo(prestamo);

  return (
    r: datosRecibo(prestamo, pagos, guardado),
    negocio: NegocioRecibo.dePerfil(perfil),
    cliente: datosCliente?['nombre'] as String? ?? '',
    cedula: datosCliente?['cedula'] as String?,
    cobradoPor: await _cobradoPor(guardado, prestamo),
    numero: guardado.numeroRecibo,
  );
}

/// Arma el PDF del recibo de `pago` y abre el menú para compartirlo (en
/// Android) o lo descarga (en la web).
Future<void> compartirRecibo({
  required Map<String, dynamic> prestamo,
  required PagoRegistrado pago,
  List<PagoRegistrado>? pagosLocales,
  Map<String, dynamic>? cliente,
}) async {
  final recibo = await prepararRecibo(
      prestamo: prestamo, pago: pago, pagosLocales: pagosLocales, cliente: cliente);
  Uint8List? logo;
  try {
    logo = await SupabaseService.instance.bajarFoto(recibo.negocio.logo);
  } catch (_) {
    // Sin señal: el recibo sale sin el logo.
  }
  final bytes = await reciboPdf(
    r: recibo.r,
    negocio: recibo.negocio,
    logo: logo,
    cobradoPor: recibo.cobradoPor,
    cliente: recibo.cliente,
    cedula: recibo.cedula,
  );

  final numero = recibo.numero?.toString().padLeft(6, '0') ?? 'sn';
  await Printing.sharePdf(bytes: bytes, filename: 'recibo_$numero.pdf');
}

/// Nombre del cobrador que hizo el cobro (null si lo cobró el prestamista).
Future<String?> _cobradoPor(PagoRegistrado pago, Map<String, dynamic> prestamo) async {
  final servicio = SupabaseService.instance;
  final sesion = servicio.sesionCobrador;
  if (sesion != null) return pago.cobradorId == sesion.cobradorId ? sesion.cobradorNombre : null;
  if (pago.cobradorId == null) return null;
  final cobradores = await servicio.listarCobradores(prestamo['prestamista_id'] as String);
  for (final c in cobradores) {
    if (c.id == pago.cobradorId) return c.nombre;
  }
  return null;
}
