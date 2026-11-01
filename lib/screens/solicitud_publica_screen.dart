import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart' show ImageSource;
import '../widgets/elegir_foto.dart';
import '../logic/borrador_solicitud.dart';
import '../logic/validacion.dart';
import '../logic/whatsapp.dart';
import '../services/errores.dart';
import '../services/supabase_service.dart';
import '../theme/app_theme.dart';
import '../widgets/evidencias.dart';
import '../widgets/formato_campos.dart';
import '../widgets/legal.dart';

/// Pantalla pública: prestamistacalle.com/s/{slug}
/// El cliente NO necesita login. Llena 5 pasos y envía. Las fotos van de
/// último: cuando ya escribió sus datos confía más y es menos probable que
/// abandone.
class SolicitudPublicaScreen extends StatefulWidget {
  final String slug;

  /// Para las pruebas: en qué paso abre (0 = el primero).
  @visibleForTesting
  final int pasoInicial;
  const SolicitudPublicaScreen({super.key, required this.slug, this.pasoInicial = 0});

  @override
  State<SolicitudPublicaScreen> createState() => _SolicitudPublicaScreenState();
}

// Cada paso del formulario.
const _fotos = 0, _datos = 1, _trabajo = 2, _referencias = 3, _pago = 4;

/// Orden en que el cliente llena los pasos.
const _orden = [_datos, _trabajo, _referencias, _pago, _fotos];
const _nombresPasos = {
  _fotos: 'Fotos',
  _datos: 'Datos',
  _trabajo: 'Trabajo',
  _referencias: 'Referencias',
  _pago: 'Pago',
};

class _SolicitudPublicaScreenState extends State<SolicitudPublicaScreen> {
  /// Posición en [_orden] (0 = el primer paso que ve el cliente).
  late int _paso = widget.pasoInicial;

  /// Qué paso es el que se ve ahora.
  int get _pasoId => _orden[_paso];
  bool _enviando = false;
  bool _enviado = false;
  Map<String, dynamic>? _prestamista;

  /// El logo del negocio del prestamista (null si no tiene o no cargó).
  Uint8List? _logo;

  /// Autorizó el uso de sus datos (casilla del último paso).
  bool _autorizaDatos = false;

  // Paso 1: fotos — guardamos los bytes (no el File, que no funciona en web)
  Uint8List? _fotoCaraBytes;
  Uint8List? _fotoCedulaFrenteBytes;
  Uint8List? _fotoCedulaReversoBytes;

  // Paso 2: datos personales
  final _nombreCtrl = TextEditingController();
  final _cedulaCtrl = TextEditingController();
  final _telefonoCtrl = TextEditingController();
  final _direccionCtrl = TextEditingController();
  double? _lat;
  double? _lng;
  String? _tipoVivienda; // propia / alquilada

  // Paso 3: trabajo
  final _trabajoLugarCtrl = TextEditingController();
  final _trabajoDireccionCtrl = TextEditingController();
  final _jefeNombreCtrl = TextEditingController();
  final _jefeTelefonoCtrl = TextEditingController();
  final _ingresoMensualCtrl = TextEditingController();
  bool _tieneOtrosIngresos = false;
  final _otrosIngresosDescripcionCtrl = TextEditingController();
  final _otrosIngresosMontoCtrl = TextEditingController();
  List<Uint8List> _evidencias = [];

  /// El prestamista exige evidencia de ingresos (lo elige en su Perfil).
  bool get _exigeEvidencias => _prestamista?['exigir_evidencias'] == true;

  // Paso 4: referencias
  final _ref1NombreCtrl = TextEditingController();
  final _ref1ParentescoCtrl = TextEditingController();
  final _ref1TelefonoCtrl = TextEditingController();
  final _ref2NombreCtrl = TextEditingController();
  final _ref2ParentescoCtrl = TextEditingController();
  final _ref2TelefonoCtrl = TextEditingController();

  // Paso 5: monto, capacidad de pago y cómo quiere el dinero (opcional)
  final _montoCtrl = TextEditingController();
  String _frecuenciaPago = 'semanal'; // diario / semanal
  final _capacidadPagoCtrl = TextEditingController();

  String _metodoCobro = 'sin_definir';
  String? _banco;
  final _numeroCuentaCtrl = TextEditingController();
  String? _billetera;

  @override
  void initState() {
    super.initState();
    _cargarPrestamista();
    for (final c in _camposTexto.values) {
      c.addListener(_guardarBorrador);
    }
    _restaurarBorrador();
  }

  // -------------------------------------------------------------------------
  // BORRADOR: lo escrito se guarda en el navegador por si la página se
  // recarga (pasa en Chrome de Android al abrir la cámara). Las fotos no.
  // -------------------------------------------------------------------------

  /// Se recuperó lo que había escrito (muestra el aviso).
  bool _recuperado = false;

  /// Mientras se ponen los datos recuperados no se vuelve a guardar.
  bool _restaurando = false;

