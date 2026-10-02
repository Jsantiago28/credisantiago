import 'package:flutter/services.dart';

import '../logic/validacion.dart';

/// Pone los guiones de la cédula mientras se escribe (001-1234567-8) y no
/// deja escribir letras ni más de 11 dígitos.
class FormatoCedula extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue viejo, TextEditingValue nuevo) =>
      _conCursorAlFinal(formatearCedula(nuevo.text));
}

/// Pone los guiones del teléfono mientras se escribe (809-555-1234).
class FormatoTelefono extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue viejo, TextEditingValue nuevo) =>
      _conCursorAlFinal(formatearTelefono(nuevo.text));
}

TextEditingValue _conCursorAlFinal(String texto) =>
    TextEditingValue(text: texto, selection: TextSelection.collapsed(offset: texto.length));

/// Solo dígitos (montos en pesos enteros).
final soloNumeros = FilteringTextInputFormatter.digitsOnly;
