/// Cómo se puede poner la app en la pantalla de inicio.
enum Instalacion {
  /// Ya se abre como app (o es el APK, o una computadora): nada que ofrecer.
  instalada,

  /// El navegador la instala con un botón (Chrome, Edge, Samsung, Brave).
  conBoton,

  /// iPhone o iPad: Compartir → Agregar a pantalla de inicio.
  iphone,

  /// Celular Android sin botón (otro navegador): desde el menú.
  menuDelNavegador,
}

Instalacion estadoInstalacion() => Instalacion.instalada;

/// Muestra el aviso del navegador para instalarla. true si la instaló.
Future<bool> instalarApp() async => false;

/// Avisa cuando cambia (el navegador avisa que se puede instalar tarde).
void alCambiarInstalacion(void Function() alCambiar) {}