  /// Cambia al recuperar o borrar el borrador, para que los campos con
  /// valor inicial (los de banco y billetera) se vuelvan a dibujar.
  int _versionBorrador = 0;

  /// Los campos de texto del formulario, por nombre (así se guardan).
  late final Map<String, TextEditingController> _camposTexto = {
    'nombre': _nombreCtrl,
    'cedula': _cedulaCtrl,
    'telefono': _telefonoCtrl,
    'direccion': _direccionCtrl,
    'trabajo_lugar': _trabajoLugarCtrl,
    'trabajo_direccion': _trabajoDireccionCtrl,
    'jefe_nombre': _jefeNombreCtrl,
    'jefe_telefono': _jefeTelefonoCtrl,
    'ingreso_mensual': _ingresoMensualCtrl,
    'otros_ingresos_descripcion': _otrosIngresosDescripcionCtrl,
    'otros_ingresos_monto': _otrosIngresosMontoCtrl,
    'ref1_nombre': _ref1NombreCtrl,
    'ref1_parentesco': _ref1ParentescoCtrl,
    'ref1_telefono': _ref1TelefonoCtrl,
    'ref2_nombre': _ref2NombreCtrl,
    'ref2_parentesco': _ref2ParentescoCtrl,
    'ref2_telefono': _ref2TelefonoCtrl,
    'monto': _montoCtrl,
    'capacidad_pago': _capacidadPagoCtrl,
    'numero_cuenta': _numeroCuentaCtrl,
  };

  void _guardarBorrador() {
    if (_restaurando || _enviando || _enviado) return;
    guardarBorradorSolicitud(
      widget.slug,
      BorradorSolicitud(
        textos: {for (final e in _camposTexto.entries) e.key: e.value.text},
        opciones: {
          'tipo_vivienda': _tipoVivienda,
          'lat': _lat,
          'lng': _lng,
          'tiene_otros_ingresos': _tieneOtrosIngresos,
          'frecuencia_pago': _frecuenciaPago,
          'metodo_cobro': _metodoCobro,
          'banco': _banco,
          'billetera': _billetera,
        },
        paso: _paso,
        guardado: DateTime.now(),
      ),
    );
  }

  /// Cambia una opción (no un texto) y guarda el borrador.
  void _elegir(VoidCallback cambio) {
    setState(cambio);
    _guardarBorrador();
  }

  Future<void> _restaurarBorrador() async {
    final b = await leerBorradorSolicitud(widget.slug);
    // Si ya empezó a escribir mientras se leía, no se le pisa.
    if (b == null || !mounted || _camposTexto.values.any((c) => c.text.isNotEmpty)) return;
    T? opcion<T>(String clave) => b.opciones[clave] is T ? b.opciones[clave] as T : null;
    _restaurando = true;
    setState(() {
      for (final e in _camposTexto.entries) {
        e.value.text = b.textos[e.key] ?? '';
      }
      _tipoVivienda = opcion<String>('tipo_vivienda');
      _lat = opcion<num>('lat')?.toDouble();
      _lng = opcion<num>('lng')?.toDouble();
      _tieneOtrosIngresos = opcion<bool>('tiene_otros_ingresos') ?? false;
      _frecuenciaPago = opcion<String>('frecuencia_pago') ?? _frecuenciaPago;
      _metodoCobro = opcion<String>('metodo_cobro') ?? _metodoCobro;
      _banco = opcion<String>('banco');
      _billetera = opcion<String>('billetera');
      _paso = b.paso.clamp(0, _orden.length - 1);
      _recuperado = true;
      _versionBorrador++;
    });
    _restaurando = false;
  }

  /// "Borrar y empezar de nuevo": deja el formulario en blanco.
  void _empezarDeNuevo() {
    _restaurando = true;
    setState(() {
      for (final c in _camposTexto.values) {
        c.clear();
      }
      _tipoVivienda = null;
      _lat = null;
      _lng = null;
      _tieneOtrosIngresos = false;
      _frecuenciaPago = 'semanal';
      _metodoCobro = 'sin_definir';
      _banco = null;
      _billetera = null;
      _evidencias = [];
      _fotoCaraBytes = _fotoCedulaFrenteBytes = _fotoCedulaReversoBytes = null;
      _autorizaDatos = false;
      _mostrarErrores = false;
      _paso = 0;
      _recuperado = false;
      _versionBorrador++;
    });
    _restaurando = false;
    borrarBorradorSolicitud(widget.slug);
  }

  Future<void> _cargarPrestamista() async {
    try {
      final servicio = SupabaseService.instance;
      final p = await Future.sync(() => servicio.obtenerPerfilPorSlug(widget.slug));
      if (mounted) setState(() => _prestamista = p);
      // El logo del prestamista (si subió uno): se ve sin sesión.
      final logo = await servicio.bajarFoto(p?['logo'] as String?);
      if (mounted && logo != null) setState(() => _logo = logo);
    } catch (e) {
      registrarError(e, null, 'CARGAR PRESTAMISTA'); // al enviar se avisa que el link no sirve
    }
  }

