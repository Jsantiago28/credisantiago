import 'package:flutter_test/flutter_test.dart';
import 'package:prestamistas_rd/logic/busqueda.dart';

final clientes = [
  {'nombre': 'José Martínez Peña', 'cedula': '001-1234567-8', 'telefono': '809-555-1234'},
  {'nombre': 'María Rosario', 'cedula': '402-7654321-0', 'telefono': '829-444-9876'},
  {'nombre': 'Josefina Núñez', 'cedula': '003-1111111-1', 'telefono': '849-333-0000'},
  {'nombre': 'Luis Guzmán', 'cedula': '001-2222222-2', 'telefono': '809-222-1111'},
];

List<String> nombres(String texto) =>
    buscarClientes(clientes, texto).map((c) => c['nombre'] as String).toList();

void main() {
  test('con una letra ya sugiere, sin importar mayúsculas', () {
    expect(nombres('j'), ['José Martínez Peña', 'Josefina Núñez']);
    expect(nombres('M'), contains('María Rosario'));
  });

  test('sin acentos encuentra con acentos', () {
    expect(nombres('jose'), ['José Martínez Peña', 'Josefina Núñez']);
    expect(nombres('nunez'), ['Josefina Núñez']);
    expect(nombres('guzman'), ['Luis Guzmán']);
  });

  test('por apellido o varias palabras', () {
    expect(nombres('rosario'), ['María Rosario']);
    expect(nombres('jo pe'), ['José Martínez Peña']);
    expect(nombres('jose martinez'), ['José Martínez Peña']);
  });

  test('primero los que empiezan igual', () {
    // "ma" empieza "María"; "José Martínez" solo lo tiene en el apellido.
    expect(nombres('ma'), ['María Rosario', 'José Martínez Peña']);
  });

  test('por cédula o teléfono, con o sin guiones', () {
    expect(nombres('0011234567'), ['José Martínez Peña']);
    expect(nombres('402-765'), ['María Rosario']);
    expect(nombres('8493330000'), ['Josefina Núñez']);
    expect(nombres('222'), ['Luis Guzmán']);
  });

  test('menos de 3 dígitos no busca por número', () {
    expect(nombres('00'), isEmpty);
  });

  test('vacío o sin coincidencias no sugiere nada', () {
    expect(nombres(''), isEmpty);
    expect(nombres('   '), isEmpty);
    expect(nombres('pedro'), isEmpty);
  });

  test('respeta el máximo de sugerencias', () {
    expect(buscarClientes(clientes, 'a', maximo: 2).length, lessThanOrEqualTo(2));
  });
}
