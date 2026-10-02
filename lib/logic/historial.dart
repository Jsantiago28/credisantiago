import 'dart:convert';

import 'package:intl/intl.dart';

/// Nombre de cada dato del cliente, como se ve en la ficha.
const nombresCampos = {
  'nombre': 'Nombre',
  'cedula': 'Cédula',
  'telefono': 'Teléfono',
  'direccion': 'Dirección',
  'ubicacion': 'Ubicación',
  'foto_cara_url': 'Foto de la cara',
  'foto_cedula_frente_url': 'Foto cédula (frente)',
  'foto_cedula_reverso_url': 'Foto cédula (atrás)',
  'trabajo_lugar': 'Dónde trabaja',
  'trabajo_direccion': 'Dirección del trabajo',
  'jefe_nombre': 'Supervisor / RR.HH.',
  'jefe_telefono': 'Tel. supervisor',
  'ingreso_mensual': 'Gana al mes',
  'tipo_vivienda': 'Vivienda',
  'evidencias_ingresos': 'Evidencias de ingresos',
  'ref1_nombre': 'Referencia 1',
  'ref1_parentesco': 'Parentesco ref. 1',
  'ref1_telefono': 'Tel. referencia 1',
  'ref2_nombre': 'Referencia 2',
  'ref2_parentesco': 'Parentesco ref. 2',
  'ref2_telefono': 'Tel. referencia 2',
  'metodo_cobro': 'Cómo quiere el dinero',
  'banco': 'Banco',
  'numero_cuenta': 'Número de cuenta',
  'billetera': 'Billetera',
};

/// Un dato del cliente que cambió.
class CambioCliente {
  final String campo;
  final String? antes;
  final String? despues;
  final DateTime fecha;

  const CambioCliente({
    required this.campo,
    required this.antes,
    required this.despues,
    required this.fecha,
  });

  factory CambioCliente.desdeFila(Map<String, dynamic> fila) => CambioCliente(
        campo: fila['campo'] as String,
        antes: fila['antes'] as String?,
        despues: fila['despues'] as String?,
        fecha: DateTime.parse(fila['created_at'] as String).toLocal(),
      );

  String get nombre => nombresCampos[campo] ?? campo;
  bool get esFoto => campo.startsWith('foto_');

  String get antesTexto => valorLegible(campo, antes);
  String get despuesTexto => valorLegible(campo, despues);
}

String _pesos(num v) => 'RD\$${NumberFormat('#,##0.##', 'en_US').format(v)}';

/// El valor como lo entiende una persona: montos en pesos, la vivienda con
/// su nombre, cuántas fotos de evidencia, "(vacío)" si no había nada.
String valorLegible(String campo, String? valor) {
  if (valor == null || valor.trim().isEmpty) return '(vacío)';
  switch (campo) {
    case 'ingreso_mensual':
      final n = num.tryParse(valor);
      return n == null ? valor : _pesos(n);
    case 'tipo_vivienda':
      return switch (valor) { 'propia' => 'Casa propia', 'alquilada' => 'Alquilada', _ => valor };
    case 'evidencias_ingresos':
      try {
        final n = (jsonDecode(valor) as List).length;
        return n == 0 ? '(vacío)' : '$n foto${n == 1 ? '' : 's'}';
      } catch (_) {
        return valor;
      }
    case 'ubicacion':
      return valor;
  }
  if (campo.startsWith('foto_')) return 'Foto';
  return valor;
}

/// Todo lo que se cambió en un mismo "Guardar".
class EdicionCliente {
  final DateTime fecha;
  final List<CambioCliente> cambios;
  const EdicionCliente(this.fecha, this.cambios);
}

/// Agrupa los cambios por el momento en que se guardaron (la más reciente
/// primero). La latitud y la longitud se muestran juntas como "Ubicación".
/// Repartir la ruta (cobrador_id) no es un dato del cliente: no sale.
List<EdicionCliente> agruparCambios(List<CambioCliente> cambios) {
  final porMomento = <DateTime, List<CambioCliente>>{};
  for (final c in cambios.where((c) => c.campo != 'cobrador_id')) {
    porMomento.putIfAbsent(c.fecha, () => []).add(c);
  }
  final ediciones = porMomento.entries.map((e) {
    final lista = e.value.where((c) => c.campo != 'lat' && c.campo != 'lng').toList();
    final coordenadas = e.value.where((c) => c.campo == 'lat' || c.campo == 'lng').toList();
    if (coordenadas.isNotEmpty) {
      final antes = coordenadas.every((c) => c.antes == null) ? null : 'Ubicación anterior';
      lista.add(CambioCliente(
        campo: 'ubicacion',
        antes: antes,
        despues: antes == null ? 'Marcada' : 'Corregida',
        fecha: e.key,
      ));
    }
    // En el orden en que aparecen en la ficha.
    final orden = nombresCampos.keys.toList();
    int posicion(CambioCliente c) {
      final i = orden.indexOf(c.campo);
      return i < 0 ? orden.length : i;
    }

    lista.sort((a, b) => posicion(a).compareTo(posicion(b)));
    return EdicionCliente(e.key, lista);
  }).toList()
    ..sort((a, b) => b.fecha.compareTo(a.fecha));
  return ediciones;
}
