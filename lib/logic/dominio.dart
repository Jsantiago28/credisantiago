import 'package:flutter/foundation.dart';

/// Dirección donde está publicada la app, para armar el link de clientes
/// (/s/{slug}). En la web es la misma dirección desde donde se abrió (así
/// sirve igual en localhost y en Cloudflare, sin cambiar nada). En Android no
/// hay dirección propia: se usa la publicada.
String get kDominioBase => kIsWeb ? Uri.base.origin : kDominioPublicado;

/// Dónde está publicada (Cloudflare Pages). Cambiar si algún día hay dominio propio.
const kDominioPublicado = 'https://credisantiago.pages.dev';
