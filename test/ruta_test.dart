import 'package:flutter_test/flutter_test.dart';
import 'package:prestamistas_rd/logic/ruta.dart';

// Lugares de Santo Domingo (aproximados).
const zonaColonial = (lat: 18.4730, lng: -69.8840);
const naco = (lat: 18.4760, lng: -69.9300);
const piantini = (lat: 18.4700, lng: -69.9380);
const losAlcarrizos = (lat: 18.5250, lng: -70.0150);
const santiago = (lat: 19.4517, lng: -70.6970);

void main() {
  test('distancia en km', () {
    expect(distanciaKm(zonaColonial, zonaColonial), 0);
    expect(distanciaKm(zonaColonial, naco), closeTo(4.9, 0.3));
    // SD → Santiago: ~138 km en línea recta (por carretera son ~155).
    expect(distanciaKm(zonaColonial, santiago), closeTo(138, 5));
  });

  test('punto desde lo guardado: sin datos o en 0,0 no cuenta', () {
    expect(puntoDe(18.47, -69.88), (lat: 18.47, lng: -69.88));
    expect(puntoDe(null, -69.88), isNull);
    expect(puntoDe(0, 0), isNull);
  });

  test('ordena de la más cercana a la más lejana desde donde estás', () {
    final paradas = [losAlcarrizos, zonaColonial, piantini, naco];
    final orden = ordenarRuta(paradas, (p) => p, inicio: zonaColonial);
    expect(orden, [zonaColonial, naco, piantini, losAlcarrizos]);
  });

  test('la ruta ordenada es más corta que en el orden de la lista', () {
    final paradas = [losAlcarrizos, zonaColonial, piantini, naco];
    final orden = ordenarRuta(paradas, (p) => p, inicio: zonaColonial);
    expect(largoRutaKm(orden, inicio: zonaColonial),
        lessThan(largoRutaKm(paradas, inicio: zonaColonial)));
  });

  test('sin punto de inicio empieza por la primera parada', () {
    final orden = ordenarRuta([piantini, losAlcarrizos, naco], (p) => p);
    expect(orden.first, piantini);
    expect(orden, [piantini, naco, losAlcarrizos]);
  });

  test('ordena cualquier cosa que tenga ubicación', () {
    final clientes = [
      {'nombre': 'Lejos', 'p': losAlcarrizos},
      {'nombre': 'Cerca', 'p': naco},
    ];
    final orden = ordenarRuta(clientes, (c) => c['p'] as Punto, inicio: zonaColonial);
    expect(orden.map((c) => c['nombre']), ['Cerca', 'Lejos']);
  });

  test('enlace "cómo llegar" de Google Maps', () {
    final uri = enlaceComoLlegar(naco);
    expect(uri.host, 'www.google.com');
    expect(uri.queryParameters['destination'], '18.476000,-69.930000');
    expect(uri.queryParameters['api'], '1');
  });

  test('enlace de ruta: última parada es el destino, las demás en medio', () {
    final uri = enlaceRuta([naco, piantini, losAlcarrizos], origen: zonaColonial);
    expect(uri.queryParameters['origin'], '18.473000,-69.884000');
    expect(uri.queryParameters['destination'], '18.525000,-70.015000');
    expect(uri.queryParameters['waypoints'], '18.476000,-69.930000|18.470000,-69.938000');
  });

  test('más de 10 paradas: el enlace lleva las primeras 10', () {
    final muchas = List.generate(15, (i) => (lat: 18.4 + i / 100, lng: -69.9));
    final uri = enlaceRuta(muchas);
    expect(uri.queryParameters['waypoints']!.split('|').length, 9);
    expect(uri.queryParameters.containsKey('origin'), isFalse);
  });

  test('una sola parada: sin paradas intermedias', () {
    final uri = enlaceRuta([naco]);
    expect(uri.queryParameters.containsKey('waypoints'), isFalse);
  });
}
