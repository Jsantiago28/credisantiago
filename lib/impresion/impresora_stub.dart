/// Si este navegador puede conectarse directo a una impresora BLE.
bool bluetoothDisponible() => false;

/// Manda el ticket (bytes ESC/POS en base64) a la impresora BLE.
Future<void> imprimirBluetooth(String base64) async =>
    throw UnsupportedError('Aquí no hay Bluetooth');

/// Le pasa el ticket a la app RawBT de Android.
void imprimirRawBT(String base64) => throw UnsupportedError('RawBT solo funciona en Android');

/// Olvida la impresora conectada (para elegir otra).
void olvidarImpresora() {}

/// Papel de este teléfono: 58 u 80 mm.
int papelImpresora() => 58;
void guardarPapelImpresora(int mm) {}
