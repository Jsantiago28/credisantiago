import 'package:flutter/material.dart';

import '../logic/whatsapp.dart';
import '../theme/app_theme.dart';
import '../widgets/contacto.dart';
import '../widgets/ui.dart';

/// Un cliente que paga mañana, para recordarle.
typedef RecordatorioManana = ({String nombre, String? telefono, double monto, DateTime fecha});

/// Recordar a los de mañana, uno por uno: sale el nombre y el monto, se toca
/// "Abrir WhatsApp" (el mensaje va escrito) y luego "Siguiente". Nada se
/// manda solo: cada mensaje lo envía uno mismo en WhatsApp.
class RecordarMananaScreen extends StatefulWidget {
  final List<RecordatorioManana> clientes;

  /// Nombre del negocio que firma el mensaje.
  final String negocio;

  /// Para las pruebas: qué hacer al tocar "Abrir WhatsApp". Si no se da,
  /// abre WhatsApp de verdad.
  final void Function(String? telefono, String mensaje)? alAbrir;

  const RecordarMananaScreen({
    super.key,
    required this.clientes,
    required this.negocio,
    this.alAbrir,
  });

  @override
  State<RecordarMananaScreen> createState() => _RecordarMananaScreenState();
}

class _RecordarMananaScreenState extends State<RecordarMananaScreen> {
  var _i = 0;

  /// Los que ya se abrieron en WhatsApp.
  final _abiertos = <int>{};

  String _mensaje(RecordatorioManana c) => mensajeRecordatorioManana(
      nombreCliente: c.nombre, negocio: widget.negocio, monto: c.monto, fecha: c.fecha);

  Future<void> _abrir(RecordatorioManana c) async {
    setState(() => _abiertos.add(_i));
    final alAbrir = widget.alAbrir;
    if (alAbrir != null) return alAbrir(c.telefono, _mensaje(c));
    await abrirWhatsApp(context, c.telefono, _mensaje(c));
  }

  @override
  Widget build(BuildContext context) {
    final total = widget.clientes.length;
    final termino = _i >= total;
    return Scaffold(
      appBar: AppBar(title: const Text('Recordar a los de mañana')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: termino ? _listo() : _uno(widget.clientes[_i], total),
      ),
    );
  }

  Widget _listo() => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Vacio(
            icono: Icons.celebration_rounded,
            texto: '¡Listo! Abriste WhatsApp para '
                '${plural(_abiertos.length, 'cliente', 'clientes')} '
                'de ${widget.clientes.length}.',
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Terminar'),
          ),
        ],
      );

  Widget _uno(RecordatorioManana c, int total) {
    final tieneTelefono = telefonoWhatsApp(c.telefono) != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('${_i + 1} de $total',
            style: TextStyle(color: AppColors.grey, fontWeight: FontWeight.w700, fontSize: 14)),
        const SizedBox(height: 8),
        LinearProgressIndicator(
          value: (_i + 1) / total,
          minHeight: 6,
          color: AppColors.green,
          backgroundColor: AppColors.surfaceAlt,
        ),
        const SizedBox(height: 16),
        Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  AvatarIniciales(nombre: c.nombre),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(c.nombre,
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text('Paga mañana ${fechaLarga(c.fecha)}',
                  style: TextStyle(color: AppColors.grey, fontSize: 14)),
              Text(rd(c.monto),
                  style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800)),
              const SizedBox(height: 12),
              Text(_mensaje(c), style: TextStyle(color: AppColors.grey, fontSize: 13)),
            ],
          ),
        ),
        const SizedBox(height: 8),
        if (tieneTelefono)
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
                backgroundColor: verdeWhatsApp, foregroundColor: Colors.black),
            onPressed: () => _abrir(c),
            icon: const Icon(Icons.chat_rounded),
            label: Text(_abiertos.contains(_i) ? 'Abrir WhatsApp otra vez' : 'Abrir WhatsApp'),
          )
        else
          Text('Este cliente no tiene un teléfono válido para WhatsApp.',
              textAlign: TextAlign.center, style: TextStyle(color: AppColors.red, fontSize: 14)),
        const SizedBox(height: 10),
        OutlinedButton(
          onPressed: () => setState(() => _i++),
          child: Text(_i + 1 < total ? 'Siguiente' : 'Terminar'),
        ),
      ],
    );
  }
}
