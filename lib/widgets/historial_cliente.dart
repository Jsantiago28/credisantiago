import 'package:flutter/material.dart';

import '../logic/historial.dart';
import '../theme/app_theme.dart';
import 'foto_privada.dart';
import 'gestiones.dart' show fechaHora;
import 'ui.dart';

/// Historial de cambios del cliente: cada "Guardar" con lo que decía antes
/// y lo que dice ahora. Las fotos se ven lado a lado (la vieja y la nueva).
Future<void> verHistorialCliente(
    BuildContext context, String nombre, List<CambioCliente> cambios) {
  final ediciones = agruparCambios(cambios);
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (ctx) => DraggableScrollableSheet(
      initialChildSize: 0.75,
      maxChildSize: 0.92,
      expand: false,
      builder: (_, controller) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
            child: Text('Cambios de $nombre',
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          ),
          Expanded(
            child: ediciones.isEmpty
                ? const Vacio(
                    icono: Icons.history_rounded,
                    texto: 'Sin cambios registrados.\n'
                        'Cuando corrijas un dato, aquí queda lo que decía antes.')
                : ListView(
                    controller: controller,
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                    children: [for (final e in ediciones) _Edicion(e)],
                  ),
          ),
        ],
      ),
    ),
  );
}

class _Edicion extends StatelessWidget {
  final EdicionCliente edicion;
  const _Edicion(this.edicion);

  @override
  Widget build(BuildContext context) {
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.history_rounded, size: 18, color: AppColors.green),
              const SizedBox(width: 8),
              Text(fechaHora(edicion.fecha),
                  style: const TextStyle(fontWeight: FontWeight.w700)),
            ],
          ),
          for (final c in edicion.cambios) ...[
            const SizedBox(height: 10),
            Text(c.nombre, style: TextStyle(color: AppColors.grey, fontSize: 12)),
            const SizedBox(height: 4),
            c.esFoto ? _fotos(c) : _textos(c),
          ],
        ],
      ),
    );
  }

  Widget _textos(CambioCliente c) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(c.antesTexto,
              style: TextStyle(
                  color: AppColors.red, decoration: TextDecoration.lineThrough)),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.arrow_forward_rounded, size: 16, color: AppColors.green),
              const SizedBox(width: 4),
              Expanded(
                child: Text(c.despuesTexto,
                    style: const TextStyle(fontWeight: FontWeight.w700)),
              ),
            ],
          ),
        ],
      );

  Widget _fotos(CambioCliente c) {
    Widget foto(String? guardado, String texto) => Builder(
          builder: (context) => GestureDetector(
            onTap: guardado == null ? null : () => verFoto(context, guardado),
            child: Column(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: FotoPrivada(
                    guardado: guardado,
                    width: 90,
                    height: 64,
                    sinFoto: Container(
                      width: 90,
                      height: 64,
                      color: AppColors.surfaceAlt,
                      child: Icon(Icons.no_photography_rounded, color: AppColors.grey),
                    ),
                  ),
                ),
                Text(texto, style: TextStyle(color: AppColors.grey, fontSize: 12)),
              ],
            ),
          ),
        );
    return Row(
      children: [
        foto(c.antes, 'Antes'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Icon(Icons.arrow_forward_rounded, color: AppColors.green),
        ),
        foto(c.despues, 'Ahora'),
      ],
    );
  }
}
