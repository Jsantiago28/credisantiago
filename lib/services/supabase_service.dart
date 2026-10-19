import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../logic/archivo_clientes.dart';
import '../logic/caja.dart' as caja;
import '../logic/cobradores.dart' as cob;
import '../logic/calculo_prestamo.dart' as calc;
import '../logic/fotos.dart' as fotos;
import '../logic/gestiones.dart' as gest;
import '../logic/graficas.dart' as graficas;
import '../logic/gastos.dart' as gastos;
import '../logic/historial.dart' as historial;
import '../logic/importar.dart' as importar;
import '../logic/validacion.dart' show soloDigitos;

/// Configura estas dos constantes con los datos de tu proyecto Supabase
/// (Project Settings -> API).
class SupabaseConfig {
  static const url = 'https://twhwjttwpliudqkkgzsq.supabase.co';
  static const anonKey = 'sb_publishable_zWnZxJRX53T5SHyOd1Uamg_-pL2imoD';
}

/// Cómo terminó el registro con contraseña.
enum ResultadoRegistro {
  /// Le llegó un código al correo para confirmarlo.
  confirmarCorreo,

  /// Ese correo ya tenía cuenta: que entre (o use "¿Olvidaste tu contraseña?").
  yaExiste,

  /// Entró directo (Supabase no pide confirmar el correo).
  listo,
}

class SupabaseService {
  SupabaseService._();
  static final SupabaseService instance = SupabaseService._();

  SupabaseClient get client => Supabase.instance.client;

  /// Si quien usa la app es un cobrador: sus datos y los de su jefe. Se
  /// llena al entrar (ver [entrarComoCobrador]); null para un prestamista.
  cob.SesionCobrador? sesionCobrador;

  bool get esCobrador => sesionCobrador != null;

  /// Cobrador cuyo jefe no tiene plan para cobradores (se le venció o lo
  /// bajó): el negocio del jefe, para avisarle. Null si no es el caso.
  String? cobradorSinPlan;

  // ---------------------------------------------------------
  // AUTH - Login solo por teléfono + OTP
  // ---------------------------------------------------------

  /// Envía el código SMS al teléfono. Formato esperado: +1809XXXXXXX
  Future<void> enviarCodigo(String telefono) async {
    await client.auth.signInWithOtp(phone: telefono);
  }

  /// Verifica el código de 4-6 dígitos recibido por SMS.
  Future<AuthResponse> verificarCodigo({
    required String telefono,
    required String codigo,
  }) {
    return client.auth.verifyOTP(
      phone: telefono,
      token: codigo,
      type: OtpType.sms,
    );
  }

  User? get usuarioActual => client.auth.currentUser;

  // ---------------------------------------------------------
  // AUTH - Login por EMAIL (temporal, para probar sin Twilio)
  // ---------------------------------------------------------

  /// Envía un link mágico al correo. El link vuelve a la misma dirección
  /// desde donde se pidió (localhost o la publicada), que debe estar
  /// autorizada en Supabase (Authentication > URL Configuration).
  Future<void> enviarCodigoEmail(String email) async {
    await client.auth.signInWithOtp(
      email: email,
      emailRedirectTo: kIsWeb ? Uri.base.origin : null,
    );
  }

  // ---------------------------------------------------------
  // AUTH - correo y contraseña (14-10-2026)
  // ---------------------------------------------------------

  /// Después de entrar con código por "¿Olvidaste tu contraseña?": antes de
  /// seguir, la app pide crear una contraseña nueva.
  bool pedirNuevaClave = false;

  /// Acaba de iniciar sesión: el Inicio le da la bienvenida con su nombre.
  bool bienvenidaPendiente = false;

  Future<void> entrarConClave(String email, String clave) async {
    await client.auth.signInWithPassword(email: email, password: clave);
    bienvenidaPendiente = true;
  }

  /// Crea la cuenta con correo y contraseña. Supabase manda un código al
  /// correo para confirmarlo (plantilla "Confirm sign up").
  Future<ResultadoRegistro> registrarConClave(String email, String clave) async {
    final r = await client.auth.signUp(
      email: email,
      password: clave,
      emailRedirectTo: kIsWeb ? Uri.base.origin : null,
    );
    if (r.session != null) return ResultadoRegistro.listo; // sin confirmar correo
    // Si el correo ya tenía cuenta, Supabase no da error (para no revelar
    // quién está registrado): devuelve un usuario sin identidades y no manda nada.
    if ((r.user?.identities ?? const []).isEmpty) return ResultadoRegistro.yaExiste;
    return ResultadoRegistro.confirmarCorreo;
  }

  Future<void> reenviarCodigoRegistro(String email) async {
    await client.auth.resend(type: OtpType.signup, email: email);
  }

  /// Código para recuperar la contraseña (la olvidó, o la cuenta es de antes
  /// y nunca tuvo). Usa la plantilla "Reset password" de Supabase, distinta
  /// de la de entrar y la de registrarse. No crea cuentas nuevas; si el
  /// correo no tiene cuenta, Supabase no manda nada (y no avisa).
  Future<void> enviarCodigoOlvide(String email) async {
    await client.auth.resetPasswordForEmail(
      email,
      redirectTo: kIsWeb ? Uri.base.origin : null,
    );
  }

  /// Borra la cuenta de quien está usando la app, con todo lo suyo: primero
  /// los archivos de su carpeta (fotos, logo, contratos) y luego su usuario,
  /// que en la base de datos arrastra perfil, clientes, préstamos, cobros…
  /// (ver migracion_2026_10_18_legal_y_borrar_cuenta.sql).
  Future<void> borrarMiCuenta() async {
    final uid = usuarioActual?.id;
    if (uid == null) throw StateError('Hay que entrar para borrar la cuenta');
    final carpeta = client.storage.from(fotos.bucketFotos);
    while (true) {
      final archivos = await carpeta.list(path: uid, searchOptions: const SearchOptions(limit: 100));
      final rutas = [for (final a in archivos) if (a.id != null) '$uid/${a.name}'];
      if (rutas.isEmpty) break;
      await carpeta.remove(rutas);
    }
    await client.rpc('borrar_mi_cuenta');
    await cerrarSesion();
  }

  Future<void> cambiarClave(String clave) async {
    await client.auth.updateUser(UserAttributes(password: clave));
  }

  /// Cédula del prestamista (número y fotos de los dos lados) al registrarse.
  /// El número es el mismo que sale en sus contratos.
  Future<void> guardarCedulaPrestamista(
    String prestamistaId, {
    required String cedula,
    required String frente,
    required String reverso,
  }) async {
    await client.from('profiles').update({
      'contrato_cedula': cedula,
      'cedula_frente_url': frente,
      'cedula_reverso_url': reverso,
    }).eq('id', prestamistaId);
  }

  /// [recuperarClave]: el código vino de "¿Olvidaste tu contraseña?"
  /// (plantilla "Reset password"); si no, de entrar o de registrarse.
  Future<AuthResponse> verificarCodigoEmail({
    required String email,
    required String codigo,
    bool recuperarClave = false,
  }) async {
    final r = await client.auth.verifyOTP(
      email: email,
      token: codigo,
      type: recuperarClave ? OtpType.recovery : OtpType.email,
    );
    bienvenidaPendiente = true;
    return r;
  }

  // ---------------------------------------------------------
  // PROFILES - Prestamista + su link único /s/{slug}
  // ---------------------------------------------------------

