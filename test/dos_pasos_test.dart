import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:prestamistas_rd/services/dos_pasos.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  const aal1 = AuthenticatorAssuranceLevels.aal1, aal2 = AuthenticatorAssuranceLevels.aal2;

  test('pide el código solo si entró con la contraseña y tiene los dos pasos', () {
    expect(pideCodigo(aal1, aal2), isTrue);
    expect(pideCodigo(aal1, aal1), isFalse, reason: 'no los activó');
    expect(pideCodigo(aal2, aal2), isFalse, reason: 'ya puso el código');
    expect(pideCodigo(null, null), isFalse, reason: 'sin sesión');
  });

  test('el código son 6 números', () {
    expect(codigoBienEscrito('123456'), isTrue);
    expect(codigoBienEscrito('123 456'), isTrue);
    expect(codigoBienEscrito('12345'), isFalse);
    expect(codigoBienEscrito('12345a'), isFalse);
    expect(codigoBienEscrito(''), isFalse);
  });

  test('sin señal no le dice que el código está malo', () {
    expect(mensajeCodigo(TimeoutException('lento')), contains('internet'));
    expect(mensajeCodigo(const AuthApiException('Invalid TOTP code entered', code: 'mfa_verification_failed')),
        contains('no sirve'));
  });
}
