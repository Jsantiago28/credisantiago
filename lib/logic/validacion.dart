/// Reglas para que los datos queden bien puestos (cédula, teléfono, nombre)
/// y para detectar clientes digitados dos veces.

String soloDigitos(String? texto) => (texto ?? '').replaceAll(RegExp(r'\D'), '');

/// Minúsculas, sin acentos y sin espacios de más (para comparar nombres).
String normalizarTexto(String texto) {
  const acentos = {'á': 'a', 'é': 'e', 'í': 'i', 'ó': 'o', 'ú': 'u', 'ü': 'u', 'ñ': 'n'};
  var s = texto.toLowerCase().trim();
  acentos.forEach((k, v) => s = s.replaceAll(k, v));
  return s.replaceAll(RegExp(r'\s+'), ' ');
}

// ---------------------------------------------------------------------------
// CÉDULA (11 dígitos: 001-1234567-8)
// ---------------------------------------------------------------------------

/// 00112345678 → 001-1234567-8 (con lo que haya, mientras se escribe).
String formatearCedula(String texto) {
  final d = soloDigitos(texto);
  final recortado = d.length > 11 ? d.substring(0, 11) : d;
  if (recortado.length <= 3) return recortado;
  if (recortado.length <= 10) return '${recortado.substring(0, 3)}-${recortado.substring(3)}';
  return '${recortado.substring(0, 3)}-${recortado.substring(3, 10)}-${recortado.substring(10)}';
}

/// El último dígito de la cédula es de verificación (Luhn): con los otros
/// 10 se calcula cuál debe ser. Sirve para atrapar un número mal digitado.
/// Ojo: hay cédulas viejas reales que no cumplen esta regla, por eso en la
/// app es solo un aviso, no un bloqueo.
bool cedulaDigitoVerificadorOk(String cedula) {
  final d = soloDigitos(cedula);
  if (d.length != 11) return false;
  var suma = 0;
  for (var i = 0; i < 10; i++) {
    var n = int.parse(d[i]) * (i.isEven ? 1 : 2);
    if (n > 9) n -= 9;
    suma += n;
  }
  return (10 - suma % 10) % 10 == int.parse(d[10]);
}

/// Error de la cédula (bloquea), o null si está bien.
String? errorCedula(String? texto) {
  final d = soloDigitos(texto);
  if (d.isEmpty) return 'Escribe la cédula';
  if (d.length != 11) return 'La cédula lleva 11 dígitos (tiene ${d.length})';
  return null;
}

/// Aviso de la cédula (no bloquea): el dígito verificador no cuadra.
String? avisoCedula(String? texto) {
  if (errorCedula(texto) != null) return null;
  return cedulaDigitoVerificadorOk(texto!)
      ? null
      : 'Revisa la cédula: puede tener un número equivocado';
}

// ---------------------------------------------------------------------------
// TELÉFONO (RD: 809 / 829 / 849 + 7 dígitos)
// ---------------------------------------------------------------------------

/// 8095551234 → 809-555-1234 (mientras se escribe).
String formatearTelefono(String texto) {
  var d = soloDigitos(texto);
  if (d.length == 11 && d.startsWith('1')) d = d.substring(1); // +1 809...
  if (d.length > 10) d = d.substring(0, 10);
  if (d.length <= 3) return d;
  if (d.length <= 6) return '${d.substring(0, 3)}-${d.substring(3)}';
  return '${d.substring(0, 3)}-${d.substring(3, 6)}-${d.substring(6)}';
}

/// Error del teléfono, o null si está bien. `obligatorio: false` acepta
/// vacío (ej. teléfono de una referencia opcional).
String? errorTelefono(String? texto, {bool obligatorio = true}) {
  var d = soloDigitos(texto);
  if (d.isEmpty) return obligatorio ? 'Escribe el teléfono' : null;
  if (d.length == 11 && d.startsWith('1')) d = d.substring(1);
  if (d.length != 10) return 'El teléfono lleva 10 dígitos (ej. 809-555-1234)';
  if (!RegExp(r'^8[024]9').hasMatch(d)) return 'Debe empezar con 809, 829 u 849';
  return null;
}

// ---------------------------------------------------------------------------
// NOMBRE Y MONTOS
// ---------------------------------------------------------------------------

/// Error del nombre completo, o null si está bien.
String? errorNombre(String? texto) {
  final t = (texto ?? '').trim();
  if (t.isEmpty) return 'Escribe el nombre completo';
  if (RegExp(r'\d').hasMatch(t)) return 'El nombre no lleva números';
  if (t.split(RegExp(r'\s+')).length < 2) return 'Escribe nombre y apellido';
  return null;
}

/// Error de un monto en pesos (solo números, mayor que 0), o null.
String? errorMonto(String? texto, {bool obligatorio = false}) {
  final t = (texto ?? '').replaceAll(',', '').trim();
  if (t.isEmpty) return obligatorio ? 'Escribe el monto' : null;
  final n = double.tryParse(t);
  if (n == null) return 'Solo números';
  if (n <= 0) return 'Debe ser mayor que 0';
  return null;
}

// ---------------------------------------------------------------------------
// REPETIDOS
// ---------------------------------------------------------------------------

/// Qué dato se repite.
enum DatoRepetido {
  cedula('cédula'),
  telefono('teléfono'),
  nombre('nombre');

  final String texto;
  const DatoRepetido(this.texto);
}

String _telefono10(String? t) {
  final d = soloDigitos(t);
  return d.length == 11 && d.startsWith('1') ? d.substring(1) : d;
}

/// Registros (clientes o solicitudes) que ya tienen la misma cédula,
/// teléfono o nombre completo. `excluirId` para no compararse consigo mismo.
List<({DatoRepetido dato, Map<String, dynamic> registro})> buscarRepetidos(
  List<Map<String, dynamic>> registros, {
  String? cedula,
  String? telefono,
  String? nombre,
  String? excluirId,
}) {
  final ced = soloDigitos(cedula);
  final tel = _telefono10(telefono);
  final nom = normalizarTexto(nombre ?? '');
  final res = <({DatoRepetido dato, Map<String, dynamic> registro})>[];
  for (final r in registros) {
    if (excluirId != null && r['id'] == excluirId) continue;
    if (ced.length == 11 && soloDigitos(r['cedula'] as String?) == ced) {
      res.add((dato: DatoRepetido.cedula, registro: r));
    }
    if (tel.length == 10 && _telefono10(r['telefono'] as String?) == tel) {
      res.add((dato: DatoRepetido.telefono, registro: r));
    }
    if (nom.contains(' ') && normalizarTexto((r['nombre'] as String?) ?? '') == nom) {
      res.add((dato: DatoRepetido.nombre, registro: r));
    }
  }
  return res;
}