  /// Crea el perfil del prestamista con un slug único derivado del nombre.
  /// Si el slug ya existe, le agrega un sufijo numérico.
  Future<String> crearPerfilConSlug({
    required String userId,
    required String telefono,
    required String nombre,
    String? invitadoPor,
  }) async {
    final base = _slugify(nombre);
    var slug = base;
    var intento = 1;

    while (await _slugExiste(slug)) {
      intento++;
      slug = '$base-$intento';
    }

    // Las reglas de privacidad no dejan ver los perfiles de otros, así que
    // _slugExiste no ve un link ya tomado por otro prestamista: si la base
    // de datos lo rechaza por repetido, se prueba con el siguiente número.
    for (var i = 0; i < 30; i++) {
      try {
        await client.from('profiles').upsert({
          'id': userId,
          'phone': telefono,
          'nombre': nombre,
          'slug': slug,
          // Aceptó los Términos y la Política de privacidad al registrarse.
          'acepto_terminos_en': DateTime.now().toUtc().toIso8601String(),
          if (invitadoPor != null) 'invitado_por': invitadoPor,
        });
        return slug;
      } on PostgrestException catch (e) {
        final repetido = e.code == '23505' && '${e.message} ${e.details}'.contains('slug');
        if (!repetido) rethrow;
        intento++;
        slug = '$base-$intento';
      }
    }
    throw StateError('No se encontró un link libre para "$nombre"');
  }

  Future<bool> _slugExiste(String slug) async {
    final res = await client
        .from('profiles')
        .select('id')
        .eq('slug', slug)
        .maybeSingle();
    return res != null;
  }

  String _slugify(String texto) {
    var s = texto.toLowerCase().trim();
    const acentos = {
      'á': 'a', 'é': 'e', 'í': 'i', 'ó': 'o', 'ú': 'u', 'ñ': 'n',
    };
    acentos.forEach((k, v) => s = s.replaceAll(k, v));
    s = s.replaceAll(RegExp(r'[^a-z0-9\s-]'), '');
    s = s.replaceAll(RegExp(r'\s+'), '-');
    return s.isEmpty ? 'prestamista' : s;
  }

  /// Prestamista del link de solicitudes. Lo abre un cliente sin sesión: la
  /// función solo entrega id, nombre, negocio, teléfono y si exige evidencias
  /// (ver migracion_2026_10_13_link_publico.sql).
  Future<Map<String, dynamic>?> obtenerPerfilPorSlug(String slug) async {
    final filas = await client.rpc('prestamista_del_link', params: {'p_slug': slug}) as List;
    return filas.isEmpty ? null : Map<String, dynamic>.from(filas.first as Map);
  }

  Future<Map<String, dynamic>?> obtenerMiPerfil() async {
    final uid = usuarioActual?.id;
    if (uid == null) return null;
    return client.from('profiles').select().eq('id', uid).maybeSingle();
  }
  /// El perfil del negocio: el propio, o el del jefe si quien usa la app
  /// es un cobrador. Es lo que llevan los recibos y los mensajes.
  Future<Map<String, dynamic>?> perfilDelNegocio() async =>
      sesionCobrador?.jefe ?? await obtenerMiPerfil();


  // ---------------------------------------------------------
  // STORAGE - Fotos de cédula, cara y evidencias (bucket PRIVADO)
  // ---------------------------------------------------------
  // Las fotos van en la carpeta del prestamista y solo él puede verlas (ver
  // migracion_2026_09_24_fotos_privadas.sql). En la base de datos se guarda
  // la ubicación del archivo; para mostrarla se pide un enlace temporal.

  final _azar = Random();

  /// Sube una foto a la carpeta del prestamista y devuelve su ubicación.
  Future<String> subirFoto({
    required List<int> bytes,
    required String prestamistaId,
    required String tipo, // cara, cedula_f, cedula_r, evidencia...
    bool pdf = false,
  }) async {
    final ruta = fotos.rutaNuevaFoto(
      prestamistaId: prestamistaId,
      tipo: tipo,
      ahora: DateTime.now(),
      azar: _azar.nextInt(1 << 30),
      extension: pdf ? 'pdf' : 'jpg',
    );
    await client.storage.from(fotos.bucketFotos).uploadBinary(
          ruta,
          Uint8List.fromList(bytes),
          fileOptions: FileOptions(contentType: pdf ? 'application/pdf' : 'image/jpeg'),
        );
    return ruta;
  }

  /// Sube el contrato firmado de un préstamo (fotos de las páginas y/o PDF)
  /// a la carpeta privada del prestamista y lo anota en el préstamo.
  /// Devuelve la lista completa de archivos.
  Future<List<String>> agregarContratoFirmado(
    Map<String, dynamic> prestamo,
    List<({Uint8List bytes, bool pdf})> archivos,
  ) async {
    final prestamistaId = prestamo['prestamista_id'] as String;
    final nuevos = [
      for (final a in archivos)
        await subirFoto(bytes: a.bytes, prestamistaId: prestamistaId, tipo: 'contrato', pdf: a.pdf),
    ];
    final lista = [...contratoFirmadoDe(prestamo), ...nuevos];
    await client.from('prestamos').update({'contrato_firmado': lista}).eq('id', prestamo['id']);
    prestamo['contrato_firmado'] = lista;
    return lista;
  }

  /// Quita un archivo de la lista del contrato firmado (subido por error).
  Future<List<String>> quitarDeContratoFirmado(Map<String, dynamic> prestamo, String archivo) async {
    final lista = [...contratoFirmadoDe(prestamo)]..remove(archivo);
    await client.from('prestamos').update({'contrato_firmado': lista}).eq('id', prestamo['id']);
    prestamo['contrato_firmado'] = lista;
    return lista;
  }

  /// Los archivos del contrato firmado de un préstamo (text[] de Supabase).
  static List<String> contratoFirmadoDe(Map<String, dynamic> prestamo) {
    final valor = prestamo['contrato_firmado'];
    return valor is List ? valor.whereType<String>().toList() : const [];
  }

  /// Sube las fotos de evidencia de ingresos y devuelve sus ubicaciones.
  Future<List<String>> subirEvidencias(
    List<List<int>> lista, {
    required String prestamistaId,
    required String prefijo,
  }) async {
    return [
      for (final bytes in lista)
        await subirFoto(bytes: bytes, prestamistaId: prestamistaId, tipo: '${prefijo}_evidencia'),
    ];
  }

  /// Enlaces temporales ya pedidos, para no pedirlos en cada pantalla.
  final _enlaces = <String, ({String url, DateTime vence})>{};

  /// Enlace para ver una foto (vale 1 hora; se reusa por 50 minutos). Acepta
  /// la ubicación o un enlace viejo guardado en la base de datos.
  Future<String?> enlaceFoto(String? guardado) async {
    final ruta = fotos.rutaFoto(guardado);
    if (ruta == null) return null;
    final enCache = _enlaces[ruta];
    if (enCache != null && enCache.vence.isAfter(DateTime.now())) return enCache.url;
    final url = await client.storage.from(fotos.bucketFotos).createSignedUrl(ruta, 3600);
    _enlaces[ruta] = (url: url, vence: DateTime.now().add(const Duration(minutes: 50)));
    return url;
  }

  /// Los bytes de una foto (para ponerla en un PDF). Null si no hay foto o
  /// no se pudo bajar: el recibo sale igual, sin ella.
  Future<Uint8List?> bajarFoto(String? guardado) async {
    final ruta = fotos.rutaFoto(guardado);
    if (ruta == null) return null;
    try {
      return await client.storage.from(fotos.bucketFotos).download(ruta);
    } catch (e) {
      // ignore: avoid_print
      print('ERROR REAL BAJAR FOTO: $e');
      return null;
    }
  }

  /// Lo que el prestamista pone en sus recibos (Perfil → Mi recibo).
  Future<void> guardarMiRecibo(String prestamistaId, Map<String, dynamic> cambios) async {
    await client.from('profiles').update(cambios).eq('id', prestamistaId);
  }

  /// Si el link del prestamista exige evidencia de ingresos.
  Future<void> cambiarExigirEvidencias(String prestamistaId, bool exigir) async {
    await client.from('profiles').update({'exigir_evidencias': exigir}).eq('id', prestamistaId);
  }

  // ---------------------------------------------------------
  // SOLICITUDES - Formulario público (sin login)
  // ---------------------------------------------------------

  Future<void> enviarSolicitud(Map<String, dynamic> data) async {
    await client.from('solicitudes').insert(data);
  }

  /// Stream en tiempo real de las solicitudes nuevas del prestamista logueado.
  Stream<List<Map<String, dynamic>>> solicitudesNuevasStream(String prestamistaId) {
    return client
        .from('solicitudes')
        .stream(primaryKey: ['id'])
        .eq('prestamista_id', prestamistaId)
        .order('created_at');
  }

