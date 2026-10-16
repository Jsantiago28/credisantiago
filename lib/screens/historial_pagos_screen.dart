import 'package:flutter/material.dart';

import '../logic/historial_pagos.dart';
import '../recibos/historial_pdf.dart';
import '../recibos/recibo_pdf.dart' show numeroReciboTexto;
import '../theme/app_theme.dart';
import '../widgets/ui.dart';

/// Historial de pagos de un cliente: todos sus préstamos (los de ahora y
/// los ya saldados) con cada cobro, y el PDF para mandárselo si lo pide.
class HistorialPagosScreen extends StatefulWidget {
  final String cliente;
  final String? cedula;
  final List<PrestamoHistorial> prestamos;

  const HistorialPagosScreen({
    super.key,
    required this.cliente,
    this.cedula,
    required this.prestamos,
  });

  @override
  State<HistorialPagosScreen> createState() => _HistorialPagosScreenState();
}

class _HistorialPagosScreenState extends State<HistorialPagosScreen> {
  bool _compartiendo = false;

  Future<void> _compartir() async {
    final mensajero = ScaffoldMessenger.of(context);
    setState(() => _compartiendo = true);
    try {
      await compartirHistorial(
          prestamos: widget.prestamos, cliente: widget.cliente, cedula: widget.cedula);
    } catch (e) {
      mensajero.showSnackBar(SnackBar(content: Text('No se pudo hacer el PDF: $e')));
    } finally {
      if (mounted) setState(() => _compartiendo = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final prestamos = widget.prestamos;
    final totalPagado = prestamos.fold<double>(0, (s, p) => s + p.pagado);
    final pendiente = prestamos.fold<double>(0, (s, p) => s + p.balance);
    return Scaffold(
      appBar: AppBar(title: const Text('Historial de pagos')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Text(widget.cliente, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text(
            'Pagado en total: ${rd(totalPagado)}'
            '${pendiente > 0 ? ' · Falta: ${rd(pendiente)}' : ''}',
            style: TextStyle(color: AppColors.grey),
          ),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            onPressed: _compartiendo || prestamos.isEmpty ? null : _compartir,
            icon: _compartiendo
                ? const SizedBox(
                    width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.picture_as_pdf_rounded),
            label: const Text('Compartir PDF'),
          ),
          const SizedBox(height: 16),
          if (prestamos.isEmpty)
            const Vacio(
                icono: Icons.receipt_long_rounded, texto: 'Este cliente no tiene préstamos con pagos.'),
          for (final p in prestamos) _prestamo(p),
        ],
      ),
    );
  }

  Widget _prestamo(PrestamoHistorial p) {
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('${rd(p.monto)} prestado',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
              ),
              p.enLaCalle
                  ? const Pildora('EN LA CALLE')
                  : Pildora(p.estadoTexto.toUpperCase(),
                      color: AppColors.grey, fondo: AppColors.surfaceAlt),
            ],
          ),
          Text(
            [
              if (p.desde != null) 'Desde ${fechaLarga(p.desde!)}',
              'Total a pagar ${rd(p.montoTotal)}',
            ].join(' · '),
            style: TextStyle(color: AppColors.grey, fontSize: 12),
          ),
          const Divider(height: 20),
          if (p.pagos.isEmpty)
            Text('Sin pagos todavía.', style: TextStyle(color: AppColors.grey)),
          for (final pago in p.pagos)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${fechaLarga(pago.fecha)} · ${numeroReciboTexto(pago.numeroRecibo)}',
                            style: TextStyle(
                                decoration: pago.anulado ? TextDecoration.lineThrough : null,
                                color: pago.anulado ? AppColors.grey : null)),
                        if (pago.anulado)
                          Text(
                              'Anulado${(pago.motivoAnulacion ?? '').trim().isEmpty ? '' : ': ${pago.motivoAnulacion}'}',
                              style: TextStyle(color: AppColors.red, fontSize: 12))
                        else if (pago.montoMora > 0)
                          Text('Incluye mora ${rd(pago.montoMora)}',
                              style: TextStyle(color: AppColors.grey, fontSize: 12)),
                      ],
                    ),
                  ),
                  Text(rd(pago.monto),
                      style: TextStyle(
                          fontWeight: FontWeight.w800,
                          decoration: pago.anulado ? TextDecoration.lineThrough : null,
                          color: pago.anulado ? AppColors.grey : null)),
                ],
              ),
            ),
          const Divider(height: 20),
          Text('Pagado: ${rd(p.pagado)}', style: const TextStyle(fontWeight: FontWeight.w800)),
          if (p.enLaCalle)
            Text(
              'Falta: ${rd(p.balance)}${p.moraPendiente > 0 ? ' (mora ${rd(p.moraPendiente)})' : ''}',
              style: TextStyle(
                  color: p.moraPendiente > 0 ? AppColors.red : null, fontWeight: FontWeight.w700),
            ),
        ],
      ),
    );
  }
}
