import 'package:supabase_flutter/supabase_flutter.dart';

import 'sin_conexion.dart';
import 'supabase_service.dart';

/// Verificación en dos pasos (opcional, en Perfil): además de la contraseña,
/// un código de 6 números de una app de códigos (Google Authenticator...).
///
/// La base de datos no le muestra nada a quien la activó y no ha puesto el
/// código (ver migracion_2026_11_02_dos_pasos.sql): esto es solo la parte
/// de la app.
class DosPasos {
  DosPasos._();

  static GoTrueMFAApi get _mfa => SupabaseService.instance.client.auth.mfa;

  /// Si a esta sesión le falta el código para entrar. Se lee de la sesión
  /// guardada: funciona sin señal.
  static bool get faltaCodigo {
    final nivel = _mfa.getAuthenticatorAssuranceLevel();
    return pideCodigo(nivel.currentLevel, nivel.nextLevel);
  }

  /// El factor ya activado con el que se pide el código (null si no hay).
  static Factor? get factorActivo {
    final factores = SupabaseService.instance.client.auth.currentUser?.factors ?? const [];
    for (final f in factores) {
      if (f.factorType == FactorType.totp && f.status == FactorStatus.verified) return f;
    }
    return null;
  }

  /// Si la tiene activada (pregunta al servidor para tener lo último).
  static Future<bool> activada() async => (await _mfa.listFactors()).totp.isNotEmpty;

  /// Empieza a activarla: devuelve el QR y la clave para la app de códigos.
  /// Si quedó una a medias de antes, se borra primero.
  static Future<({String factorId, String uri, String clave})> empezar() async {
    final factores = await _mfa.listFactors();
    for (final f in factores.all) {
      if (f.status != FactorStatus.verified) await _mfa.unenroll(f.id);
    }
    final r = await _mfa.enroll(
      factorType: FactorType.totp,
      issuer: 'CrediSantiago',
      friendlyName: 'App de códigos',
    );
    final totp = r.totp!;
    return (factorId: r.id, uri: totp.uri, clave: totp.secret);
  }

  /// Revisa el código: al activarla ([factorId] el de [empezar]) o al entrar.
  static Future<void> verificar(String factorId, String codigo) =>
      _mfa.challengeAndVerify(factorId: factorId, code: codigo.trim());

  /// La quita (hace falta haber puesto el código en esta sesión).
  static Future<void> desactivar() async {
    final factores = await _mfa.listFactors();
    for (final f in factores.all) {
      await _mfa.unenroll(f.id);
    }
    await SupabaseService.instance.client.auth.refreshSession();
  }
}

/// Le falta el código a una sesión que entró solo con la contraseña
/// ([actual] aal1) cuando la cuenta tiene los dos pasos ([siguiente] aal2).
bool pideCodigo(AuthenticatorAssuranceLevels? actual, AuthenticatorAssuranceLevels? siguiente) =>
    actual == AuthenticatorAssuranceLevels.aal1 && siguiente == AuthenticatorAssuranceLevels.aal2;

/// Un código bien escrito: 6 números (se ignoran los espacios).
bool codigoBienEscrito(String texto) => RegExp(r'^\d{6}$').hasMatch(texto.replaceAll(' ', ''));

/// Mensaje para un código que el servidor no aceptó.
String mensajeCodigo(Object e) => SinConexion.esFaltaDeConexion(e)
    ? 'No se pudo revisar el código. Revisa tu internet e intenta de nuevo.'
    : 'Ese código no sirve. Revisa la app de códigos y escribe el que sale ahora.';
