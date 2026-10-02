// Cobradores: el prestamista los invita por correo y les reparte clientes.
// Las reglas de quién ve qué están en la base de datos
// (supabase/migracion_2026_09_30_cobradores.sql).

import 'planes.dart';

class Cobrador {
  final String id;
  final String nombre;
  final String email;
  final String? telefono;

  /// Usuario de la app: se llena la primera vez que el cobrador entra.
  final String? userId;
  final bool activo;

  const Cobrador({
    required this.id,
    required this.nombre,
    required this.email,
    this.telefono,
    this.userId,
    this.activo = true,
  });

  factory Cobrador.desdeFila(Map<String, dynamic> fila) => Cobrador(
        id: fila['id'] as String,
        nombre: (fila['nombre'] as String?) ?? '',
        email: (fila['email'] as String?) ?? '',
        telefono: fila['telefono'] as String?,
        userId: fila['user_id'] as String?,
        activo: fila['activo'] != false,
      );

  /// Ya entró alguna vez a la app con su correo.
  bool get yaEntro => userId != null;

  String get estado => !activo
      ? 'Desactivado'
      : yaEntro
          ? 'Activo'
          : 'Esperando que entre';
}

/// Quien usa la app es un cobrador: sus datos y los de su jefe (lo que
/// devuelve la función mi_jefe() de la base de datos).
class SesionCobrador {
  final String cobradorId;
  final String cobradorNombre;
  final String prestamistaId;

  /// El perfil del jefe con lo que hace falta para el recibo y los
  /// mensajes: nombre, negocio, whatsapp, phone y recibo_*.
  final Map<String, dynamic> jefe;

  const SesionCobrador({
    required this.cobradorId,
    required this.cobradorNombre,
    required this.prestamistaId,
    required this.jefe,
  });

  factory SesionCobrador.desdeFila(Map<String, dynamic> fila) => SesionCobrador(
        cobradorId: fila['cobrador_id'] as String,
        cobradorNombre: (fila['cobrador_nombre'] as String?) ?? '',
        prestamistaId: fila['prestamista_id'] as String,
        jefe: {
          'id': fila['prestamista_id'],
          for (final campo in const [
            'nombre', 'negocio', 'whatsapp', 'phone',
            'recibo_logo', 'recibo_telefono', 'recibo_direccion', 'recibo_mensaje',
          ])
            campo: fila[campo],
        },
      );

  /// El nombre del negocio del jefe (o el suyo si no puso negocio).
  String get negocio {
    final n = (jefe['negocio'] as String?)?.trim() ?? '';
    return n.isNotEmpty ? n : ((jefe['nombre'] as String?) ?? 'tu prestamista');
  }
}

/// Correo con forma de correo (algo@algo.algo).
String? errorCorreo(String? texto) {
  final t = (texto ?? '').trim();
  if (t.isEmpty) return 'Escribe el correo del cobrador';
  if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(t)) return 'Ese correo no está bien escrito';
  return null;
}

/// Cuántos cobradores activos permite el plan de hoy (null = sin límite).
/// Plan vencido = Gratis; cuenta sin aprobar = 0. Igual que la base de datos.
int? limiteCobradores({
  required Map<String, dynamic> perfil,
  required List<Map<String, dynamic>> planes,
  required DateTime hoy,
}) {
  if (perfil['aprobado'] == false) return 0;
  final efectivo = planEfectivo(perfil, hoy);
  final plan = planes.firstWhere((p) => p['id'] == efectivo,
      orElse: () => {'max_cobradores': efectivo == 'premium' ? null : 0});
  if (!plan.containsKey('max_cobradores')) return 0; // falta la migración
  return (plan['max_cobradores'] as num?)?.toInt();
}

/// Mensaje para mandarle al cobrador por WhatsApp: dónde entrar y con qué
/// correo.
String mensajeInvitacionCobrador({
  required String nombre,
  required String email,
  required String negocio,
  required String link,
}) =>
    'Hola ${nombre.split(' ').first}, te agregué como cobrador de $negocio.\n\n'
    '1. Abre este link: $link\n'
    '2. Entra con tu correo: $email\n'
    '3. Te llega un código al correo; escríbelo en la app.\n\n'
    'Ahí vas a ver tu ruta de cobro del día.';
