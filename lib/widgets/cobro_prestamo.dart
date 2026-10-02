import 'package:flutter/material.dart';

import '../logic/calculo_prestamo.dart';
import '../recibos/compartir_recibo.dart';
import '../recibos/imprimir_ticket.dart';
import '../recibos/recibo_pdf.dart';
import '../services/supabase_service.dart';
import '../theme/app_theme.dart';
import 'contacto.dart';
import 'gestiones.dart';
import 'ui.dart';

/// Flujo de cobro de un préstamo: cuotas → cobrar → recibo, e historial de
/// recibos. Se abre desde Inicio y desde Reportes. `onCambio` se llama
/// después de registrar un cobro, para que la pantalla recargue.
class CobroPrestamo {
  final BuildContext context;
  final PrestamoConDatos datos;
  final VoidCallback onCambio;

  CobroPrestamo(this.context, this.datos, {required this.onCambio});

  Map<String, dynamic> get _prestamo => datos.prestamo;
  String get _nombre => datos.nombre;

  static RoundedRectangleBorder get _forma => const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      );

  /// Cronograma de cuotas. Al tocar una pendiente, pide confirmar el cobro
  /// (cuota + su mora, ya puesto).
  Future<void> abrirCuotas() async {
    final estado = datos.estado(DateTime.now());
    if (estado.cuotas.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Este préstamo no tiene cronograma (falta info del plazo).')));
      return;
    }

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: _forma,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.75,
        maxChildSize: 0.92,
        expand: false,
        builder: (_, controller) => Column(
          children: [
            const SizedBox(height: 8),
            Container(
                width: 40,
                height: 4,
                decoration:
                    BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(2))),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 4),
              child: Row(
                children: [
                  AvatarIniciales(nombre: _nombre, tamano: 44),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_nombre,
                            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                        Text(
                          estado.moraPendiente > 0
                              ? 'Debe ${rd(estado.balance)} · mora ${rd(estado.moraPendiente)}'
                              : 'Debe ${rd(estado.balance)}',
                          style: TextStyle(
                              color: estado.moraPendiente > 0 ? AppColors.red : AppColors.grey,
                              fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                  if (datos.pagos.isNotEmpty)
                    TextButton.icon(
                      onPressed: () {
                        Navigator.of(ctx).pop();
                        abrirRecibos();
                      },
                      icon: const Icon(Icons.receipt_long, size: 18),
                      label: Text('Recibos (${datos.pagos.length})'),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: FilaContacto(
                telefono: datos.cliente?['telefono'] as String?,
                onWhatsApp: () => whatsAppCobro(context,
                    nombreCliente: _nombre,
                    telefono: datos.cliente?['telefono'] as String?,
                    estado: estado),
              ),
            ),
            if (datos.promesa(DateTime.now()) case final promesa?)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
                child: LineaPromesa(promesa),
              ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  TextButton.icon(
                    onPressed: () async {
                      if (await anotarGestion(ctx, datos)) {
                        onCambio();
                        if (ctx.mounted) Navigator.of(ctx).pop();
                        if (context.mounted) {
                          ScaffoldMessenger.of(context)
                              .showSnackBar(SnackBar(content: Text('Gestión a $_nombre guardada')));
                        }
                      }
                    },
                    icon: const Icon(Icons.handshake_rounded, size: 18),
                    label: const Text('Anotar gestión'),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => verGestiones(context, datos, onCambio: onCambio),
                    child: Text(datos.gestiones.isEmpty
                        ? 'Ver gestiones'
                        : 'Gestiones (${datos.gestiones.length})'),
                  ),
                ],
              ),
            ),
            const Divider(height: 12),
            Expanded(
              child: ListView.builder(
                controller: controller,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: estado.cuotas.length,
                itemBuilder: (_, i) {
                  final cuota = estado.cuotas[i];
                  final alDia = cuota.porCobrar < 0.005;
                  final detalle = [
                    rd(cuota.monto),
                    if (!cuota.pagada && cuota.pendiente < cuota.monto)
                      'faltan ${rd(cuota.pendiente)}',
                    if (cuota.moraPendiente > 0) '+ mora ${rd(cuota.moraPendiente)}',
                  ].join(' · ');

                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      alDia ? Icons.check_circle : Icons.radio_button_unchecked,
                      color: alDia
                          ? AppColors.green
                          : cuota.moraPendiente > 0
                              ? AppColors.red
                              : AppColors.grey,
                    ),
                    title: Text('Cuota #${cuota.numero} — ${fechaLarga(cuota.fecha)}',
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text(detalle,
                        style: TextStyle(
                            color: cuota.moraPendiente > 0 ? AppColors.red : AppColors.grey)),
                    trailing: alDia
                        ? const Text('Pagada',
                            style: TextStyle(color: AppColors.green, fontSize: 12))
                        : TextButton(
                            onPressed: () {
                              Navigator.of(ctx).pop();
                              _confirmarCobro(estado, cuota.porCobrar);
                            },
                            child: const Text('Cobrar'),
                          ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmarCobro(EstadoPrestamo estado, double montoSugerido) async {
    String pesos(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);
    final ctrl = TextEditingController(text: pesos(montoSugerido));

    final monto = await showModalBottomSheet<double>(
      context: context,
      isScrollControlled: true,
      shape: _forma,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 20,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Cobrar a $_nombre',
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text(
                estado.moraPendiente > 0
                    ? 'Debe ${rd(estado.balance)} (incluye ${rd(estado.moraPendiente)} de mora)'
                    : 'Balance actual: ${rd(estado.balance)}',
                style: const TextStyle(color: AppColors.grey)),
            const SizedBox(height: 16),
            TextField(
              controller: ctrl,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
              decoration: InputDecoration(
                prefixText: 'RD\$ ',
                filled: true,
                fillColor: AppColors.background,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () =>
                  Navigator.of(ctx).pop(double.tryParse(ctrl.text.replaceAll(',', ''))),
              child: const Text('Confirmar cobro'),
            ),
          ],
        ),
      ),
    );

    if (monto == null || monto <= 0 || !context.mounted) return;
    final mensajero = ScaffoldMessenger.of(context);

    try {
      // El cobro es del dueño del préstamo, aunque lo haga un cobrador.
      final pago = await SupabaseService.instance.registrarPago(
        prestamoId: _prestamo['id'],
        prestamistaId: _prestamo['prestamista_id'] as String,
        monto: monto,
      );
      onCambio();
      if (context.mounted) await _mostrarCobroRegistrado(pago);
    } catch (e) {
      // ignore: avoid_print
      print('ERROR REAL COBRAR: $e');
      mensajero.showSnackBar(SnackBar(content: Text('No se pudo registrar el cobro: $e')));
    }
  }

  /// Genera y comparte el PDF del recibo, avisando si algo falla.
  Future<void> _compartirRecibo(PagoRegistrado pago) async {
    final mensajero = ScaffoldMessenger.of(context);
    try {
      await compartirRecibo(prestamo: _prestamo, pago: pago);
    } catch (e) {
      // ignore: avoid_print
      print('ERROR REAL RECIBO: $e');
      mensajero.showSnackBar(SnackBar(content: Text('No se pudo generar el recibo: $e')));
    }
  }

  /// Después de cobrar: confirma el reparto y ofrece compartir el recibo.
  Future<void> _mostrarCobroRegistrado(PagoRegistrado pago) {
    return showModalBottomSheet(
      context: context,
      shape: _forma,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.check_circle, color: AppColors.green, size: 28),
                const SizedBox(width: 10),
                Expanded(
                  child: Text('Cobrado ${rd(pago.monto)} a $_nombre',
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text('Recibo ${numeroReciboTexto(pago.numeroRecibo)}',
                style: const TextStyle(color: AppColors.grey)),
            if (pago.montoMora > 0)
              Text('Cuota ${rd(pago.montoCuota)} + mora ${rd(pago.montoMora)}',
                  style: const TextStyle(color: AppColors.grey)),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () => _compartirRecibo(pago),
              icon: const Icon(Icons.picture_as_pdf),
              label: const Text('Compartir recibo (PDF)'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => imprimirTicket(context, prestamo: _prestamo, pago: pago),
              icon: const Icon(Icons.print_rounded),
              label: const Text('Imprimir ticket'),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Listo'),
            ),
            // El cobrador no anula: le avisa al jefe.
            if (!SupabaseService.instance.esCobrador)
              TextButton.icon(
                style: TextButton.styleFrom(foregroundColor: AppColors.red),
                onPressed: () async {
                  if (await _anular(pago) && ctx.mounted) Navigator.of(ctx).pop();
                },
                icon: const Icon(Icons.undo_rounded, size: 18),
                label: const Text('¿Te equivocaste? Anular este cobro'),
              )
            else
              const Text('¿Te equivocaste? Avísale a tu jefe para que lo anule.',
                  style: TextStyle(color: AppColors.grey, fontSize: 12)),
          ],
        ),
      ),
    );
  }

  /// Pide el motivo y anula el cobro. Devuelve true si se anuló.
  Future<bool> _anular(PagoRegistrado pago) async {
    final motivo = TextEditingController();
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setEstado) => AlertDialog(
          backgroundColor: AppColors.surface,
          title: Text('Anular recibo ${numeroReciboTexto(pago.numeroRecibo)}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'El cobro de ${rd(pago.monto)} del ${fechaLarga(pago.fecha)} deja de contar: '
                'vuelve a subir lo que debe $_nombre. No se borra: queda anulado con el motivo.',
                style: const TextStyle(color: AppColors.grey),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: motivo,
                autofocus: true,
                onChanged: (_) => setEstado(() {}),
                decoration: const InputDecoration(
                  labelText: 'Motivo',
                  hintText: 'Ej. puse 4000 en vez de 400',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancelar')),
            TextButton(
              onPressed: motivo.text.trim().length < 3 ? null : () => Navigator.of(ctx).pop(true),
              child: const Text('Anular cobro', style: TextStyle(color: AppColors.red)),
            ),
          ],
        ),
      ),
    );
    if (confirmado != true || !context.mounted) return false;

    final mensajero = ScaffoldMessenger.of(context);
    try {
      await SupabaseService.instance
          .anularPago(prestamo: _prestamo, pago: pago, motivo: motivo.text);
      onCambio();
      mensajero.showSnackBar(SnackBar(
          content: Text('Recibo ${numeroReciboTexto(pago.numeroRecibo)} anulado. '
              'El balance de $_nombre se recalculó.')));
      return true;
    } catch (e) {
      // ignore: avoid_print
      print('ERROR REAL ANULAR: $e');
      mensajero.showSnackBar(SnackBar(content: Text('No se pudo anular: $e')));
      return false;
    }
  }

  /// Historial de pagos del préstamo, para reenviar cualquier recibo.
  Future<void> abrirRecibos() {
    final pagos = [...datos.pagos]..sort((a, b) => b.fecha.compareTo(a.fecha));
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: _forma,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        expand: false,
        builder: (_, controller) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(20),
              child: Text('Recibos de $_nombre',
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            ),
            Expanded(
              child: ListView.builder(
                controller: controller,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: pagos.length,
                itemBuilder: (_, i) {
                  final pago = pagos[i];
                  if (pago.anulado) {
                    // Queda a la vista, tachado, para que haya rastro.
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.block_rounded, color: AppColors.red),
                      title: Text('${numeroReciboTexto(pago.numeroRecibo)} — ${rd(pago.monto)}',
                          style: const TextStyle(
                              color: AppColors.grey, decoration: TextDecoration.lineThrough)),
                      subtitle: Text(
                        'ANULADO'
                        '${pago.anuladoEn != null ? ' el ${fechaLarga(pago.anuladoEn!)}' : ''}'
                        '${pago.motivoAnulacion != null ? ' · ${pago.motivoAnulacion}' : ''}',
                        style: const TextStyle(color: AppColors.red, fontSize: 12),
                      ),
                    );
                  }
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.receipt_long, color: AppColors.grey),
                    title: Text('${numeroReciboTexto(pago.numeroRecibo)} — ${rd(pago.monto)}',
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text(fechaLarga(pago.fecha) +
                        (pago.montoMora > 0 ? ' · incluye mora ${rd(pago.montoMora)}' : '')),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: 'Compartir PDF',
                          icon: const Icon(Icons.picture_as_pdf, color: AppColors.green),
                          onPressed: () => _compartirRecibo(pago),
                        ),
                        IconButton(
                          tooltip: 'Imprimir ticket',
                          icon: const Icon(Icons.print_rounded, color: AppColors.grey),
                          onPressed: () =>
                              imprimirTicket(context, prestamo: _prestamo, pago: pago),
                        ),
                        if (!SupabaseService.instance.esCobrador)
                          PopupMenuButton<String>(
                            tooltip: 'Más opciones',
                            color: AppColors.surfaceAlt,
                            icon: const Icon(Icons.more_vert, color: AppColors.grey),
                            onSelected: (_) async {
                              if (await _anular(pago) && ctx.mounted) Navigator.of(ctx).pop();
                            },
                            itemBuilder: (_) => const [
                              PopupMenuItem(
                                value: 'anular',
                                child: Row(
                                  children: [
                                    Icon(Icons.undo_rounded, color: AppColors.red, size: 18),
                                    SizedBox(width: 8),
                                    Text('Anular este cobro'),
                                  ],
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