  /// Pide la foto con la cámara (directo, también en Chrome de Android) o de
  /// la galería, y avisa si algo falla. [frontal]: la cámara de adelante.
  Future<void> _tomarFoto({
    required ImageSource origen,
    bool frontal = false,
    required void Function(Uint8List bytes) onTomada,
  }) async {
    final bytes = await elegirFoto(context, origen: origen, frontal: frontal);
    if (bytes != null && mounted) setState(() => onTomada(bytes));
  }

  Future<void> _capturarUbicacion() async {
    try {
      final permiso = await Geolocator.requestPermission();
      if (permiso == LocationPermission.denied) return;
      final pos = await Geolocator.getCurrentPosition();
      if (!mounted) return;
      _elegir(() {
        _lat = pos.latitude;
        _lng = pos.longitude;
      });
    } catch (_) {
      // Si el cliente no da permiso, continúa sin GPS.
    }
  }

  bool get _paso1Valido =>
      _fotoCaraBytes != null && _fotoCedulaFrenteBytes != null && _fotoCedulaReversoBytes != null;

  /// Se marcan en rojo los datos mal puestos después de tocar Continuar.
  bool _mostrarErrores = false;

  /// Errores de los datos del paso (null = bien).
  List<String?> _erroresDelPaso(int paso) => switch (paso) {
        1 => [
            errorNombre(_nombreCtrl.text),
            errorCedula(_cedulaCtrl.text),
            errorTelefono(_telefonoCtrl.text),
          ],
        2 => [
            errorTelefono(_jefeTelefonoCtrl.text, obligatorio: false),
            errorMonto(_ingresoMensualCtrl.text),
            if (_tieneOtrosIngresos) errorMonto(_otrosIngresosMontoCtrl.text),
          ],
        3 => [
            errorTelefono(_ref1TelefonoCtrl.text, obligatorio: false),
            errorTelefono(_ref2TelefonoCtrl.text, obligatorio: false),
          ],
        4 => [errorMonto(_montoCtrl.text), errorMonto(_capacidadPagoCtrl.text)],
        _ => const [],
      };

  void _siguiente() {
    if (_pasoId == _fotos && !_paso1Valido) {
      _mostrarError('Toma las 3 fotos para enviar tu solicitud');
      return;
    }
    if (_pasoId == _fotos && !_autorizaDatos) {
      _mostrarError('Marca la casilla para autorizar el uso de tus datos');
      return;
    }
    if (_erroresDelPaso(_pasoId).any((e) => e != null)) {
      setState(() => _mostrarErrores = true);
      _mostrarError('Revisa los datos marcados en rojo');
      return;
    }
    _mostrarErrores = false;
    if (_pasoId == _trabajo && _exigeEvidencias && _evidencias.isEmpty) {
      _mostrarError('Sube al menos una foto de evidencia de tus ingresos');
      return;
    }
    // Las evidencias no se guardan en el borrador: si se recuperó lo
    // escrito, puede que falten al llegar al final.
    if (_paso == 4 && _exigeEvidencias && _evidencias.isEmpty) {
      setState(() => _paso = _orden.indexOf(_trabajo));
      _mostrarError('Sube al menos una foto de evidencia de tus ingresos');
      return;
    }
    if (_paso < 4) {
      _elegir(() => _paso++);
    } else {
      _enviarSolicitud();
    }
  }