  Future<void> aprobarSolicitud(Map<String, dynamic> solicitud) async {
    // 1. Crea el cliente con los datos de la solicitud. Va primero: si el
    //    plan no permite más clientes, falla aquí y la solicitud sigue nueva.
    final cliente = await _conLimite(() => client.from('clientes').insert({
      'prestamista_id': solicitud['prestamista_id'],
      'solicitud_id': solicitud['id'],
      'nombre': solicitud['nombre'],
      'cedula': solicitud['cedula'],
      'telefono': solicitud['telefono'],
      'direccion': solicitud['direccion'],
      'lat': solicitud['lat'],
      'lng': solicitud['lng'],
      'foto_cara_url': solicitud['foto_cara_url'],
      'foto_cedula_frente_url': solicitud['foto_cedula_frente_url'],
      'foto_cedula_reverso_url': solicitud['foto_cedula_reverso_url'],
      'trabajo_lugar': solicitud['trabajo_lugar'],
      'trabajo_direccion': solicitud['trabajo_direccion'],
      'jefe_nombre': solicitud['jefe_nombre'],
      'jefe_telefono': solicitud['jefe_telefono'],
      'ingreso_mensual': solicitud['ingreso_mensual'],
      'tipo_vivienda': solicitud['tipo_vivienda'],
      'evidencias_ingresos': solicitud['evidencias_ingresos'] ?? const <String>[],
      'ref1_nombre': solicitud['ref1_nombre'],
      'ref1_parentesco': solicitud['ref1_parentesco'],
      'ref1_telefono': solicitud['ref1_telefono'],
      'ref2_nombre': solicitud['ref2_nombre'],
      'ref2_parentesco': solicitud['ref2_parentesco'],
      'ref2_telefono': solicitud['ref2_telefono'],
      'metodo_cobro': solicitud['metodo_cobro'],
      'banco': solicitud['banco'],
      'numero_cuenta': solicitud['numero_cuenta'],
      'billetera': solicitud['billetera'],
    }).select().single());

    // 2. Crea el préstamo en estado "borrador" para que el prestamista lo ajuste
    await client.from('prestamos').insert({
      'prestamista_id': solicitud['prestamista_id'],
      'cliente_id': cliente['id'],
      'monto': solicitud['monto_solicitado'] ?? 0,
      'estado': 'borrador',
    });

    // 3. Marca la solicitud como aprobada
    await client
        .from('solicitudes')
        .update({'estado': 'aprobada'}).eq('id', solicitud['id']);
  }

  /// Convierte el error de la base de datos por límite del plan en
  /// [LimitePlan], para que la app ofrezca mejorar el plan.
  Future<T> _conLimite<T>(Future<T> Function() accion) async {
    try {
      return await accion();
    } on PostgrestException catch (e) {
      final m = RegExp(r'LIMITE_PLAN: tu plan permite (\d+)').firstMatch(e.message);
      if (m != null) throw LimitePlan(int.parse(m.group(1)!));
      rethrow;
    }
  }

  // ---------------------------------------------------------
  // PLANES Y ADMINISTRACIÓN
  // ---------------------------------------------------------

  /// Planes disponibles, del más barato al más caro.
  Future<List<Map<String, dynamic>>> obtenerPlanes() =>
      client.from('planes').select().order('orden');

  /// WhatsApp de soporte, instrucciones de pago, etc. (null si no hay).
  Future<Map<String, dynamic>?> obtenerAjustes() =>
      client.from('ajustes_app').select().eq('id', 1).maybeSingle();

  /// Cuántos clientes tiene el prestamista en su lista (los archivados no
  /// cuentan para el plan).
  Future<int> contarClientes(String prestamistaId) async {
    final filas = await _conArchivo(() => client
        .from('clientes')
        .select(_hayArchivoClientes ? 'id, archivado_en' : 'id')
        .eq('prestamista_id', prestamistaId));
    return filas.where((c) => !estaArchivado(c)).length;
  }

  // ---------------------------------------------------------
  // INVITACIONES entre prestamistas: link /i/{slug} (ver
  // migracion_2026_10_14_invitaciones.sql)
  // ---------------------------------------------------------

  static const _claveInvitacion = 'invitado_por_slug';

  /// Guarda en este teléfono el link de invitación con que se abrió la app,
  /// para usarlo cuando la persona termine de registrarse.
  Future<void> guardarInvitacion(String slug) async {
    try {
      await (await SharedPreferences.getInstance()).setString(_claveInvitacion, slug);
    } catch (_) {
      // Sin almacenamiento: se registra sin invitación.
    }
  }

