import 'archivo_clientes.dart';

/// Estados de un préstamo que todavía está vivo: en la calle o sin entregar.
const _vivos = {'en_calle', 'por_cobrar', 'atrasado', 'borrador'};

/// Clientes que pagaron todo y ya no tienen préstamo: todos sus préstamos
/// están pagados (los cancelados no cuentan) y ninguno está en la calle ni
/// sin entregar. Son a los que vale la pena ofrecerles otro. Los eliminados
/// de la lista no salen. Ordenados por nombre.
///
/// [prestamos] trae al menos `cliente_id` y `estado` de cada préstamo.
List<Map<String, dynamic>> clientesParaVolverAPrestar(
  List<Map<String, dynamic>> clientes,
  List<Map<String, dynamic>> prestamos,
) {
  final pagados = <String>{};
  final conPrestamoVivo = <String>{};
  for (final p in prestamos) {
    final id = p['cliente_id'] as String?;
    if (id == null) continue;
    final estado = p['estado'] as String?;
    if (estado == 'pagado') pagados.add(id);
    if (_vivos.contains(estado)) conPrestamoVivo.add(id);
  }
  return clientes
      .where((c) =>
          !estaArchivado(c) && pagados.contains(c['id']) && !conPrestamoVivo.contains(c['id']))
      .toList()
    ..sort((a, b) => ((a['nombre'] as String?) ?? '')
        .toLowerCase()
        .compareTo(((b['nombre'] as String?) ?? '').toLowerCase()));
}
