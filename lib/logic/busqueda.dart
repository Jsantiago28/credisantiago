/// Búsqueda de clientes mientras se escribe: por nombre (sin importar
/// mayúsculas ni acentos), cédula o teléfono.
library;

import 'validacion.dart';

String _normalizar(String texto) => normalizarTexto(texto);

String _digitos(String? texto) => soloDigitos(texto);

/// Clientes que coinciden con lo escrito, los mejores primero:
///  - nombre: cada palabra escrita debe estar al inicio de alguna palabra
///    del nombre ("jo pe" encuentra "José Pérez");
///  - cédula o teléfono: si se escriben 3 dígitos o más.
List<Map<String, dynamic>> buscarClientes(
  List<Map<String, dynamic>> clientes,
  String texto, {
  int maximo = 6,
}) {
  final consulta = _normalizar(texto);
  if (consulta.isEmpty) return const [];
  final palabras = consulta.split(' ');
  final digitos = _digitos(texto);

  final resultado = <(int, String, Map<String, dynamic>)>[];
  for (final c in clientes) {
    final nombre = _normalizar((c['nombre'] as String?) ?? '');
    final partes = nombre.split(' ');
    final porNombre = palabras.every((p) => partes.any((w) => w.startsWith(p)));
    final porNumero = digitos.length >= 3 &&
        (_digitos(c['cedula'] as String?).contains(digitos) ||
            _digitos(c['telefono'] as String?).contains(digitos));
    if (!porNombre && !porNumero) continue;
    // Puntaje: el nombre empieza igual > coincide por palabras > por número.
    final puntaje = nombre.startsWith(consulta) ? 0 : (porNombre ? 1 : 2);
    resultado.add((puntaje, nombre, c));
  }
  // Empate: alfabético sin acentos ("José" antes que "Josefina").
  resultado.sort((a, b) {
    final porPuntaje = a.$1.compareTo(b.$1);
    return porPuntaje != 0 ? porPuntaje : a.$2.compareTo(b.$2);
  });
  return resultado.take(maximo).map((r) => r.$3).toList();
}
