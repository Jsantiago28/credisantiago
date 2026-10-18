import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../logic/dominio.dart';
import '../screens/mi_recibo_screen.dart';
import '../screens/nuevo_cliente_screen.dart';
import '../services/supabase_service.dart';
import '../theme/app_theme.dart';
import 'ui.dart';

const _claveOcultar = 'primeros_pasos_ocultos';
const _claveCompartio = 'link_compartido';

/// Anota que el prestamista ya compartió su link de solicitudes (desde aquí
/// o desde Perfil), para marcar ese paso.
Future<void> marcarLinkCompartido() async {
  try {
    await (await SharedPreferences.getInstance()).setBool(_claveCompartio, true);
  } catch (_) {}
}

/// Mensaje con el link de solicitudes para mandar por WhatsApp.
String mensajeLinkSolicitudes(String slug) =>
    'Solicita tu préstamo aquí sin venir a mi casa, llena esto y te digo si te apruebo: '
    '$kDominioBase/s/$slug';

/// Guía de primeros pasos para el prestamista nuevo, en su Inicio: cinco
/// pasos que se marcan solos. Se esconde cuando están todos o si la oculta.
class PrimerosPasos extends StatefulWidget {
  final Map<String, dynamic> perfil;

  /// Ya tiene préstamos (en la calle o saldados).
  final bool tienePrestamos;

  /// Para el paso "primer préstamo": ir a Clientes.
  final VoidCallback? onVerClientes;

  /// Algo cambió (cliente nuevo, recibo): recargar el Inicio.
  final VoidCallback onCambio;

  const PrimerosPasos({
    super.key,
    required this.perfil,
    required this.tienePrestamos,
    required this.onCambio,
    this.onVerClientes,
  });

  @override
  State<PrimerosPasos> createState() => _PrimerosPasosState();
}

class _PrimerosPasosState extends State<PrimerosPasos> {
  bool _cargado = false;
  bool _oculto = false;
  bool _compartio = false;
  int _clientes = 0;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    try {
      final p = await SharedPreferences.getInstance();
      _oculto = p.getBool(_claveOcultar) ?? false;
      _compartio = p.getBool(_claveCompartio) ?? false;
    } catch (_) {}
    try {
      _clientes = await SupabaseService.instance.contarClientes(widget.perfil['id'] as String);
    } catch (_) {}
    if (mounted) setState(() => _cargado = true);
  }

  String _texto(String campo) => ((widget.perfil[campo] as String?) ?? '').trim();

  Future<void> _ocultar() async {
    setState(() => _oculto = true);
    try {
      await (await SharedPreferences.getInstance()).setBool(_claveOcultar, true);
    } catch (_) {}
  }

  Future<void> _abrirMiRecibo() async {
    await Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => MiReciboScreen(perfil: widget.perfil)));
    if (mounted) setState(() {});
  }

  Future<void> _compartirLink() async {
    await Share.share(mensajeLinkSolicitudes(widget.perfil['slug'] as String? ?? ''));
    await marcarLinkCompartido();
    if (mounted) setState(() => _compartio = true);
  }

  Future<void> _agregarCliente() async {
    await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => NuevoClienteScreen(prestamistaId: widget.perfil['id'] as String)));
    await _cargar();
    widget.onCambio();
  }

  @override
  Widget build(BuildContext context) {
    if (!_cargado || _oculto) return const SizedBox.shrink();
    final pasos = <(String, String, bool, VoidCallback?)>[
      ('Pon tu logo y los datos de tu recibo', 'Salen en tus recibos, tu app y tu formulario',
          _texto('recibo_logo').isNotEmpty, _abrirMiRecibo),
      ('Tu cédula y ciudad para los contratos', 'Así el contrato sale completo',
          _texto('contrato_cedula').isNotEmpty && _texto('contrato_ciudad').isNotEmpty, _abrirMiRecibo),
      ('Manda tu link de solicitudes', 'Tus clientes te piden el préstamo desde su celular',
          _compartio, _compartirLink),
      ('Agrega tu primer cliente', 'O aprueba una solicitud que te llegue', _clientes > 0,
          _agregarCliente),
      ('Haz tu primer préstamo', 'Abre un cliente y toca "Nuevo préstamo"', widget.tienePrestamos,
          widget.onVerClientes),
    ];
    final hechos = pasos.where((p) => p.$3).length;
    if (hechos == pasos.length) return const SizedBox.shrink();

    return Panel(
      margin: const EdgeInsets.only(bottom: 12),
      borde: AppColors.green.withValues(alpha: 0.5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.rocket_launch_rounded, color: AppColors.green),
              const SizedBox(width: 10),
              const Expanded(
                child: Text('Primeros pasos', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
              ),
              Text('$hechos de ${pasos.length}',
                  style: TextStyle(color: AppColors.green, fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: hechos / pasos.length,
              minHeight: 6,
              color: AppColors.green,
              backgroundColor: AppColors.greenDark,
            ),
          ),
          const SizedBox(height: 6),
          for (final (titulo, ayuda, hecho, accion) in pasos)
            InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: hecho ? null : accion,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    Icon(hecho ? Icons.check_circle_rounded : Icons.radio_button_unchecked,
                        color: hecho ? AppColors.green : AppColors.grey),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(titulo,
                              style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  decoration: hecho ? TextDecoration.lineThrough : null,
                                  color: hecho ? AppColors.grey : null)),
                          if (!hecho)
                            Text(ayuda, style: TextStyle(color: AppColors.grey, fontSize: 12)),
                        ],
                      ),
                    ),
                    if (!hecho && accion != null) Icon(Icons.chevron_right, color: AppColors.grey),
                  ],
                ),
              ),
            ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(onPressed: _ocultar, child: const Text('Ocultar')),
          ),
        ],
      ),
    );
  }
}
