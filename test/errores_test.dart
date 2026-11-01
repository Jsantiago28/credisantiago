import 'package:flutter_test/flutter_test.dart';
import 'package:prestamistas_rd/logic/calculo_prestamo.dart';
import 'package:prestamistas_rd/services/errores.dart';
import 'package:prestamistas_rd/services/supabase_service.dart';

void main() {
  test('al usuario no se le muestra el error técnico', () {
    expect(mensajeError(Exception('SocketException: Failed host lookup')),
        'Sin internet. Intenta de nuevo.');
    expect(mensajeError(Exception('PostgrestException(message: permission denied)')),
        'Algo salió mal. Intenta de nuevo.');
    // Los que la app conoce traen su mensaje claro.
    expect(mensajeError(const SaldoCambio(10350)),
        'El saldo cambió: ahora son RD\$10350. Vuelve a abrir Saldar.');
    expect(mensajeError(const ClienteRepetido('Ana')), contains('Ana'));
    expect(mensajeError(StateError('Tiene 2 cobro(s). Anúlalos primero.')),
        'Tiene 2 cobro(s). Anúlalos primero.');
  });

  test('las cuotas que no son mensuales caen en el día del calendario', () {
    expect(fechaCuota(DateTime(2026, 3, 1), 'diario', 10), DateTime(2026, 3, 11));
    expect(fechaCuota(DateTime(2026, 12, 28), 'semanal', 1), DateTime(2027, 1, 4));
    expect(fechaCuota(DateTime(2026, 1, 31), 'quincenal', 2), DateTime(2026, 3, 2));
  });
}
