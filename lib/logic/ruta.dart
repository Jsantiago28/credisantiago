import 'dart:math';

/// Ruta de cobro: distancias, orden de las paradas y enlaces a Google Maps.

/// Un lugar en el mapa.
typedef Punto = ({double lat, double lng});

/// Punto a partir de lat/lng guardados (null si falta alguno o son 0,0).
Punto? puntoDe(dynamic lat, dynamic lng) {
  final a = (lat as num?)?.toDouble();
  final b = (lng as num?)?.toDouble();
  if (a == null || b == null || (a == 0 && b == 0)) return null;
  return (lat: a, lng: b);
}

/// Distancia en línea recta en km (fórmula de haversine).
double distanciaKm(Punto a, Punto b) {
  const radioTierra = 6371.0;
  double rad(double g) => g * pi / 180;
  final dLat = rad(b.lat - a.lat);
  final dLng = rad(b.lng - a.lng);
  final h = sin(dLat / 2) * sin(dLat / 2) +
      cos(rad(a.lat)) * cos(rad(b.lat)) * sin(dLng / 2) * sin(dLng / 2);
  return 2 * radioTierra * asin(sqrt(h));
}

/// Ordena las paradas: desde `inicio`, siempre a la más cercana que falte.
/// No es la ruta perfecta, pero para 10–30 paradas en la ciudad sale muy
/// parecida y se calcula al instante. Sin `inicio`, empieza por la primera.
List<T> ordenarRuta<T>(List<T> paradas, Punto Function(T) ubicacion, {Punto? inicio}) {
  final quedan = [...paradas];
  final orden = <T>[];
  var actual = inicio;
  while (quedan.isNotEmpty) {
    var mejor = 0;
    if (actual != null) {
      var menor = double.infinity;
      for (var i = 0; i < quedan.length; i++) {
        final d = distanciaKm(actual, ubicacion(quedan[i]));
        if (d < menor) {
          menor = d;
          mejor = i;
        }
      }
    }
    final siguiente = quedan.removeAt(mejor);
    orden.add(siguiente);
    actual = ubicacion(siguiente);
  }
  return orden;
}

/// Kilómetros de la ruta en línea recta (desde `inicio` si se da).
double largoRutaKm(List<Punto> puntos, {Punto? inicio}) {
  var total = 0.0;
  var anterior = inicio;
  for (final p in puntos) {
    if (anterior != null) total += distanciaKm(anterior, p);
    anterior = p;
  }
  return total;
}

String _coord(Punto p) => '${p.lat.toStringAsFixed(6)},${p.lng.toStringAsFixed(6)}';

/// Google Maps con la navegación hasta un punto.
Uri enlaceComoLlegar(Punto destino) => Uri.https('www.google.com', '/maps/dir/', {
      'api': '1',
      'destination': _coord(destino),
      'travelmode': 'driving',
    });

/// Google Maps con la ruta completa (en orden). Google acepta hasta 9
/// paradas intermedias: si son más, se abren las primeras 10 y el resto
/// queda para un segundo tramo. Sin `origen`, Google usa la ubicación del
/// teléfono.
Uri enlaceRuta(List<Punto> paradas, {Punto? origen}) {
  if (paradas.isEmpty) throw ArgumentError('No hay paradas');
  final tramo = paradas.take(10).toList();
  return Uri.https('www.google.com', '/maps/dir/', {
    'api': '1',
    if (origen != null) 'origin': _coord(origen),
    'destination': _coord(tramo.last),
    if (tramo.length > 1) 'waypoints': tramo.take(tramo.length - 1).map(_coord).join('|'),
    'travelmode': 'driving',
  });
}
