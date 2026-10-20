import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../impresion/impresora.dart' as impresora;
import '../logic/calculo_prestamo.dart';
import '../logic/ticket.dart';
import '../theme/app_theme.dart';
import 'compartir_recibo.dart';

/// "Imprimir ticket": elige el papel y cómo imprimir (Bluetooth directo o
/// la app RawBT) y manda el recibo a la impresora.
Future<void> imprimirTicket(
  BuildContext context, {
  required Map<String, dynamic> prestamo,
  required PagoRegistrado pago,
  List<PagoRegistrado>? pagosLocales,
  Map<String, dynamic>? cliente,
}) async {
  final mensajero = ScaffoldMessenger.of(context);
  final ReciboListo recibo;
  try {
    recibo = await prepararRecibo(
        prestamo: prestamo, pago: pago, pagosLocales: pagosLocales, cliente: cliente);
  } catch (e) {
    mensajero.showSnackBar(SnackBar(content: Text('No se pudo preparar el ticket: $e')));
    return;
  }
  if (!context.mounted) return;
  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surface,
    builder: (_) => HojaImprimir(
      bytes: (mm) => ticketEscPos(lineasTicket(
        r: recibo.r,
        negocio: recibo.negocio,
        cliente: recibo.cliente,
        cedula: recibo.cedula,
        cobradoPor: recibo.cobradoPor,
        papelMm: mm,
      )),
    ),
  );
}

class HojaImprimir extends StatefulWidget {
  /// El ticket en bytes ESC/POS para ese ancho de papel (58 u 80 mm).
  final List<int> Function(int papelMm) bytes;

  const HojaImprimir({super.key, required this.bytes});

  @override
  State<HojaImprimir> createState() => _HojaImprimirState();
}

class _HojaImprimirState extends State<HojaImprimir> {
  int _papel = impresora.papelImpresora();
  bool _imprimiendo = false;
  String? _error;

  String get _base64 => base64Encode(widget.bytes(_papel));

  Future<void> _bluetooth() async {
    final navegador = Navigator.of(context);
    final mensajero = ScaffoldMessenger.of(context);
    setState(() {
      _imprimiendo = true;
      _error = null;
    });
    try {
      await impresora.imprimirBluetooth(_base64);
      mensajero.showSnackBar(const SnackBar(content: Text('Ticket enviado a la impresora')));
      navegador.pop();
    } catch (e) {
      if (mounted) {
        setState(() {
          _imprimiendo = false;
          _error = '$e'.replaceFirst('Exception: ', '');
        });
      }
    }
  }

  void _rawbt() {
    try {
      impresora.imprimirRawBT(_base64);
      Navigator.of(context).pop();
    } catch (e) {
      setState(() => _error = '$e'.replaceFirst('Unsupported operation: ', ''));
    }
  }

  @override
  Widget build(BuildContext context) {
    final hayBluetooth = impresora.bluetoothDisponible();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Imprimir ticket',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            const SizedBox(height: 12),
            Text('Papel de la impresora', style: TextStyle(color: AppColors.grey)),
            const SizedBox(height: 6),
            SegmentedButton<int>(
              segments: const [
                ButtonSegment(value: 58, label: Text('58 mm (chica)')),
                ButtonSegment(value: 80, label: Text('80 mm (grande)')),
              ],
              selected: {_papel},
              onSelectionChanged: (s) {
                setState(() => _papel = s.first);
                impresora.guardarPapelImpresora(s.first);
              },
            ),
            const SizedBox(height: 16),
            // El Bluetooth directo es solo de la versión web (Chrome); en la
            // app de Android se imprime con RawBT.
            if (kIsWeb) ...[
              ElevatedButton.icon(
                onPressed: _imprimiendo || !hayBluetooth ? null : _bluetooth,
                icon: _imprimiendo
                    ? const SizedBox(
                        width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.bluetooth),
                label: const Text('Bluetooth directo'),
              ),
              Text(
                hayBluetooth
                    ? 'Para impresoras con Bluetooth BLE. La primera vez eliges la impresora de la lista.'
                    : 'Este navegador no se conecta directo. Usa Chrome en Android, o RawBT.',
                style: TextStyle(color: AppColors.grey, fontSize: 12),
              ),
              const SizedBox(height: 12),
            ],
            OutlinedButton.icon(
              onPressed: _imprimiendo ? null : _rawbt,
              icon: const Icon(Icons.print_rounded),
              label: const Text('Con la app RawBT (Android)'),
            ),
            Text(
              'Funciona con casi cualquier impresora Bluetooth. Instala RawBT una vez desde '
              'Google Play y empareja ahí tu impresora.',
              style: TextStyle(color: AppColors.grey, fontSize: 12),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: TextStyle(color: AppColors.red)),
            ],
            if (hayBluetooth) ...[
              const SizedBox(height: 8),
              TextButton(
                onPressed: _imprimiendo
                    ? null
                    : () {
                        impresora.olvidarImpresora();
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                            content: Text('La próxima vez te pregunta cuál impresora usar')));
                      },
                child: const Text('Usar otra impresora'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
