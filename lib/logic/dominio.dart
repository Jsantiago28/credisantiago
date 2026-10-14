import 'package:flutter/foundation.dart';

/// Dirección donde está publicada la app, para armar el link de clientes
/// (/s/{slug}). En la web es la misma dirección desde donde se abrió (así
/// sirve igual en localhost y en Netlify, sin cambiar nada). En Android no
/// hay dirección propia: se usa la publicada.
String get kDominioBase => kIsWeb ? Uri.base.origin : kDominioPublicado;

/// Cambiar por la dirección real cuando se publique (Netlify / dominio propio).
const kDominioPublicado = 'https://credisantiago.netlify.app';
