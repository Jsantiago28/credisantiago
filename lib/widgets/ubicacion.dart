import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';

import '../logic/ruta.dart';

/// Dónde está el teléfono ahora, o null (con un aviso) si no se puede:
/// sin permiso, GPS apagado o el navegador no lo permite.
Future<Punto?> miUbicacion(BuildContext context) async {
  final mensajero = ScaffoldMessenger.of(context);
  void avisar(String t) => mensajero.showSnackBar(SnackBar(content: Text(t)));
  try {
    if (!await Geolocator.isLocationServiceEnabled()) {
      avisar('La ubicación del teléfono está apagada. Actívala e intenta otra vez.');
      return null;
    }
    var permiso = await Geolocator.checkPermission();
    if (permiso == LocationPermission.denied) permiso = await Geolocator.requestPermission();
    if (permiso == LocationPermission.denied || permiso == LocationPermission.deniedForever) {
      avisar('Sin permiso de ubicación. Actívalo en los ajustes del navegador o del teléfono.');
      return null;
    }
    final pos = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
      timeLimit: const Duration(seconds: 20),
    );
    return (lat: pos.latitude, lng: pos.longitude);
  } catch (e) {
    // ignore: avoid_print
    print('ERROR REAL UBICACION: $e');
    avisar('No se pudo obtener la ubicación: $e');
    return null;
  }
}

/// Abre Google Maps (app o web) en el enlace dado.
Future<void> abrirMapa(BuildContext context, Uri enlace) async {
  final mensajero = ScaffoldMessenger.of(context);
  if (!await launchUrl(enlace, mode: LaunchMode.externalApplication)) {
    mensajero.showSnackBar(const SnackBar(content: Text('No se pudo abrir Google Maps.')));
  }
}