  /// El prestamista que invitó (según el link guardado), o null.
  Future<({String id, String nombre})?> quienInvito() async {
    try {
      final slug = (await SharedPreferences.getInstance()).getString(_claveInvitacion);
      if (slug == null) return null;
      final p = await obtenerPerfilPorSlug(slug);
      if (p == null) return null;
      final negocio = (p['negocio'] as String?)?.trim() ?? '';
      return (
        id: p['id'] as String,
        nombre: negocio.isNotEmpty ? negocio : (p['nombre'] as String?) ?? '',
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> olvidarInvitacion() async {
    try {
      await (await SharedPreferences.getInstance()).remove(_claveInvitacion);
    } catch (_) {}
  }

  /// Admin: da 1 mes gratis al que invitó a [invitadoId] (el invitado ya
  /// pagó su primer plan). Devuelve hasta cuándo le quedó el plan.
  Future<DateTime> adminPremioInvitacion(String invitadoId) async {
    final vence = await client.rpc('admin_premio_invitacion', params: {'invitado': invitadoId});
    return DateTime.parse(vence as String);
  }

  /// Panel de administración: todos los prestamistas (solo admins).
  Future<List<Map<String, dynamic>>> adminPrestamistas() async {
    final filas = await client.rpc('admin_prestamistas');
    return List<Map<String, dynamic>>.from(filas as List);
  }

  /// Admin: aprobar / cambiar plan / fecha de vencimiento de un prestamista.
  Future<void> adminActualizarPrestamista(String id, Map<String, dynamic> cambios) async {
    await client.from('profiles').update(cambios).eq('id', id);
  }

  /// Admin: registra una mensualidad recibida y extiende el plan (lo hace
  /// la base de datos en un solo paso). Devuelve hasta cuándo quedó.
  Future<DateTime> adminRegistrarPago({
    required String prestamistaId,
    required String plan,
    required int meses,
    required double monto,
    required String metodo,
    String? nota,
  }) async {
    final vence = await client.rpc('admin_registrar_pago', params: {
      'prestamista': prestamistaId,
      'plan_pagado': plan,
      'meses': meses,
      'monto': monto,
      'metodo': metodo,
      'nota': nota,
    });
    return DateTime.parse(vence as String);
  }

  /// Mensualidades pagadas, la más reciente primero, con el nombre del
  /// prestamista. El admin ve todas; un prestamista, las suyas.
  Future<List<Map<String, dynamic>>> obtenerPagosPlanes({String? prestamistaId, int limite = 100}) async {
    var consulta = client.from('pagos_planes').select('*, profiles(nombre)');
    if (prestamistaId != null) consulta = consulta.eq('prestamista_id', prestamistaId);
    return consulta.order('created_at', ascending: false).limit(limite);
  }

  /// Admin: borra un pago mal registrado (no cambia el plan).
  Future<void> adminBorrarPagoPlan(String id) async {
    await client.from('pagos_planes').delete().eq('id', id);
  }

  /// El WhatsApp del prestamista (para recordarle cuándo le toca pagar).
  Future<void> guardarMiWhatsApp(String prestamistaId, String whatsapp) async {
    await client.from('profiles').update({'whatsapp': whatsapp}).eq('id', prestamistaId);
  }

  /// Aprueba la solicitud de alguien que YA es cliente (misma cédula): no
  /// crea otro cliente, le abre un préstamo en "borrador" en su ficha.
  Future<void> aprobarParaClienteExistente(
    Map<String, dynamic> solicitud,
    Map<String, dynamic> cliente,
  ) async {
    await client
        .from('solicitudes')
        .update({'estado': 'aprobada'}).eq('id', solicitud['id']);
    await client.from('prestamos').insert({
      'prestamista_id': solicitud['prestamista_id'],
      'cliente_id': cliente['id'],
      'monto': solicitud['monto_solicitado'] ?? 0,
      'estado': 'borrador',
    });
  }

  /// Crea un cliente a mano (sin solicitud, para quien no puede llenar el
  /// formulario) y su préstamo en "borrador", igual que al aprobar una
  /// solicitud. Devuelve el cliente y el préstamo para ir directo a Prestar.
  /// Falla si el prestamista ya tiene un cliente con esa cédula.
  Future<({Map<String, dynamic> cliente, Map<String, dynamic> prestamo})> crearClienteManual({
    required String prestamistaId,
    required Map<String, dynamic> datos,
    double? monto,
  }) async {
    final repetido = await client
        .from('clientes')
        .select() // con archivado_en, si ya se corrió la migración
        .eq('prestamista_id', prestamistaId)
        .eq('cedula', datos['cedula'])
        .maybeSingle();
    if (repetido != null) {
      throw ClienteRepetido(repetido['nombre'] as String? ?? '', eliminado: estaArchivado(repetido));
    }

    final cliente = await _conLimite(() => client
        .from('clientes')
        .insert({...datos, 'prestamista_id': prestamistaId, 'metodo_cobro': 'efectivo'})
        .select()
        .single());
    final prestamo = await client
        .from('prestamos')
        .insert({
          'prestamista_id': prestamistaId,
          'cliente_id': cliente['id'],
          'monto': monto ?? 0,
          'estado': 'borrador',
        })
        .select()
        .single();
    return (cliente: cliente, prestamo: prestamo);
  }

  /// Lista corta de clientes (para buscar mientras se escribe). Trae
  /// también los archivados (con `archivado_en`), para avisar de repetidos.
  Future<List<Map<String, dynamic>>> listarClientes(String prestamistaId) {
    return _conArchivo(() => client
        .from('clientes')
        .select('id, prestamista_id, nombre, cedula, telefono, direccion, foto_cara_url'
            '')
        .eq('prestamista_id', prestamistaId)
        .order('nombre'));
  }

  /// false si la base de datos todavía no tiene clientes.archivado_en.
  bool _hayArchivoClientes = true;

  Future<T> _conArchivo<T>(Future<T> Function() consulta) async {
    try {
      return await consulta();
    } on PostgrestException catch (e) {
      if (!_hayArchivoClientes || !e.message.contains('archivado_en')) rethrow;
      _hayArchivoClientes = false;
      return consulta();
    }
  }

  /// Quita al cliente de la lista sin borrarlo: queda archivado con sus
  /// préstamos pagados, cobros y fotos, y se puede restaurar. Solo si no
  /// tiene un préstamo en la calle; los préstamos sin entregar (borrador)
  /// se cancelan.
  Future<void> archivarCliente(String clienteId) async {
    final prestamos = await client
        .from('prestamos')
        .select('id, estado')
        .eq('cliente_id', clienteId);
    if (prestamos.any((p) => prestamoActivo(p['estado'] as String?))) {
      throw const ClienteConPrestamo();
    }
    try {
      await client.from('clientes').update({
        'archivado_en': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', clienteId);
    } on PostgrestException catch (e) {
      if (e.message.contains('TIENE_PRESTAMO')) throw const ClienteConPrestamo();
      if (e.message.contains('archivado_en')) throw const FaltaMigracionArchivo();
      rethrow;
    }
    final borradores = [
      for (final p in prestamos)
        if (p['estado'] == 'borrador') p['id'] as String,
    ];
    if (borradores.isNotEmpty) {
      await client.from('prestamos').update({'estado': 'cancelado'}).inFilter('id', borradores);
    }
  }

  /// Vuelve a poner en la lista a un cliente archivado (respeta el límite
  /// del plan).
  Future<void> restaurarCliente(String clienteId) async {
    await _conLimite(
        () => client.from('clientes').update({'archivado_en': null}).eq('id', clienteId));
  }

  /// Todos los datos de un cliente (los que copió de su solicitud).
  Future<Map<String, dynamic>?> obtenerCliente(String clienteId) {
    return client.from('clientes').select().eq('id', clienteId).maybeSingle();
  }

  /// La solicitud original (tiene datos que el cliente no guarda, como el
  /// ingreso mensual o la capacidad de pago).
  Future<Map<String, dynamic>?> obtenerSolicitud(String solicitudId) {
    return client.from('solicitudes').select().eq('id', solicitudId).maybeSingle();
  }

  /// Todos los préstamos de un cliente, el más nuevo primero.
  Future<List<Map<String, dynamic>>> obtenerPrestamosDeCliente(String clienteId) {
    return client
        .from('prestamos')
        .select()
        .eq('cliente_id', clienteId)
        .order('created_at', ascending: false);
  }

  /// Préstamo nuevo en "borrador" para un cliente que ya existe (ej. uno
  /// que saldó y vuelve a pedir).
  Future<Map<String, dynamic>> crearPrestamoBorrador(Map<String, dynamic> cliente) {
    return client
        .from('prestamos')
        .insert({
          'prestamista_id': cliente['prestamista_id'],
          'cliente_id': cliente['id'],
          'monto': 0,
          'estado': 'borrador',
        })
        .select()
        .single();
  }

  Future<void> rechazarSolicitud(String solicitudId) async {
    await client
        .from('solicitudes')
        .update({'estado': 'rechazada'}).eq('id', solicitudId);
  }

  // ---------------------------------------------------------
  // CLIENTES (Fase 2)
  // ---------------------------------------------------------

  /// Stream en tiempo real de todos los clientes del prestamista.
  Stream<List<Map<String, dynamic>>> clientesStream(String prestamistaId) {
    return client
        .from('clientes')
        .stream(primaryKey: ['id'])
        .eq('prestamista_id', prestamistaId)
        .order('created_at');
  }

  /// Busca el préstamo más reciente de un cliente (usualmente el "borrador"
  /// creado automáticamente al aprobar su solicitud).
  Future<Map<String, dynamic>?> obtenerUltimoPrestamo(String clienteId) async {
    return client
        .from('prestamos')
        .select()
        .eq('cliente_id', clienteId)
        .order('created_at', ascending: false)
        .limit(1)
        .maybeSingle();
  }

  // ---------------------------------------------------------
  // PRESTAMOS (Fase 2)
  // ---------------------------------------------------------

  /// Confirma el préstamo: fija monto, interés, frecuencia y mora, calcula
  /// la cantidad de cuotas y el monto de cada una (ver calc.calcularPlan),
  /// y lo pasa a estado "en_calle".
  Future<void> confirmarPrestamo({
    required String prestamoId,
    required double monto,
    required double tasaInteresMensual,
    required String frecuencia, // diario / semanal
    required int diasPlazo,
    required double moraDiaria, // % diario de lo que falta de la cuota
    required int diasGracia,
    calc.TipoInteres tipo = calc.TipoInteres.saldo,
  }) async {
    if (moraDiaria < 0) throw ArgumentError.value(moraDiaria, 'moraDiaria');
    if (diasGracia < 0) throw ArgumentError.value(diasGracia, 'diasGracia');
    final plan = calc.calcularPlan(
      monto: monto,
      tasaInteresMensual: tasaInteresMensual,
      diasPlazo: diasPlazo,
      frecuencia: frecuencia,
      tipo: tipo,
    );
    final datos = {
      'monto': monto,
      'tasa_interes': tasaInteresMensual,
      'cuota': plan.cuota,
      'cantidad_cuotas': plan.cantidadCuotas,
      'monto_total': plan.montoTotal,
      'mora_diaria': moraDiaria,
      'dias_gracia': diasGracia,
      'frecuencia': frecuencia,
      'tipo_interes': tipo.valor,
      'fecha_desembolso': calc.fechaSql(DateTime.now()),
      'estado': 'en_calle',
    };
    // La primera cuota del cronograma, así sale de la misma fuente que Cobrar.
    datos['proximo_pago'] = calc.fechaSql(calc.proximoPago(datos, 0)!);

    await client.from('prestamos').update(datos).eq('id', prestamoId);
  }

  /// Stream en tiempo real de los préstamos "en la calle" del prestamista.
  Stream<List<Map<String, dynamic>>> prestamosEnCalleStream(String prestamistaId) {
    return client
        .from('prestamos')
        .stream(primaryKey: ['id'])
        .eq('prestamista_id', prestamistaId)
        .order('proximo_pago');
  }

  /// Suma el BALANCE real (cuotas + mora, menos lo ya pagado) de todos los
  /// préstamos "en la calle" — no el monto prestado original, que no baja
  /// nunca aunque el cliente vaya pagando.
  Future<double> obtenerBalanceTotalEnCalle(
      List<Map<String, dynamic>> prestamosEnCalle) async {
    double total = 0;
    for (final p in prestamosEnCalle) {
      total += (await obtenerEstado(p)).balance;
    }
    return total;
  }

  static const _columnasPagoSinCobrador =
      'id, numero_recibo, monto, monto_mora, fecha_pago, anulado, anulado_en, motivo_anulacion';

  /// Con el cobrador que lo hizo; sin él mientras falte la migración de
  /// cobradores (para que la app siga funcionando).
  bool _hayCobradorEnPagos = true;

  /// false mientras falte la migración de saldar antes (pagos.descuento).
  bool _hayDescuentoEnPagos = true;
  String get _columnasPago => [
        _columnasPagoSinCobrador,
        if (_hayCobradorEnPagos) 'cobrador_id',
        if (_hayDescuentoEnPagos) 'descuento',
      ].join(', ');

  Future<T> _conColumnasPago<T>(Future<T> Function() consulta) async {
    while (true) {
      try {
        return await consulta();
      } on PostgrestException catch (e) {
        if (_hayCobradorEnPagos && e.message.contains('cobrador_id')) {
          _hayCobradorEnPagos = false;
        } else if (_hayDescuentoEnPagos && e.message.contains('descuento')) {
          _hayDescuentoEnPagos = false;
        } else {
          rethrow;
        }
      }
    }
  }

  /// Los pagos de un préstamo (también los anulados, marcados), con su
  /// fecha, cuánto fue a mora y su número de recibo.
  Future<List<calc.PagoRegistrado>> obtenerPagos(String prestamoId) async {
    final filas = await _conColumnasPago(() => client
        .from('pagos')
        .select(_columnasPago)
        .eq('prestamo_id', prestamoId)
        .order('fecha_pago'));
    return filas.map(calc.PagoRegistrado.desdeFila).toList();
  }

  /// Cuotas, mora y balance de un préstamo al día de hoy (ver
  /// calc.estadoPrestamo). Es lo que muestran Cobrar y Reportes.
  Future<calc.EstadoPrestamo> obtenerEstado(Map<String, dynamic> prestamo) async {
    final pagos = await obtenerPagos(prestamo['id']);
    return calc.estadoPrestamo(prestamo, pagos, DateTime.now());
  }

  /// Registra un cobro repartido entre cuota y mora (ver calc.repartirPago),
  /// mueve proximo_pago a la siguiente cuota pendiente y, si ya no debe
  /// nada (cuotas + mora), marca el préstamo como "pagado". Devuelve el
  /// pago guardado (con su reparto y número de recibo).
  Future<calc.PagoRegistrado> registrarPago({
    required String prestamoId,
    required String prestamistaId,
    required double monto,
    ({double lat, double lng})? ubicacion,

    /// Interés que se perdona al saldar antes de tiempo (ver
    /// calc.calcularSaldarHoy). Solo el prestamista.
    double descuento = 0,
  }) async {
    final prestamo = await client
        .from('prestamos')
        .select()
        .eq('id', prestamoId)
        .single();
    final pagos = await obtenerPagos(prestamoId);
    // obtenerPagos ya revisó si existe la columna del descuento.
    if (descuento > 0 && !_hayDescuentoEnPagos) throw const FaltaMigracionSaldar();
    final ahora = DateTime.now();
    final reparto = calc.repartirPago(calc.estadoPrestamo(prestamo, pagos, ahora), monto);

    // numero_recibo lo asigna la base de datos (trigger), por eso se lee de vuelta.
    Future<Map<String, dynamic>> guardar(bool conUbicacion) => _conColumnasPago(() => client
        .from('pagos')
        .insert({
          'prestamo_id': prestamoId,
          'prestamista_id': prestamistaId,
          'monto': monto,
          'monto_mora': reparto.mora,
          'metodo': 'efectivo',
          if (descuento > 0) 'descuento': descuento,
          if (conUbicacion && ubicacion != null) ...{
            'lat': ubicacion.lat,
            'lng': ubicacion.lng,
          },
        })
        .select(_columnasPago)
        .single());
    Map<String, dynamic> fila;
    try {
      fila = await guardar(true);
    } on PostgrestException catch (e) {
      // Sin la migración del GPS todavía: el cobro se guarda sin ubicación.
      if (ubicacion == null || !e.message.contains('lat')) rethrow;
      fila = await guardar(false);
    }
    final pago = calc.PagoRegistrado.desdeFila(fila);

    final despues = calc.estadoPrestamo(prestamo, [...pagos, pago], ahora);
    final proximo = despues.proximoPago;
    await client.from('prestamos').update({
      if (proximo != null) 'proximo_pago': calc.fechaSql(proximo),
      if (despues.saldado) 'estado': 'pagado',
    }).eq('id', prestamoId);

    return pago;
  }

  /// Anula un cobro mal digitado: no se borra (queda la marca, la fecha y el
  /// motivo) pero deja de contar. Recalcula el préstamo: si había quedado
  /// saldado por ese cobro, vuelve a la calle.
  Future<void> anularPago({
    required Map<String, dynamic> prestamo,
    required calc.PagoRegistrado pago,
    required String motivo,
  }) async {
    if (pago.id == null) throw ArgumentError('Cobro sin id');
    await client.from('pagos').update({
      'anulado': true,
      'anulado_en': DateTime.now().toUtc().toIso8601String(),
      'motivo_anulacion': motivo.trim(),
    }).eq('id', pago.id!);

    final pagos = await obtenerPagos(prestamo['id']);
    final estado = calc.estadoPrestamo(prestamo, pagos, DateTime.now());
    final proximo = estado.proximoPago;
    await client.from('prestamos').update({
      'estado': estado.saldado ? 'pagado' : 'en_calle',
      if (proximo != null) 'proximo_pago': calc.fechaSql(proximo),
    }).eq('id', prestamo['id']);
  }

  /// Cancela un préstamo creado por error. Solo si no tiene cobros válidos
  /// (si los tiene, primero hay que anularlos).
  Future<void> cancelarPrestamo(Map<String, dynamic> prestamo) async {
    final pagos = calc.pagosValidos(await obtenerPagos(prestamo['id']));
    if (pagos.isNotEmpty) {
      throw StateError('Tiene ${pagos.length} cobro(s). Anúlalos primero.');
    }
    await client.from('prestamos').update({'estado': 'cancelado'}).eq('id', prestamo['id']);
  }

  /// Guarda dónde está la casa (o el negocio) del cliente, para el mapa.
  Future<void> guardarUbicacionCliente(String clienteId, double lat, double lng) async {
    await client.from('clientes').update({'lat': lat, 'lng': lng}).eq('id', clienteId);
  }

  /// Corrige los datos de un cliente. Falla si la cédula nueva ya es de
  /// otro cliente del mismo prestamista.
  Future<void> actualizarCliente(Map<String, dynamic> cliente, Map<String, dynamic> datos) async {
    final cedula = datos['cedula'] as String?;
    if (cedula != null && cedula != cliente['cedula']) {
      final repetido = await client
          .from('clientes')
          .select('id, nombre')
          .eq('prestamista_id', cliente['prestamista_id'])
          .eq('cedula', cedula)
          .neq('id', cliente['id'])
          .maybeSingle();
      if (repetido != null) throw ClienteRepetido(repetido['nombre'] as String? ?? '');
    }
    await client.from('clientes').update(datos).eq('id', cliente['id']);
  }

  /// Historial de cambios del cliente (lo anota la base de datos al
  /// guardar). Vacío si falta correr la migración del historial.
  Future<List<historial.CambioCliente>> obtenerHistorialCliente(String clienteId) async {
    try {
      final filas = await client
          .from('clientes_historial')
          .select('campo, antes, despues, created_at')
          .eq('cliente_id', clienteId)
          .order('created_at', ascending: false);
      return filas.map(historial.CambioCliente.desdeFila).toList();
    } catch (e) {
      // ignore: avoid_print
      print('ERROR REAL HISTORIAL: $e');
      return const [];
    }
  }

  // ---------------------------------------------------------
  // CAJA POR DÍA Y CIERRES (Reportes)
  // ---------------------------------------------------------

  /// Lo que ya había pagado un cliente importado de Excel no es dinero que
  /// entró ese día: no cuenta en la caja ni en las gráficas.
  static bool _noImportado(Map<String, dynamic> fila) => fila['metodo'] != 'importado';

  /// Cobros del prestamista desde `desde` (también los anulados), con el
  /// nombre del cliente, para la caja por día.
  Future<List<caja.CobroCaja>> obtenerCobrosCaja(String prestamistaId, {DateTime? desde}) async {
    Future<List<Map<String, dynamic>>> buscar() => _conColumnasPago(() {
          var consulta = client
              .from('pagos')
              .select('id, numero_recibo, monto, monto_mora, fecha_pago, anulado, metodo, '
                  '${_hayCobradorEnPagos ? 'cobrador_id, ' : ''}'
                  '${_hayGpsEnPagos ? 'lat, lng, ' : ''}prestamos(clientes(nombre))')
              .eq('prestamista_id', prestamistaId);
          if (desde != null) {
            consulta = consulta.gte('fecha_pago', desde.toUtc().toIso8601String());
          }
          return consulta.order('fecha_pago', ascending: false);
        });
    List<Map<String, dynamic>> filas;
    try {
      filas = await buscar();
    } on PostgrestException catch (e) {
      // Sin la migración del GPS todavía: la caja se ve sin ubicaciones.
      if (!_hayGpsEnPagos || !e.message.contains('lat')) rethrow;
      _hayGpsEnPagos = false;
      filas = await buscar();
    }
    return filas.where(_noImportado).map(caja.CobroCaja.desdeFila).toList();
  }

  /// false si la base de datos todavía no tiene pagos.lat / pagos.lng.
  bool _hayGpsEnPagos = true;

  /// Entregas de los cobradores de un día, por cobrador. Vacío si falta la
  /// migración de entregas.
  Future<Map<String, caja.Entrega>> obtenerEntregas(String prestamistaId, DateTime dia) async {
    try {
      final filas = await client
          .from('entregas_cobrador')
          .select()
          .eq('prestamista_id', prestamistaId)
          .eq('fecha', caja.claveDia(dia));
      return {for (final e in filas.map(caja.Entrega.desdeFila)) e.cobradorId: e};
    } catch (e) {
      // ignore: avoid_print
      print('ERROR REAL ENTREGAS: $e');
      return const {};
    }
  }

  /// Anota (o corrige) lo que un cobrador entregó ese día.
  Future<void> guardarEntrega(String prestamistaId, caja.Entrega e) async {
    await client.from('entregas_cobrador').upsert({
      'prestamista_id': prestamistaId,
      'cobrador_id': e.cobradorId,
      'fecha': caja.claveDia(e.fecha),
      'cobrado': e.cobrado,
      'entregado': e.entregado,
      'nota': (e.nota?.trim().isEmpty ?? true) ? null : e.nota!.trim(),
    }, onConflict: 'cobrador_id,fecha');
  }

  Future<void> borrarEntrega(String entregaId) async {
    await client.from('entregas_cobrador').delete().eq('id', entregaId);
  }

  /// La entrega de hoy del cobrador que usa la app (null si su jefe no la
  /// ha anotado).
  Future<caja.Entrega?> miEntregaDeHoy() async {
    final sesion = sesionCobrador;
    if (sesion == null) return null;
    try {
      final fila = await client
          .from('entregas_cobrador')
          .select()
          .eq('cobrador_id', sesion.cobradorId)
          .eq('fecha', caja.claveDia(DateTime.now()))
          .maybeSingle();
      return fila == null ? null : caja.Entrega.desdeFila(fila);
    } catch (_) {
      return null;
    }
  }

  /// Cobros desde una fecha (también los anulados, marcados), para las
  /// gráficas de Reportes.
  Future<List<graficas.CobroGrafica>> obtenerCobrosGraficas(
      String prestamistaId, DateTime desde) async {
    final filas = await _conColumnasPago(() => client
        .from('pagos')
        .select('prestamo_id, monto, monto_mora, fecha_pago, anulado, metodo'
            '${_hayDescuentoEnPagos ? ', descuento' : ''}')
        .eq('prestamista_id', prestamistaId)
        .gte('fecha_pago', desde.toUtc().toIso8601String()));
    return filas.where(_noImportado).map(graficas.CobroGrafica.desdeFila).toList();
  }

  /// Cierres de caja guardados, por día ("2026-09-23" → fila).
  Future<Map<String, Map<String, dynamic>>> obtenerCierres(String prestamistaId) async {
    final filas = await client
        .from('cierres_caja')
        .select()
        .eq('prestamista_id', prestamistaId)
        .order('fecha', ascending: false);
    return {for (final f in filas) f['fecha'] as String: f};
  }

  /// Guarda (o reemplaza) el cierre de un día.
  Future<void> cerrarCaja(String prestamistaId, caja.DiaCaja dia, {String? nota}) async {
    await client.from('cierres_caja').upsert({
      'prestamista_id': prestamistaId,
      'fecha': caja.claveDia(dia.dia),
      'total': dia.total,
      'cuotas': dia.cuotas,
      'mora': dia.mora,
      'cantidad_cobros': dia.cantidad,
      'nota': (nota?.trim().isEmpty ?? true) ? null : nota!.trim(),
    }, onConflict: 'prestamista_id,fecha');
  }

  /// Borra un cierre. No toca los cobros de ese día.
  Future<void> borrarCierre(String cierreId) async {
    await client.from('cierres_caja').delete().eq('id', cierreId);
  }

  // ---------------------------------------------------------
  // GASTOS DEL NEGOCIO (Reportes → Gastos)
  // ---------------------------------------------------------

  /// Gastos desde `desde` (y hasta `hasta`, si se da), el más reciente
  /// primero. Si la tabla no existe todavía (falta correr la migración),
  /// devuelve vacío para que Reportes y la caja se vean igual.
  Future<List<gastos.Gasto>> obtenerGastos(String prestamistaId,
      {required DateTime desde, DateTime? hasta}) async {
    try {
      var consulta = client
          .from('gastos')
          .select()
          .eq('prestamista_id', prestamistaId)
          .gte('fecha', caja.claveDia(desde));
      if (hasta != null) consulta = consulta.lte('fecha', caja.claveDia(hasta));
      final filas =
          await consulta.order('fecha', ascending: false).order('created_at', ascending: false);
      return filas.map(gastos.Gasto.desdeFila).toList();
    } catch (e) {
      // ignore: avoid_print
      print('ERROR REAL GASTOS: $e');
      return const [];
    }
  }

  Future<void> agregarGasto(String prestamistaId, gastos.Gasto g) async {
    await client.from('gastos').insert({
      'prestamista_id': prestamistaId,
      'fecha': caja.claveDia(g.fecha),
      'monto': g.monto,
      'categoria': g.categoria,
      'nota': (g.nota?.trim().isEmpty ?? true) ? null : g.nota!.trim(),
    });
  }

  /// Borra un gasto anotado por error. No toca préstamos ni cobros.
  Future<void> borrarGasto(String gastoId) async {
    await client.from('gastos').delete().eq('id', gastoId);
  }

  // ---------------------------------------------------------
  // COBRADORES
  // ---------------------------------------------------------

  /// Al entrar sin perfil de prestamista: si ese correo fue invitado como
  /// cobrador, lo amarra y deja lista [sesionCobrador]. Null si no es
  /// cobrador (o si falta la migración de cobradores).
  Future<cob.SesionCobrador?> entrarComoCobrador() async {
    sesionCobrador = null;
    cobradorSinPlan = null;
    try {
      await client.rpc('aceptar_invitacion_cobrador');
      final filas = await client.rpc('mi_jefe') as List;
      if (filas.isEmpty) {
        try {
          cobradorSinPlan = await client.rpc('cobrador_sin_plan') as String?;
        } catch (_) {
          // Sin la migración de seguridad todavía.
        }
        return null;
      }
      return sesionCobrador =
          cob.SesionCobrador.desdeFila(Map<String, dynamic>.from(filas.first as Map));
    } catch (e) {
      // ignore: avoid_print
      print('ERROR REAL ENTRAR COMO COBRADOR: $e');
      return null;
    }
  }

  /// Los cobradores del prestamista, los activos primero.
  Future<List<cob.Cobrador>> listarCobradores(String prestamistaId) async {
    try {
      final filas = await client
          .from('cobradores')
          .select()
          .eq('prestamista_id', prestamistaId)
          .order('activo', ascending: false)
          .order('created_at');
      return filas.map(cob.Cobrador.desdeFila).toList();
    } catch (e) {
      // ignore: avoid_print
      print('ERROR REAL COBRADORES: $e');
      return const [];
    }
  }

  /// Convierte los errores de la base de datos en mensajes claros.
  Future<T> _conErroresCobrador<T>(Future<T> Function() accion) async {
    try {
      return await accion();
    } on PostgrestException catch (e) {
      final m = RegExp(r'LIMITE_COBRADORES: tu plan permite (\d+)').firstMatch(e.message);
      if (m != null) throw LimiteCobradores(int.parse(m.group(1)!));
      if (e.code == '23505' && '${e.message} ${e.details}'.contains('email')) {
        throw StateError('Ese correo ya es cobrador (tuyo o de otro prestamista).');
      }
      rethrow;
    }
  }

  Future<cob.Cobrador> agregarCobrador(String prestamistaId,
      {required String nombre, required String email, String? telefono}) {
    return _conErroresCobrador(() async {
      final fila = await client
          .from('cobradores')
          .insert({
            'prestamista_id': prestamistaId,
            'nombre': nombre.trim(),
            'email': email.trim().toLowerCase(),
            'telefono': (telefono?.trim().isEmpty ?? true) ? null : telefono!.trim(),
          })
          .select()
          .single();
      return cob.Cobrador.desdeFila(fila);
    });
  }

  /// Nombre, correo o teléfono; o activo = false para quitarle el acceso.
  Future<void> actualizarCobrador(String cobradorId, Map<String, dynamic> cambios) {
    return _conErroresCobrador(
        () => client.from('cobradores').update(cambios).eq('id', cobradorId));
  }

  /// Le da estos clientes al cobrador (null = sin cobrador: los cobra el
  /// prestamista).
  Future<void> asignarCobrador(List<String> clienteIds, String? cobradorId) async {
    if (clienteIds.isEmpty) return;
    await client.from('clientes').update({'cobrador_id': cobradorId}).inFilter('id', clienteIds);
  }

  /// Cédulas (solo dígitos) de los clientes que ya tiene, para no importarlos
  /// dos veces.
  Future<Set<String>> cedulasDeMisClientes(String prestamistaId) async {
    final filas = await client.from('clientes').select('cedula').eq('prestamista_id', prestamistaId);
    return {for (final f in filas) soloDigitos(f['cedula'] as String?)};
  }

  /// Guarda un cliente del Excel y, si trae, su préstamo en la calle. Lo que
  /// ya pagó se anota como un cobro "importado" del día del préstamo: cubre
  /// las primeras cuotas y no cuenta como dinero de la caja.
  Future<void> importarCliente(String prestamistaId, importar.FilaImportada f) async {
    final cliente = await _conLimite(() => client
        .from('clientes')
        .insert({...f.cliente, 'prestamista_id': prestamistaId, 'metodo_cobro': 'efectivo'})
        .select('id')
        .single());
    final p = f.prestamo;
    if (p == null) return;
    final prestamo = await client
        .from('prestamos')
        .insert({...p.datos(), 'prestamista_id': prestamistaId, 'cliente_id': cliente['id']})
        .select('id')
        .single();
    if (p.yaPago > 0) {
      await client.from('pagos').insert({
        'prestamo_id': prestamo['id'],
        'prestamista_id': prestamistaId,
        'monto': p.yaPago,
        'monto_mora': 0,
        'metodo': 'importado',
        'fecha_pago':
            DateTime(p.fecha.year, p.fecha.month, p.fecha.day, 12).toUtc().toIso8601String(),
      });
    }
  }

  /// Clientes con su cobrador, para repartir la ruta.
  Future<List<Map<String, dynamic>>> clientesParaRepartir(String prestamistaId) async {
    final filas = await _conArchivo(() => client
        .from('clientes')
        .select('id, nombre, direccion, cobrador_id')
        .eq('prestamista_id', prestamistaId)
        .order('nombre'));
    return filas.where((c) => !estaArchivado(c)).toList();
  }

  /// Cobros de hoy del cobrador que usa la app (para "Mi caja").
  Future<List<caja.CobroCaja>> misCobrosDeHoy() async {
    final sesion = sesionCobrador;
    if (sesion == null) return const [];
    final hoy = DateTime.now();
    final filas = await client
        .from('pagos')
        .select('id, numero_recibo, monto, monto_mora, fecha_pago, anulado, metodo, '
            'prestamos(clientes(nombre))')
        .eq('cobrador_id', sesion.cobradorId)
        .gte('fecha_pago', DateTime(hoy.year, hoy.month, hoy.day).toUtc().toIso8601String())
        .order('fecha_pago', ascending: false);
    return filas.map(caja.CobroCaja.desdeFila).toList();
  }

  // ---------------------------------------------------------
  // GESTIONES Y ACUERDOS DE COBRO
  // ---------------------------------------------------------

  /// Gestiones de un préstamo, la más reciente primero. Si la tabla no
  /// existe todavía (falta correr la migración), devuelve vacío para que
  /// el cobro siga funcionando.
  Future<List<gest.Gestion>> obtenerGestiones(String prestamoId) async {
    try {
      final filas = await client
          .from('gestiones')
          .select()
          .eq('prestamo_id', prestamoId)
          .order('created_at', ascending: false);
      return filas.map(gest.Gestion.desdeFila).toList();
    } catch (e) {
      // ignore: avoid_print
      print('ERROR REAL GESTIONES: $e');
      return const [];
    }
  }

  /// Gestiones de varios préstamos a la vez, agrupadas por préstamo (para
  /// Inicio). Vacío si la tabla no existe todavía.
  Future<Map<String, List<gest.Gestion>>> _gestionesDe(List<String> prestamoIds) async {
    if (prestamoIds.isEmpty) return const {};
    try {
      final filas = await client
          .from('gestiones')
          .select()
          .inFilter('prestamo_id', prestamoIds)
          .order('created_at', ascending: false);
      final porPrestamo = <String, List<gest.Gestion>>{};
      for (final g in filas.map(gest.Gestion.desdeFila)) {
        porPrestamo.putIfAbsent(g.prestamoId, () => []).add(g);
      }
      return porPrestamo;
    } catch (e) {
      // ignore: avoid_print
      print('ERROR REAL GESTIONES: $e');
      return const {};
    }
  }

  /// Anota una gestión de cobro. Las gestiones no se editan ni se borran.
  Future<gest.Gestion> registrarGestion({
    required Map<String, dynamic> prestamo,
    required String tipo,
    required String resultado,
    String? acuerdo,
    DateTime? promesaFecha,
    double? promesaMonto,
  }) async {
    final esPromesa = resultado == 'promesa';
    final fila = await client
        .from('gestiones')
        .insert({
          'prestamista_id': prestamo['prestamista_id'],
          'prestamo_id': prestamo['id'],
          'cliente_id': prestamo['cliente_id'],
          'tipo': tipo,
          'resultado': resultado,
          'acuerdo': (acuerdo?.trim().isEmpty ?? true) ? null : acuerdo!.trim(),
          if (esPromesa && promesaFecha != null) 'promesa_fecha': calc.fechaSql(promesaFecha),
          if (esPromesa && promesaMonto != null) 'promesa_monto': promesaMonto,
        })
        .select()
        .single();
    return gest.Gestion.desdeFila(fila);
  }

  /// Todos los préstamos en la calle con su cliente y sus pagos: es lo que
  /// necesita el tablero de Inicio para calcular cobros del día y atrasos.
  Future<List<PrestamoConDatos>> obtenerCartera(String prestamistaId) async {
    final prestamos = await client
        .from('prestamos')
        .select()
        .eq('prestamista_id', prestamistaId)
        .eq('estado', 'en_calle');
    final porPrestamo = await _gestionesDe([for (final p in prestamos) p['id'] as String]);
    return Future.wait(prestamos.map((p) async {
      final cliente = await client
          .from('clientes')
          .select('nombre, direccion, telefono, foto_cara_url, lat, lng')
          .eq('id', p['cliente_id'])
          .maybeSingle();
      final pagos = await obtenerPagos(p['id']);
      return PrestamoConDatos(
          prestamo: p, cliente: cliente, pagos: pagos, gestiones: porPrestamo[p['id']] ?? const []);
    }));
  }

  Future<void> cerrarSesion() {
    sesionCobrador = null;
    return client.auth.signOut();
  }

  /// Cliente de un préstamo (para el recibo y el contrato).
  Future<Map<String, dynamic>?> obtenerClienteDePrestamo(Map<String, dynamic> prestamo) {
    return client
        .from('clientes')
        .select('nombre, cedula, telefono, direccion')
        .eq('id', prestamo['cliente_id'])
        .maybeSingle();
  }

  // ---------------------------------------------------------
  // REPORTES (Fase 3)
  // ---------------------------------------------------------

  /// Trae todos los préstamos (en la calle o pagados) junto con el nombre
  /// y teléfono del cliente, y cuánto se ha pagado de cada uno. Es la
  /// base para la pantalla de Reportes y para el Excel.
  Future<List<Map<String, dynamic>>> obtenerReportePrestamos(
      String prestamistaId) async {
    final prestamos = await client
        .from('prestamos')
        .select()
        .eq('prestamista_id', prestamistaId)
        .inFilter('estado', ['en_calle', 'pagado', 'atrasado']);

    final resultado = <Map<String, dynamic>>[];
    for (final p in prestamos) {
      final cliente = await client
          .from('clientes')
          .select('nombre, telefono, direccion, jefe_nombre, jefe_telefono, '
              'ref1_nombre, ref1_telefono')
          .eq('id', p['cliente_id'])
          .maybeSingle();
      final pagos = await obtenerPagos(p['id']);
      final hoy = DateTime.now();
      final estado = calc.estadoPrestamo(p, pagos, hoy);
      final proximo = estado.proximoPago;

      resultado.add({
        ...p,
        'cliente_nombre': cliente?['nombre'] ?? '',
        'cliente_telefono': cliente?['telefono'] ?? '',
        'cliente_direccion': cliente?['direccion'] ?? '',
        'cliente_jefe': cliente?['jefe_nombre'] ?? '',
        'cliente_jefe_telefono': cliente?['jefe_telefono'] ?? '',
        'cliente_ref1': cliente?['ref1_nombre'] ?? '',
        'cliente_ref1_telefono': cliente?['ref1_telefono'] ?? '',
        'monto_total': estado.montoTotal,
        // Solo lo que fue a cuotas (capital + interés), sin mora.
        'total_pagado': estado.cobradoCuotas,
        // Interés perdonado al saldar antes (no es dinero recibido).
        'total_descuento': estado.descuentos,
        'mora_cobrada': estado.moraCobrada,
        'mora_cobrada_mes': calc.moraCobradaEnMes(pagos, hoy),
        // Día del último cobro: para un préstamo pagado, es cuando se saldó.
        'fecha_ultimo_pago': calc.pagosValidos(pagos).isEmpty
            ? null
            : calc.pagosValidos(pagos).map((x) => x.fecha).fold<DateTime?>(
                null, (a, b) => a == null || b.isAfter(a) ? b : a),
        'mora_pendiente': estado.moraPendiente,
        // Lo que debe en total: cuotas + mora.
        'balance': estado.balance,
        // El estado completo, para la gráfica de la cartera.
        'estado_calculado': estado,
        // Desde el cronograma, no desde la columna: préstamos cobrados antes
        // de que registrarPago la actualizara la tienen desfasada.
        if (proximo != null) 'proximo_pago': calc.fechaSql(proximo),
      });
    }
    return resultado;
  }
}

/// Un préstamo con su cliente y sus pagos ya cargados.
class PrestamoConDatos {
  final Map<String, dynamic> prestamo;
  final Map<String, dynamic>? cliente;
  final List<calc.PagoRegistrado> pagos;

  /// Gestiones de cobro (visitas, llamadas, promesas), la más reciente primero.
  final List<gest.Gestion> gestiones;

  const PrestamoConDatos({
    required this.prestamo,
    required this.cliente,
    required this.pagos,
    this.gestiones = const [],
  });

  String get nombre => (cliente?['nombre'] as String?) ?? '...';
  String get direccion => (cliente?['direccion'] as String?) ?? '';

  calc.EstadoPrestamo estado(DateTime hoy) => calc.estadoPrestamo(prestamo, pagos, hoy);

  /// La última promesa de pago y cómo va (null si nunca prometió).
  gest.InfoPromesa? promesa(DateTime hoy) =>
      gest.ultimaPromesa(gestiones, pagos, hoy);
}

/// Ya existe un cliente con esa cédula para este prestamista.
class ClienteRepetido implements Exception {
  final String nombre;
  /// El que tiene esa cédula está en "Clientes eliminados".
  final bool eliminado;
  const ClienteRepetido(this.nombre, {this.eliminado = false});

  @override
  String toString() => eliminado
      ? 'Ya tienes un cliente con esa cédula: $nombre. Está en Clientes → Eliminados: restáuralo.'
      : 'Ya tienes un cliente con esa cédula: $nombre';
}

/// No se puede archivar: el cliente tiene un préstamo en la calle.
class ClienteConPrestamo implements Exception {
  const ClienteConPrestamo();

  @override
  String toString() =>
      'Tiene un préstamo en la calle. Solo se puede eliminar cuando lo termine de pagar.';
}

/// Falta correr migracion_2026_10_18_saldar_antes.sql.
class FaltaMigracionSaldar implements Exception {
  const FaltaMigracionSaldar();

  @override
  String toString() => 'Falta actualizar la base de datos (migración saldar_antes).';
}

/// Falta correr migracion_2026_10_18_archivar_clientes.sql.
class FaltaMigracionArchivo implements Exception {
  const FaltaMigracionArchivo();

  @override
  String toString() => 'Falta actualizar la base de datos (migración archivar_clientes).';
}

/// El plan del prestamista no permite más clientes.
/// El plan del prestamista no permite más cobradores.
class LimiteCobradores implements Exception {
  final int limite;
  const LimiteCobradores(this.limite);

  @override
  String toString() => limite == 0
      ? 'Tu plan no incluye cobradores. Con el Básico tienes 1 y con el Pro, 3.'
      : 'Tu plan permite $limite cobrador(es). Mejora tu plan para agregar más.';
}

class LimitePlan implements Exception {
  final int limite;
  const LimitePlan(this.limite);

  @override
  String toString() => limite == 0
      ? 'Tu cuenta todavía no está aprobada.'
      : 'Llegaste al límite de tu plan ($limite clientes).';
}