  void _mostrarError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _enviarSolicitud() async {
    final prestamistaId = _prestamista?['id'] as String?;
    if (prestamistaId == null) {
      _mostrarError('Este link no es válido. Pídele el link correcto a tu prestamista.');
      return;
    }
    setState(() => _enviando = true);
    try {
      // Las fotos van a la carpeta privada del prestamista: solo él las ve.
      final servicio = SupabaseService.instance;
      Future<String?> subir(Uint8List? bytes, String tipo) async => bytes == null
          ? null
          : await servicio.subirFoto(bytes: bytes, prestamistaId: prestamistaId, tipo: tipo);
      final urlCara = await subir(_fotoCaraBytes, 'cara');
      final urlFrente = await subir(_fotoCedulaFrenteBytes, 'cedula_f');
      final urlReverso = await subir(_fotoCedulaReversoBytes, 'cedula_r');

      final evidencias = await servicio.subirEvidencias(_evidencias,
          prestamistaId: prestamistaId, prefijo: 'solicitud');

      await SupabaseService.instance.enviarSolicitud({
        'evidencias_ingresos': evidencias,
        'prestamista_id': _prestamista?['id'],
        'foto_cara_url': urlCara,
        'foto_cedula_frente_url': urlFrente,
        'foto_cedula_reverso_url': urlReverso,
        'nombre': _nombreCtrl.text.trim(),
        'cedula': _cedulaCtrl.text.trim(),
        'telefono': _telefonoCtrl.text.trim(),
        'direccion': _direccionCtrl.text.trim(),
        'lat': _lat,
        'lng': _lng,
        'tipo_vivienda': _tipoVivienda,
        'trabajo_lugar': _trabajoLugarCtrl.text.trim(),
        'trabajo_direccion': _trabajoDireccionCtrl.text.trim(),
        'jefe_nombre': _jefeNombreCtrl.text.trim(),
        'jefe_telefono': _jefeTelefonoCtrl.text.trim(),
        'ingreso_mensual': double.tryParse(_ingresoMensualCtrl.text.replaceAll(',', '')),
        'tiene_otros_ingresos': _tieneOtrosIngresos,
        'otros_ingresos_descripcion':
            _tieneOtrosIngresos ? _otrosIngresosDescripcionCtrl.text.trim() : null,
        'otros_ingresos_monto': _tieneOtrosIngresos
            ? double.tryParse(_otrosIngresosMontoCtrl.text.replaceAll(',', ''))
            : null,
        'ref1_nombre': _ref1NombreCtrl.text.trim(),
        'ref1_parentesco': _ref1ParentescoCtrl.text.trim(),
        'ref1_telefono': _ref1TelefonoCtrl.text.trim(),
        'ref2_nombre': _ref2NombreCtrl.text.trim(),
        'ref2_parentesco': _ref2ParentescoCtrl.text.trim(),
        'ref2_telefono': _ref2TelefonoCtrl.text.trim(),
        'metodo_cobro': _metodoCobro,
        'banco': _banco,
        'numero_cuenta':
            _numeroCuentaCtrl.text.trim().isEmpty ? null : _numeroCuentaCtrl.text.trim(),
        'billetera': _billetera,
        'monto_solicitado': double.tryParse(_montoCtrl.text.replaceAll(',', '')),
        'frecuencia_pago': _frecuenciaPago,
        'capacidad_pago': double.tryParse(_capacidadPagoCtrl.text.replaceAll(',', '')),
        'estado': 'nueva',
        'acepto_privacidad_en': DateTime.now().toUtc().toIso8601String(),
      });

      await borrarBorradorSolicitud(widget.slug); // ya se envió: no queda nada guardado
      if (mounted) setState(() => _enviado = true);
    } catch (e) {
      registrarError(e, null, 'SOLICITUD');
      // Freno contra solicitudes repetidas (migracion_2026_10_18_seguridad.sql).
      final repetida = '$e'.contains('DEMASIADAS_SOLICITUDES');
      _mostrarError(repetida
          ? 'Ya recibimos tu solicitud. Si necesitas cambiar algo, escríbele al prestamista.'
          : 'No pudimos enviar tu solicitud. Intenta de nuevo.');
    } finally {
      setState(() => _enviando = false);
    }
  }

  // -------------------------------------------------------------------------
  // DISEÑO (solo presentación; la lógica de pasos y envío está arriba)
  // -------------------------------------------------------------------------

  static const _azul = Color(0xFF1565C0);
  static const _azulOscuro = Color(0xFF0B1F4B);
  static const _azulClaro = Color(0xFFF1F5FF);
  static const _verde = Color(0xFF15803D); // el verde que se lee al sol
  static const _gris = Color(0xFF9AA3B2);

