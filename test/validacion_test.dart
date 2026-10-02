import 'package:flutter_test/flutter_test.dart';
import 'package:prestamistas_rd/logic/validacion.dart';

void main() {
  group('Cédula', () {
    test('se forma sola mientras se escribe', () {
      expect(formatearCedula('001'), '001');
      expect(formatearCedula('0011'), '001-1');
      expect(formatearCedula('0011234567'), '001-1234567');
      expect(formatearCedula('00112345678'), '001-1234567-8');
      expect(formatearCedula('001-1234567-8999'), '001-1234567-8'); // no pasa de 11
      expect(formatearCedula('abc001x'), '001');
    });

    test('exige los 11 dígitos', () {
      expect(errorCedula(''), 'Escribe la cédula');
      expect(errorCedula('001-123'), 'La cédula lleva 11 dígitos (tiene 6)');
      expect(errorCedula('001-1234567-8'), isNull);
    });

    test('dígito verificador: detecta un número mal digitado', () {
      // Se arma una cédula válida y se le cambia el último dígito.
      final valida = _cedulaValida('0010000000');
      expect(cedulaDigitoVerificadorOk(valida), isTrue);
      expect(avisoCedula(valida), isNull);
      final ultimo = int.parse(valida[valida.length - 1]);
      final mala = valida.substring(0, valida.length - 1) + '${(ultimo + 1) % 10}';
      expect(cedulaDigitoVerificadorOk(mala), isFalse);
      expect(avisoCedula(mala), 'Revisa la cédula: puede tener un número equivocado');
    });

    test('el aviso no sale si la cédula está incompleta (ahí manda el error)', () {
      expect(avisoCedula('001-123'), isNull);
    });
  });

  group('Teléfono', () {
    test('se forma solo', () {
      expect(formatearTelefono('809'), '809');
      expect(formatearTelefono('809555'), '809-555');
      expect(formatearTelefono('8095551234'), '809-555-1234');
      expect(formatearTelefono('+1 809 555 1234'), '809-555-1234');
      expect(formatearTelefono('80955512345'), '809-555-1234');
    });

    test('10 dígitos de RD', () {
      expect(errorTelefono('809-555-1234'), isNull);
      expect(errorTelefono('829 555 1234'), isNull);
      expect(errorTelefono('+1 849-555-1234'), isNull);
      expect(errorTelefono('809-555'), 'El teléfono lleva 10 dígitos (ej. 809-555-1234)');
      expect(errorTelefono('305-555-1234'), 'Debe empezar con 809, 829 u 849');
      expect(errorTelefono(''), 'Escribe el teléfono');
      expect(errorTelefono('', obligatorio: false), isNull);
    });
  });

  group('Nombre y montos', () {
    test('nombre y apellido, sin números', () {
      expect(errorNombre('José Pérez'), isNull);
      expect(errorNombre('José'), 'Escribe nombre y apellido');
      expect(errorNombre('José 2 Pérez'), 'El nombre no lleva números');
      expect(errorNombre('  '), 'Escribe el nombre completo');
    });

    test('montos: solo números y mayor que 0', () {
      expect(errorMonto('25000'), isNull);
      expect(errorMonto('25,000'), isNull);
      expect(errorMonto('25mil'), 'Solo números');
      expect(errorMonto('0'), 'Debe ser mayor que 0');
      expect(errorMonto(''), isNull);
      expect(errorMonto('', obligatorio: true), 'Escribe el monto');
    });
  });

  group('Repetidos', () {
    final clientes = [
      {'id': '1', 'nombre': 'José Martínez', 'cedula': '001-1234567-8', 'telefono': '809-555-1234'},
      {'id': '2', 'nombre': 'María Rosario', 'cedula': '402-7654321-0', 'telefono': '8294449876'},
    ];

    test('misma cédula, aunque se escriba sin guiones', () {
      final r = buscarRepetidos(clientes, cedula: '00112345678');
      expect(r.single.dato, DatoRepetido.cedula);
      expect(r.single.registro['nombre'], 'José Martínez');
    });

    test('mismo teléfono, con o sin guiones o +1', () {
      expect(buscarRepetidos(clientes, telefono: '+1 829-444-9876').single.registro['id'], '2');
    });

    test('mismo nombre completo, sin importar acentos ni mayúsculas', () {
      expect(buscarRepetidos(clientes, nombre: 'jose  MARTINEZ').single.dato, DatoRepetido.nombre);
    });

    test('datos incompletos no cuentan como repetidos', () {
      expect(buscarRepetidos(clientes, cedula: '001', telefono: '809', nombre: 'José'), isEmpty);
    });

    test('varios datos repetidos a la vez', () {
      final r = buscarRepetidos(clientes,
          cedula: '001-1234567-8', telefono: '809-555-1234', nombre: 'José Martínez');
      expect(r.map((x) => x.dato), [DatoRepetido.cedula, DatoRepetido.telefono, DatoRepetido.nombre]);
    });

    test('no se compara consigo mismo', () {
      expect(buscarRepetidos(clientes, cedula: '001-1234567-8', excluirId: '1'), isEmpty);
    });
  });
}

/// Completa 10 dígitos con el dígito verificador correcto (Luhn).
String _cedulaValida(String diez) {
  for (var d = 0; d <= 9; d++) {
    if (cedulaDigitoVerificadorOk('$diez$d')) return '$diez$d';
  }
  throw StateError('no hay dígito válido');
}
