import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

// Impresora en la app de Android: se imprime con la app RawBT (gratis en
// Google Play), que funciona con casi cualquier impresora Bluetooth. El
// Bluetooth directo (BLE) es solo de la versión web en Chrome.

const _paqueteRawBT = 'ru.a402d.rawbtprinter';
const _clavePapel = 'papel_impresora';

/// En la app no hay Bluetooth directo: se usa RawBT.
bool bluetoothDisponible() => false;

Future<void> imprimirBluetooth(String base64) async =>
    throw UnsupportedError('En la app se imprime con RawBT');

/// Le pasa el ticket a RawBT. Si no está instalada, abre su página en
/// Google Play para instalarla.
void imprimirRawBT(String base64) {
  _imprimirRawBT(base64);
}

Future<void> _imprimirRawBT(String base64) async {
  final abrio = await launchUrl(Uri.parse('rawbt:base64,$base64'),
      mode: LaunchMode.externalApplication);
  if (!abrio) {
    await launchUrl(
      Uri.https('play.google.com', '/store/apps/details', {'id': _paqueteRawBT}),
      mode: LaunchMode.externalApplication,
    );
  }
}

/// En la app no hay impresora "conectada" que olvidar: RawBT la recuerda.
void olvidarImpresora() {}

int _papel = 58;
bool _papelLeido = false;

/// Papel de este teléfono: 58 u 80 mm. Se lee una vez del teléfono; hasta
/// entonces vale 58.
int papelImpresora() {
  if (!_papelLeido) {
    _papelLeido = true;
    SharedPreferences.getInstance()
        .then((p) => _papel = p.getInt(_clavePapel) ?? _papel)
        .catchError((_) => _papel);
  }
  return _papel;
}

void guardarPapelImpresora(int mm) {
  _papel = mm;
  SharedPreferences.getInstance().then((p) => p.setInt(_clavePapel, mm)).catchError((_) => false);
}
