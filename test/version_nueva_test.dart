import 'package:flutter_test/flutter_test.dart';
import 'package:prestamistas_rd/services/version_nueva.dart';

void main() {
  test('compara versiones número por número', () {
    expect(VersionNueva.esMasNueva('1.0.7', '1.0.6'), isTrue);
    expect(VersionNueva.esMasNueva('1.0.10', '1.0.9'), isTrue); // no es texto
    expect(VersionNueva.esMasNueva('1.1.0', '1.0.9'), isTrue);
    expect(VersionNueva.esMasNueva('1.0.6', '1.0.6'), isFalse);
    expect(VersionNueva.esMasNueva('1.0.5', '1.0.6'), isFalse);
    expect(VersionNueva.esMasNueva('1.0.7+8', '1.0.6'), isTrue);
    expect(VersionNueva.esMasNueva('', '1.0.6'), isFalse);
  });
}
