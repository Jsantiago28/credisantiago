import 'package:flutter/material.dart';

import '../logic/cobradores.dart';
import '../services/errores.dart';
import '../services/supabase_service.dart';
import '../theme/app_theme.dart';
import 'ui.dart';

/// En la ficha del cliente: quién le cobra ("Lo cobro yo" o un cobrador).
/// No sale si el prestamista no tiene cobradores.
class SelectorCobrador extends StatefulWidget {
  final Map<String, dynamic> cliente;

  /// Para pruebas: los cobradores ya cargados (si es null, los busca).
  final List<Cobrador>? cobradores;

  const SelectorCobrador({super.key, required this.cliente, this.cobradores});

  @override
  State<SelectorCobrador> createState() => _SelectorCobradorState();
}

class _SelectorCobradorState extends State<SelectorCobrador> {
  late List<Cobrador>? _cobradores = widget.cobradores;
  late String? _actual = widget.cliente['cobrador_id'] as String?;
  bool _guardando = false;

  @override
  void initState() {
    super.initState();
    if (_cobradores == null) _cargar();
  }

  Future<void> _cargar() async {
    var cobradores = const <Cobrador>[];
    try {
      cobradores = await SupabaseService.instance
          .listarCobradores(widget.cliente['prestamista_id'] as String);
    } catch (e, pila) {
      registrarError(e, pila, 'COBRADORES');
    }
    if (mounted) setState(() => _cobradores = cobradores);
  }

  Future<void> _cambiar(String? cobradorId) async {
    if (cobradorId == _actual) return;
    final mensajero = ScaffoldMessenger.of(context);
    final antes = _actual;
    setState(() {
      _actual = cobradorId;
      _guardando = true;
    });
    try {
      await SupabaseService.instance.asignarCobrador([widget.cliente['id'] as String], cobradorId);
      widget.cliente['cobrador_id'] = cobradorId;
    } catch (e) {
      if (mounted) setState(() => _actual = antes);
      mensajero.showSnackBar(SnackBar(content: Text('No se pudo cambiar. ${mensajeError(e)}')));
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cobradores = _cobradores;
    // Los activos, y el actual aunque ya no esté activo (para que se vea).
    final opciones = (cobradores ?? const <Cobrador>[])
        .where((c) => c.activo || c.id == _actual)
        .toList();
    if (opciones.isEmpty) return const SizedBox.shrink();
    return Panel(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        children: [
          Icon(Icons.delivery_dining_rounded, color: AppColors.green),
          const SizedBox(width: 12),
          Text('Le cobra:', style: TextStyle(color: AppColors.grey)),
          const SizedBox(width: 8),
          Expanded(
            child: DropdownButton<String?>(
              value: _actual,
              isExpanded: true,
              underline: const SizedBox.shrink(),
              dropdownColor: AppColors.surfaceAlt,
              onChanged: _guardando ? null : _cambiar,
              items: [
                const DropdownMenuItem(value: null, child: Text('Lo cobro yo')),
                for (final c in opciones)
                  DropdownMenuItem(
                    value: c.id,
                    child: Text(c.activo ? c.nombre : '${c.nombre} (sin acceso)',
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
