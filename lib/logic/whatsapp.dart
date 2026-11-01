import 'package:intl/intl.dart';

import 'calculo_prestamo.dart';

/// Número en formato internacional para WhatsApp (solo dígitos, con código
/// de país). Los de RD (809/829/849, 10 dígitos) llevan el 1 delante.
/// Devuelve null si no parece un teléfono.
String? telefonoWhatsApp(String? telefono) {
  if (telefono == null) return null;
  final digitos = telefono.replaceAll(RegExp(r'\D'), '');
  if (digitos.length == 10 && RegExp(r'^8[024]9').hasMatch(digitos)) return '1$digitos';
  if (digitos.length < 10) return null;
  return digitos;
}

/// Enlace que abre WhatsApp para compartir el mensaje con quien uno elija
/// (sin número: WhatsApp pregunta a quién mandarlo).
Uri enlaceCompartirWhatsApp(String mensaje) => Uri.https('wa.me', '/', {'text': mensaje});

/// Enlace que abre el chat de WhatsApp con el mensaje ya escrito.
Uri? enlaceWhatsApp(String? telefono, String mensaje) {
  final numero = telefonoWhatsApp(telefono);
  if (numero == null) return null;
  return Uri.https('wa.me', '/$numero', {'text': mensaje});
}

String _rd(double v) =>
    'RD\$${NumberFormat(v == v.roundToDouble() ? '#,##0' : '#,##0.00', 'en_US').format(v)}';

const _meses = ['ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'sep', 'oct', 'nov', 'dic'];

/// Mensaje de cobro según cómo está el préstamo hoy: atrasado (con mora),
/// cuota que vence hoy, o recordatorio de la próxima cuota.
String mensajeCobro({
  required String nombreCliente,
  required String negocio,
  required EstadoPrestamo estado,
  required DateTime hoy,
}) {
  final nombre = nombreCliente.trim().split(RegExp(r'\s+')).first;
  final saludo = 'Hola $nombre, le saluda $negocio.';
  final dia = cobroDelDia(estado, hoy);

  if (dia.atrasado > 0) {
    final total = dia.atrasado + dia.venceHoy;
    final mora = estado.moraPendiente > 0
        ? ' (incluye ${_rd(estado.moraPendiente)} de mora)'
        : '';
    final dias = dia.diasAtraso == 0
        ? '' // ya pagó las cuotas, solo debe la mora
        : ', con ${dia.diasAtraso} día${dia.diasAtraso == 1 ? '' : 's'} de atraso';
    return '$saludo Tiene ${_rd(total)} pendiente$mora$dias. '
        'Por favor póngase al día para que no siga subiendo la mora. ¡Gracias!';
  }
  if (dia.venceHoy > 0) {
    return '$saludo Le recordamos que hoy vence su cuota de ${_rd(dia.venceHoy)}. ¡Gracias!';
  }
  for (final c in estado.cuotas) {
    if (c.porCobrar > 0) {
      final f = c.fecha;
      return '$saludo Le recordamos que su próxima cuota de ${_rd(c.porCobrar)} '
          'vence el ${f.day} ${_meses[f.month - 1]}. ¡Gracias!';
    }
  }
  // Sin cuotas pendientes en el cronograma, pero debe (préstamos viejos sin
  // cronograma): se le recuerda el balance, nunca se le dice que saldó.
  if (estado.balance >= 0.01) {
    return '$saludo Le recordamos que tiene un balance pendiente de ${_rd(estado.balance)}. ¡Gracias!';
  }
  return '$saludo Su préstamo está saldado. ¡Gracias por cumplir! '
      'Si más adelante necesita otro préstamo, aquí estamos para servirle.';
}

/// "Hola José" (o solo "Hola" si no hay nombre).
String _hola(String nombreCliente) {
  final nombre = nombreCliente.trim().split(RegExp(r'\s+')).first;
  return nombre.isEmpty ? 'Hola' : 'Hola $nombre';
}

/// Mensaje para avisarle al cliente que su solicitud fue aprobada. Si se
/// sabe el monto, lo menciona.
String mensajeSolicitudAprobada({
  required String nombreCliente,
  required String negocio,
  num? monto,
}) {
  final cuanto = monto != null && monto > 0 ? ' de ${_rd(monto.toDouble())}' : '';
  return '${_hola(nombreCliente)}, le saluda $negocio. ¡Buenas noticias! Su solicitud de '
      'préstamo$cuanto fue aprobada. Le escribo para ponernos de acuerdo con la entrega '
      'del dinero.';
}

/// Mensaje amable para avisarle al cliente que esta vez no se le pudo
/// aprobar la solicitud.
String mensajeSolicitudRechazada({required String nombreCliente, required String negocio}) =>
    '${_hola(nombreCliente)}, le saluda $negocio. Gracias por enviarnos su solicitud. '
    'Por ahora no podemos aprobarle el préstamo, pero más adelante puede volver a '
    'intentarlo. ¡Que tenga un buen día!';

/// Para el cliente que pagó todo: se le agradece y se le invita a pedir
/// otro préstamo con el link de solicitudes del prestamista ([link]).
String mensajeVolverAPrestar({required String nombreCliente, required String link}) =>
    '${_hola(nombreCliente)}, usted cumplió con su préstamo. Si necesita otro, aquí estoy.'
    '${link.trim().isEmpty ? '' : ' Puede pedirlo aquí: ${link.trim()}'}';

const _diasSemana = ['lunes', 'martes', 'miércoles', 'jueves', 'viernes', 'sábado', 'domingo'];

/// Recordatorio para el que paga mañana: el monto y la fecha.
String mensajeRecordatorioManana({
  required String nombreCliente,
  required String negocio,
  required double monto,
  required DateTime fecha,
}) =>
    '${_hola(nombreCliente)}, le saluda $negocio. Le recordamos que mañana, '
    '${_diasSemana[fecha.weekday - 1]} ${fecha.day} ${_meses[fecha.month - 1]}, '
    'le toca su cuota de ${_rd(monto)}. ¡Gracias!';

const _mesesLargos = [
  'enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio', 'julio', 'agosto', //
  'septiembre', 'octubre', 'noviembre', 'diciembre',
];

/// Resumen corto del mes para compartir por WhatsApp (con un socio, el
/// contador o uno mismo).
String mensajeResumenMes({
  required String negocio,
  required DateTime mes,
  required double prestado,
  required double cobrado,
  required double ganancia,
  required double moraCobrada,
  required double enLaCalle,
  required int atrasados,
}) {
  final titulo = negocio.trim().isEmpty ? 'Resumen' : 'Resumen de ${negocio.trim()}';
  return [
    '$titulo · ${_mesesLargos[mes.month - 1]} ${mes.year}',
    'Prestado: ${_rd(prestado)}',
    'Cobrado: ${_rd(cobrado)}',
    'Ganancia: ${_rd(ganancia)}',
    'Mora cobrada: ${_rd(moraCobrada)}',
    'En la calle: ${_rd(enLaCalle)}',
    'Atrasados: $atrasados ${atrasados == 1 ? 'cliente' : 'clientes'}',
  ].join('\n');
}