  String get _negocio {
    final p = _prestamista;
    if (p == null) return 'tu prestamista';
    final negocio = p['negocio'] as String?;
    return negocio != null && negocio.trim().isNotEmpty ? negocio : (p['nombre'] as String? ?? '');
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: AppTheme.formulario(),
      child: Scaffold(
        backgroundColor: const Color(0xFFF7F8FA),
        body: SafeArea(
          child: Center(
            // En la computadora queda del ancho de un teléfono; en el
            // teléfono ocupa todo el ancho.
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Container(
                color: Colors.white,
                child: _enviado ? _buildConfirmacion() : _buildFormulario(),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildConfirmacion() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.check_circle, color: _verde, size: 80),
            const SizedBox(height: 16),
            const Text('¡Solicitud enviada!',
                style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: _azulOscuro)),
            const SizedBox(height: 8),
            Text(
              '$_negocio va a revisar tu solicitud y te contactará pronto.',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 32),
            _sello(),
          ],
        ),
      ),
    );
  }

  Widget _buildFormulario() {
    final pasos = [for (final id in _orden) _nombresPasos[id]!];
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _encabezado(),
          const SizedBox(height: 16),
          _buildStepper(pasos),
          if (_recuperado) ...[
            const SizedBox(height: 16),
            _avisoRecuperado(),
          ],
          const Divider(height: 40),
          KeyedSubtree(key: ValueKey(_versionBorrador), child: _buildPasoActual()),
          const SizedBox(height: 24),
          SizedBox(
            height: 58,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: _azul,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                textStyle: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
              ),
              onPressed: _enviando ? null : _siguiente,
              child: _enviando
                  ? const SizedBox(
                      height: 22,
                      width: 22,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : Text(_paso == 4 ? 'Enviar solicitud' : 'Continuar'),
            ),
          ),
          const SizedBox(height: 20),
          _sello(),
          const SizedBox(height: 16),
          _pie(),
        ],
      ),
    );
  }

  /// Aviso de que se recuperó lo escrito, con la opción de empezar de nuevo.
  Widget _avisoRecuperado() {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
      decoration: BoxDecoration(
        color: const Color(0xFFE8F7EE),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFB7E4C7)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.restore_rounded, color: _verde),
              SizedBox(width: 10),
              Expanded(
                child: Text('Recuperamos lo que habías escrito',
                    style: TextStyle(fontWeight: FontWeight.w700, color: _azulOscuro)),
              ),
            ],
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: _empezarDeNuevo,
              child: const Text('Borrar y empezar de nuevo'),
            ),
          ),
        ],
      ),
    );
  }

  /// "Solicitud a …" con flecha para volver al paso anterior.
  Widget _encabezado() {
    return Row(
      children: [
        SizedBox(
          width: 48,
          child: _paso > 0
              ? IconButton(
                  tooltip: 'Paso anterior',
                  icon: const Icon(Icons.arrow_back, color: _azul, size: 32),
                  onPressed: () => _elegir(() {
                    _paso--;
                    _mostrarErrores = false;
                  }),
                )
              : null,
        ),
        const SizedBox(width: 8),
        if (_logo != null) ...[
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.memory(_logo!, width: 52, height: 52, fit: BoxFit.contain),
          ),
          const SizedBox(width: 12),
        ],
        Expanded(
          child: Text(
            _prestamista == null ? 'Solicitud de préstamo' : 'Solicitud a $_negocio',
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: _azulOscuro),
          ),
        ),
      ],
    );
  }

  /// Pasos conectados: terminados en verde con ✓, el actual con borde azul,
  /// los que faltan en gris.
  Widget _buildStepper(List<String> pasos) {
    Widget circulo(int i) {
      final hecho = i < _paso;
      final actual = i == _paso;
      return Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: hecho ? _verde : Colors.white,
          border: Border.all(
            color: hecho ? _verde : (actual ? _azul : _gris),
            width: actual ? 3 : 2,
          ),
        ),
        alignment: Alignment.center,
        child: hecho
            ? const Icon(Icons.check, color: Colors.white, size: 26)
            : Text('${i + 1}',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: actual ? _azul : _gris,
                )),
      );
    }

    return Column(
      children: [
        Row(
          children: [
            for (var i = 0; i < pasos.length; i++) ...[
              circulo(i),
              if (i < pasos.length - 1)
                Expanded(
                  child: Container(
                    height: 3,
                    color: i < _paso ? _azul : const Color(0xFFE0E4EA),
                  ),
                ),
            ],
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            for (var i = 0; i < pasos.length; i++)
              Expanded(
                child: Text(
                  '${i + 1} ${pasos[i]}',
                  textAlign: i == 0
                      ? TextAlign.left
                      : (i == pasos.length - 1 ? TextAlign.right : TextAlign.center),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: i <= _paso ? FontWeight.w700 : FontWeight.w500,
                    color: i < _paso ? _verde : (i == _paso ? _azulOscuro : _gris),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }

  /// Título grande de cada paso.
  Widget _encabezadoPaso(String titulo, String descripcion) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Paso ${_paso + 1} de ${_orden.length} - ${_nombresPasos[_pasoId]}',
              style: const TextStyle(
                  fontSize: 30, fontWeight: FontWeight.w900, color: _azulOscuro, height: 1.1)),
          Text(titulo,
              style: const TextStyle(
                  fontSize: 30, fontWeight: FontWeight.w900, color: _azulOscuro, height: 1.1)),
          const SizedBox(height: 6),
          Text(descripcion, style: const TextStyle(fontSize: 16, color: Color(0xFF333A45))),
        ],
      ),
    );
  }

  /// Sello de privacidad. Dice solo lo que es cierto: la conexión va
  /// cifrada y las fotos están en un almacenamiento privado del prestamista.
  Widget _sello() {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFFE8F7EE),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: const Color(0xFFB7E4C7)),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.lock_rounded, color: _verde, size: 20),
              SizedBox(width: 8),
              Flexible(
                child: Text('Datos seguros y privados',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: _verde, fontWeight: FontWeight.w800, fontSize: 16)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Tus fotos y datos viajan cifrados y solo los ve $_negocio.',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 13, color: Color(0xFF333A45)),
        ),
      ],
    );
  }

  /// Nombre del negocio y, si tiene teléfono, soporte por WhatsApp.
  Widget _pie() {
    final telefono = _prestamista?['phone'] as String?;
    final enlace = enlaceWhatsApp(telefono, 'Hola, tengo una pregunta sobre mi solicitud.');
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(_negocio, style: const TextStyle(color: Color(0xFF5B6472), fontSize: 13)),
        if (enlace != null) ...[
          const Text('  ·  ', style: TextStyle(color: Color(0xFF5B6472))),
          InkWell(
            onTap: () => launchUrl(enlace, mode: LaunchMode.externalApplication),
            child: Text('Soporte ${formatearTelefono(telefono!)}',
                style: const TextStyle(
                    color: _azul, fontSize: 13, decoration: TextDecoration.underline)),
          ),
        ],
      ],
    );
  }

  Widget _buildPasoActual() {
    switch (_pasoId) {
      case _fotos:
        return _paso1Fotos();
      case _datos:
        return _paso2Datos();
      case _trabajo:
        return _paso3Trabajo();
      case _referencias:
        return _paso4Referencias();
      case _pago:
        return _paso5Pago();
      default:
        return const SizedBox();
    }
  }

  /// Tarjeta ancha para una foto: ícono, título y ayuda (y la foto ya
  /// tomada), con dos botones: "Tomar foto" abre la cámara directo (en Chrome
  /// de Android el selector de fotos no trae cámara) y "Galería" elige una
  /// que ya tenga. Cada botón abre el selector en el mismo toque, como pide
  /// Safari en iPhone.
  Widget _tarjetaFoto({
    required IconData icono,
    required String titulo,
    required String ayuda,
    required Uint8List? bytes,
    bool frontal = false,
    required void Function(Uint8List bytes) onTomada,
  }) {
    final lista = bytes != null;
    void pedir(ImageSource origen) =>
        _tomarFoto(origen: origen, frontal: frontal, onTomada: onTomada);
    final forma = RoundedRectangleBorder(borderRadius: BorderRadius.circular(12));
    const letraBoton = TextStyle(fontSize: 15, fontWeight: FontWeight.w800);
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: CustomPaint(
        painter: _BordePunteado(color: lista ? _verde : _azul, radio: 16),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: lista ? const Color(0xFFF0FAF4) : _azulClaro,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 28,
                    backgroundColor: lista ? const Color(0xFFD5F2E0) : const Color(0xFFDCE6FF),
                    child: Icon(lista ? Icons.check_rounded : icono,
                        color: lista ? _verde : _azul, size: 30),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(titulo,
                            style: const TextStyle(
                                fontSize: 20, fontWeight: FontWeight.w800, color: _azulOscuro)),
                        const SizedBox(height: 2),
                        Text(lista ? 'Lista. Si quieres, tómala otra vez.' : ayuda,
                            style: const TextStyle(fontSize: 14, color: Color(0xFF333A45))),
                      ],
                    ),
                  ),
                  if (lista) ...[
                    const SizedBox(width: 10),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Image.memory(bytes, width: 84, height: 84, fit: BoxFit.cover),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 14),
              // Wrap: con letra grande en el teléfono, un botón baja de línea.
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  ElevatedButton.icon(
                    onPressed: () => pedir(ImageSource.camera),
                    icon: const Icon(Icons.photo_camera_rounded),
                    label: const Text('Tomar foto'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _azul,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(150, 48),
                      shape: forma,
                      textStyle: letraBoton,
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => pedir(ImageSource.gallery),
                    icon: const Icon(Icons.photo_library_rounded),
                    label: const Text('Galería'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _azul,
                      side: const BorderSide(color: _azul, width: 1.5),
                      minimumSize: const Size(130, 48),
                      shape: forma,
                      textStyle: letraBoton,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _paso1Fotos() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _encabezadoPaso('Tus fotos',
            'Último paso: tres fotos claras para verificar tu identidad. Toca "Tomar foto" '
                'para usar la cámara.'),
        Container(
          margin: const EdgeInsets.only(bottom: 16),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF7E6),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.lightbulb_outline_rounded, color: Color(0xFFB45309)),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  '¿No se abre la cámara? Toca "Galería" y elige una foto que ya tomaste. '
                  'Lo que escribiste no se pierde.',
                  style: TextStyle(fontSize: 14, color: Color(0xFF333A45)),
                ),
              ),
            ],
          ),
        ),
        _tarjetaFoto(
          icono: Icons.face_rounded,
          titulo: 'Foto de tu cara',
          ayuda: 'Que se vea clara, sin lentes oscuros',
          bytes: _fotoCaraBytes,
          frontal: true,
          onTomada: (b) => _fotoCaraBytes = b,
        ),
        _tarjetaFoto(
          icono: Icons.badge_outlined,
          titulo: 'Cédula - Frente',
          ayuda: 'Parte frontal de tu cédula, que se lea bien',
          bytes: _fotoCedulaFrenteBytes,
          onTomada: (b) => _fotoCedulaFrenteBytes = b,
        ),
        _tarjetaFoto(
          icono: Icons.flip_to_back_outlined,
          titulo: 'Cédula - Reverso',
          ayuda: 'Parte de atrás de tu cédula, que se lea bien',
          bytes: _fotoCedulaReversoBytes,
          onTomada: (b) => _fotoCedulaReversoBytes = b,
        ),
        // Ley 172-13: el cliente autoriza que el prestamista use sus datos.
        CasillaAcepto(
          valor: _autorizaDatos,
          onCambio: (v) => setState(() => _autorizaDatos = v),
          texto: 'Autorizo a $_negocio a guardar y usar mis datos y fotos para evaluar '
              'mi solicitud y administrar mi préstamo, según la',
          conTerminos: false,
          color: _azul,
        ),
      ],
    );
  }

  /// Campo de texto. `validar` marca el error en rojo cuando se intenta
  /// seguir; `aviso` es una advertencia en ámbar que no bloquea.
  Widget _campo(
    TextEditingController c,
    String label, {
    TextInputType? tipo,
    String? Function(String?)? validar,
    String? Function(String?)? aviso,
    List<TextInputFormatter>? formato,
    String? ejemplo,
  }) {
    final error = _mostrarErrores ? validar?.call(c.text) : null;
    final advertencia = error == null ? aviso?.call(c.text) : null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: TextField(
        controller: c,
        keyboardType: tipo,
        inputFormatters: formato,
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(
          labelText: label,
          hintText: ejemplo,
          errorText: error,
          helperText: advertencia,
          helperMaxLines: 2,
          helperStyle: const TextStyle(color: Color(0xFFB45309), fontWeight: FontWeight.w600),
          filled: true,
          fillColor: const Color(0xFFF7F9FC),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(
                color: advertencia != null ? const Color(0xFFF59E0B) : const Color(0xFFD5DBE5)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: _azul, width: 2),
          ),
        ),
      ),
    );
  }

  Widget _paso2Datos() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _encabezadoPaso('Tus datos', 'Escríbelos como aparecen en tu cédula'),
        _campo(_nombreCtrl, 'Nombre completo',
            validar: errorNombre, ejemplo: 'Ej. José Pérez Díaz'),
        _campo(_cedulaCtrl, 'Cédula',
            tipo: TextInputType.number,
            formato: [FormatoCedula()],
            validar: errorCedula,
            aviso: avisoCedula,
            ejemplo: '001-1234567-8'),
        _campo(_telefonoCtrl, 'Teléfono',
            tipo: TextInputType.phone,
            formato: [FormatoTelefono()],
            validar: errorTelefono,
            ejemplo: '809-555-1234'),
        _campo(_direccionCtrl, 'Dirección exacta'),
        const Text('La casa donde vives es:', style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Row(
          children: [
            for (final (valor, texto) in [('propia', 'Propia'), ('alquilada', 'Alquilada')]) ...[
              ChoiceChip(
                label: Text(texto),
                selected: _tipoVivienda == valor,
                onSelected: (_) => _elegir(() => _tipoVivienda = valor),
              ),
              const SizedBox(width: 8),
            ],
          ],
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: _capturarUbicacion,
          icon: Icon(_lat != null ? Icons.check_circle : Icons.my_location,
              color: _lat != null ? AppColors.green : null),
          label: Text(_lat != null ? 'Ubicación capturada' : 'Marcar mi ubicación'),
        ),
      ],
    );
  }

  Widget _paso3Trabajo() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _encabezadoPaso('Dónde trabajas', 'Así sabemos cómo vas a pagar'),
        _campo(_trabajoLugarCtrl, 'Lugar de trabajo'),
        _campo(_trabajoDireccionCtrl, 'Dirección del trabajo'),
        _campo(_jefeNombreCtrl, 'Nombre del supervisor o de Recursos Humanos'),
        _campo(_jefeTelefonoCtrl, 'Teléfono del supervisor o de Recursos Humanos',
            tipo: TextInputType.phone,
            formato: [FormatoTelefono()],
            validar: (t) => errorTelefono(t, obligatorio: false)),
        _campo(_ingresoMensualCtrl, '¿Cuánto ganas al mes? (RD\$)',
            tipo: TextInputType.number, formato: [soloNumeros], validar: errorMonto),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('¿Tienes otros ingresos?'),
          value: _tieneOtrosIngresos,
          onChanged: (v) => _elegir(() => _tieneOtrosIngresos = v),
        ),
        if (_tieneOtrosIngresos) ...[
          _campo(_otrosIngresosDescripcionCtrl, '¿De dónde? (ej: negocio propio, alquiler)'),
          _campo(_otrosIngresosMontoCtrl, 'Monto aproximado (RD\$)',
              tipo: TextInputType.number, formato: [soloNumeros], validar: errorMonto),
        ],
        const SizedBox(height: 12),
        SelectorEvidencias(
          fotos: _evidencias,
          obligatorio: _exigeEvidencias,
          onCambio: (f) => setState(() => _evidencias = f),
        ),
      ],
    );
  }

  Widget _paso4Referencias() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _encabezadoPaso('2 referencias personales',
            'Personas que te conozcan y que podamos llamar'),
        const Text('Referencia 1', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        _campo(_ref1NombreCtrl, 'Nombre'),
        _campo(_ref1ParentescoCtrl, 'Parentesco'),
        _campo(_ref1TelefonoCtrl, 'Teléfono',
            tipo: TextInputType.phone,
            formato: [FormatoTelefono()],
            validar: (t) => errorTelefono(t, obligatorio: false)),
        const SizedBox(height: 12),
        const Text('Referencia 2', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        _campo(_ref2NombreCtrl, 'Nombre'),
        _campo(_ref2ParentescoCtrl, 'Parentesco'),
        _campo(_ref2TelefonoCtrl, 'Teléfono',
            tipo: TextInputType.phone,
            formato: [FormatoTelefono()],
            validar: (t) => errorTelefono(t, obligatorio: false)),
      ],
    );
  }

  Widget _paso5Pago() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _encabezadoPaso('¿Cuánto necesitas?', 'Ya casi terminas: solo faltan tus fotos'),
        _campo(_montoCtrl, 'Monto que solicitas (RD\$)',
            tipo: TextInputType.number, formato: [soloNumeros], validar: errorMonto),
        const Text('¿Cómo prefieres pagar?', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        RadioGroup<String>(
          groupValue: _frecuenciaPago,
          onChanged: (v) => _elegir(() => _frecuenciaPago = v!),
          child: const Row(
            children: [
              Expanded(
                child: RadioListTile<String>(
                  value: 'diario',
                  title: Text('Diario'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              Expanded(
                child: RadioListTile<String>(
                  value: 'semanal',
                  title: Text('Semanal'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
        ),
        _campo(
          _capacidadPagoCtrl,
          _frecuenciaPago == 'diario'
              ? '¿Cuánto puedes pagar al día? (RD\$)'
              : '¿Cuánto puedes pagar a la semana? (RD\$)',
          tipo: TextInputType.number,
          formato: [soloNumeros],
          validar: errorMonto,
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.blue.shade50,
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Text(
            '¿Cómo te gustaría recibir el dinero si te aprobamos? '
            'Esto es solo si te aprobamos, no es obligatorio llenarlo ahora.',
            style: TextStyle(fontSize: 13),
          ),
        ),
        const SizedBox(height: 12),
        RadioGroup<String>(
          groupValue: _metodoCobro,
          onChanged: (v) => _elegir(() => _metodoCobro = v!),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const RadioListTile<String>(
                value: 'transferencia',
                title: Text('Transferencia bancaria'),
              ),
              if (_metodoCobro == 'transferencia') ...[
                DropdownButtonFormField<String>(
                  initialValue: _banco,
                  items: ['Banreservas', 'Popular', 'BHD', 'Scotia', 'Otro']
                      .map((b) => DropdownMenuItem(value: b, child: Text(b)))
                      .toList(),
                  onChanged: (v) => _elegir(() => _banco = v),
                  decoration: const InputDecoration(labelText: 'Banco'),
                ),
                _campo(_numeroCuentaCtrl, 'Número de cuenta',
                    tipo: TextInputType.number, formato: [soloNumeros]),
              ],
              const RadioListTile<String>(
                value: 'billetera',
                title: Text('Billetera (Qik / MIO)'),
              ),
              if (_metodoCobro == 'billetera')
                DropdownButtonFormField<String>(
                  initialValue: _billetera,
                  items: ['Qik', 'MIO']
                      .map((b) => DropdownMenuItem(value: b, child: Text(b)))
                      .toList(),
                  onChanged: (v) => _elegir(() => _billetera = v),
                  decoration: const InputDecoration(labelText: 'Billetera'),
                ),
              const RadioListTile<String>(
                value: 'efectivo',
                title: Text('Prefiero que venga a mi casa/trabajo'),
              ),
              const RadioListTile<String>(
                value: 'sin_definir',
                title: Text('Dejar en blanco por ahora'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Borde punteado redondeado (Flutter no trae uno).
class _BordePunteado extends CustomPainter {
  final Color color;
  final double radio;
  const _BordePunteado({required this.color, required this.radio});

  @override
  void paint(Canvas canvas, Size size) {
    final pincel = Paint()
      ..color = color
      ..strokeWidth = 1.6
      ..style = PaintingStyle.stroke;
    final contorno = Path()
      ..addRRect(RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(radio)));
    const trazo = 7.0, espacio = 5.0;
    for (final tramo in contorno.computeMetrics()) {
      for (var d = 0.0; d < tramo.length; d += trazo + espacio) {
        canvas.drawPath(tramo.extractPath(d, d + trazo), pincel);
      }
    }
  }

  @override
  bool shouldRepaint(_BordePunteado viejo) => viejo.color != color || viejo.radio != radio;
}
