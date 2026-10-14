import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../logic/busqueda.dart';
import '../logic/validacion.dart';
import '../widgets/formato_campos.dart';
import '../services/supabase_service.dart';
import '../theme/app_theme.dart';
import '../widgets/elegir_foto.dart';
import '../widgets/evidencias.dart';
import '../widgets/ui.dart';
import 'planes_screen.dart';
import 'prestar_screen.dart';

/// Crear un cliente a mano, para quien no puede llenar la solicitud por el
/// link. Al guardar pasa directo a Prestar.
class NuevoClienteScreen extends StatefulWidget {
  final String prestamistaId;

  /// Valores de la calculadora, si se llegó desde ahí.
  final double? monto;
  final double? tasa;
  final int? dias;
  final String? frecuencia;

  const NuevoClienteScreen({
    super.key,
    required this.prestamistaId,
    this.monto,
    this.tasa,
    this.dias,
    this.frecuencia,
  });

  @override
  State<NuevoClienteScreen> createState() => _NuevoClienteScreenState();
}

class _NuevoClienteScreenState extends State<NuevoClienteScreen> {
  final _form = GlobalKey<FormState>();
  final _nombre = TextEditingController();
  final _cedula = TextEditingController();
  final _telefono = TextEditingController();
  final _direccion = TextEditingController();
  final _trabajo = TextEditingController();
  final _jefe = TextEditingController();
  final _jefeTel = TextEditingController();
  final _ref = TextEditingController();
  final _refParentesco = TextEditingController();
  final _refTel = TextEditingController();
  final _ingreso = TextEditingController();
  String? _tipoVivienda; // propia / alquilada
  bool _guardando = false;

  // Fotos (opcionales): bytes, porque File no funciona en la web.
  Uint8List? _fotoCedulaFrente;
  Uint8List? _fotoCedulaReverso;
  Uint8List? _fotoCara;
  List<Uint8List> _evidencias = [];

  /// Clientes que ya existen, para sugerirlos mientras se escribe y no
  /// crear uno repetido.
  List<Map<String, dynamic>> _existentes = const [];

  /// Se esconden las sugerencias si el prestamista dice "es otra persona".
  bool _ocultarSugerencias = false;

  @override
  void initState() {
    super.initState();
    // Future.sync para que cualquier error (hasta uno inmediato, sin
    // conexión) quede en catchError: sin sugerencias se puede crear igual.
    Future.sync(() => SupabaseService.instance.listarClientes(widget.prestamistaId))
        .then((lista) {
      if (mounted) setState(() => _existentes = lista);
    }).catchError((_) {});
    for (final c in [_nombre, _cedula, _telefono]) {
      c.addListener(() => setState(() => _ocultarSugerencias = false));
    }
  }

  /// Lo que se está escribiendo (cédula o teléfono pesan más que el nombre).
  List<Map<String, dynamic>> get _sugerencias {
    if (_ocultarSugerencias || _existentes.isEmpty) return const [];
    for (final texto in [_cedula.text, _telefono.text, _nombre.text]) {
      if (texto.trim().isEmpty) continue;
      final r = buscarClientes(_existentes, texto, maximo: 5);
      if (r.isNotEmpty) return r;
    }
    return const [];
  }

  /// Prestarle a un cliente que ya existe: usa su préstamo por confirmar si
  /// tiene uno, o le crea uno nuevo.
  Future<void> _prestarAExistente(Map<String, dynamic> cliente) async {
    final servicio = SupabaseService.instance;
    final mensajero = ScaffoldMessenger.of(context);
    try {
      final prestamos = await servicio.obtenerPrestamosDeCliente(cliente['id'] as String);
      final enCalle = prestamos.where((p) => p['estado'] == 'en_calle').length;
      if (enCalle > 0 && mounted) {
        final seguir = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: AppColors.surface,
            title: Text('${cliente['nombre']} ya tiene un préstamo en la calle'),
            content: const Text('¿Quieres prestarle otro aparte?'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.of(ctx).pop(false), child: const Text('No')),
              TextButton(
                  onPressed: () => Navigator.of(ctx).pop(true),
                  child: const Text('Sí, prestarle otro')),
            ],
          ),
        );
        if (seguir != true) return;
      }
      final borrador = prestamos.where((p) => p['estado'] == 'borrador').firstOrNull ??
          await servicio.crearPrestamoBorrador(cliente);
      if (!mounted) return;
      await Navigator.of(context).pushReplacement(MaterialPageRoute(
        builder: (_) => PrestarScreen(
          cliente: cliente,
          prestamo: {...borrador, if (widget.monto != null) 'monto': widget.monto},
          tasaInicial: widget.tasa,
          diasInicial: widget.dias,
          frecuenciaInicial: widget.frecuencia,
        ),
      ));
    } catch (e) {
      mensajero.showSnackBar(SnackBar(content: Text('No se pudo abrir el préstamo: $e')));
    }
  }

  /// Pide la foto (cámara o galería; en iPhone, el menú del teléfono).
  Future<Uint8List?> _elegirFoto() => elegirFoto(context);

  Future<String?> _subir(Uint8List? bytes, String tipo) async {
    if (bytes == null) return null;
    return SupabaseService.instance.subirFoto(
      bytes: bytes,
      prestamistaId: widget.prestamistaId,
      tipo: 'manual_$tipo',
    );
  }

  String? _texto(TextEditingController c) => c.text.trim().isEmpty ? null : c.text.trim();

  /// "Ya es tu cliente: José Pérez" si ese dato ya lo tiene otro cliente.
  String? _repetido(DatoRepetido dato) {
    final r = buscarRepetidos(
      _existentes,
      cedula: dato == DatoRepetido.cedula ? _cedula.text : null,
      telefono: dato == DatoRepetido.telefono ? _telefono.text : null,
      nombre: dato == DatoRepetido.nombre ? _nombre.text : null,
    );
    if (r.isEmpty) return null;
    final quien = r.map((x) => x.registro['nombre']).toSet().join(', ');
    return switch (dato) {
      DatoRepetido.cedula => 'Esta cédula ya es de tu cliente $quien',
      DatoRepetido.telefono => 'Este teléfono ya lo tiene tu cliente $quien',
      DatoRepetido.nombre => 'Ya tienes un cliente con este nombre',
    };
  }

  Future<void> _guardar() async {
    if (!_form.currentState!.validate()) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Revisa los datos marcados en rojo')));
      return;
    }
    // Teléfono o nombre repetido no bloquea (dos hermanos pueden compartir
    // teléfono), pero se confirma para no digitar a alguien dos veces.
    final dudas = [_repetido(DatoRepetido.nombre), _repetido(DatoRepetido.telefono)]
        .whereType<String>()
        .toList();
    if (dudas.isNotEmpty) {
      final seguir = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppColors.surface,
          title: const Text('¿Es otra persona?'),
          content: Text('${dudas.join('.\n')}.\n\n'
              'Si es la misma persona, búscala en Clientes en vez de crearla otra vez.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Revisar')),
            TextButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('Sí, es otra persona')),
          ],
        ),
      );
      if (seguir != true) return;
    }
    setState(() => _guardando = true);
    try {
      final urlFrente = await _subir(_fotoCedulaFrente, 'cedula_f');
      final urlReverso = await _subir(_fotoCedulaReverso, 'cedula_r');
      final urlCara = await _subir(_fotoCara, 'cara');
      final evidencias =
          await SupabaseService.instance.subirEvidencias(_evidencias,
              prestamistaId: widget.prestamistaId, prefijo: 'manual');
      final r = await SupabaseService.instance.crearClienteManual(
        prestamistaId: widget.prestamistaId,
        monto: widget.monto,
        datos: {
          'nombre': _nombre.text.trim(),
          'cedula': formatearCedula(_cedula.text),
          'telefono': formatearTelefono(_telefono.text),
          'direccion': _texto(_direccion),
          'tipo_vivienda': _tipoVivienda,
          'foto_cedula_frente_url': urlFrente,
          'foto_cedula_reverso_url': urlReverso,
          'foto_cara_url': urlCara,
          'ingreso_mensual': double.tryParse(_ingreso.text.replaceAll(',', '')),
          'evidencias_ingresos': evidencias,
          'trabajo_lugar': _texto(_trabajo),
          'jefe_nombre': _texto(_jefe),
          'jefe_telefono': _texto(_jefeTel),
          'ref1_nombre': _texto(_ref),
          'ref1_parentesco': _texto(_refParentesco),
          'ref1_telefono': _texto(_refTel),
        },
      );
      if (!mounted) return;
      await Navigator.of(context).pushReplacement(MaterialPageRoute(
        builder: (_) => PrestarScreen(
          cliente: r.cliente,
          prestamo: r.prestamo,
          tasaInicial: widget.tasa,
          diasInicial: widget.dias,
          frecuenciaInicial: widget.frecuencia,
        ),
      ));
    } on ClienteRepetido catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    } on LimitePlan catch (e) {
      if (mounted) await avisarLimitePlan(context, e);
    } catch (e) {
      // ignore: avoid_print
      print('ERROR REAL NUEVO CLIENTE: $e');
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('No se pudo crear el cliente: $e')));
      }
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Nuevo cliente')),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            if (widget.monto != null)
              Panel(
                borde: AppColors.green.withValues(alpha: 0.4),
                child: Row(
                  children: [
                    Icon(Icons.calculate_rounded, color: AppColors.green),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                          'Préstamo de ${rd(widget.monto!)} de la calculadora. '
                          'Lo confirmas en el próximo paso.',
                          style: TextStyle(color: AppColors.grey)),
                    ),
                  ],
                ),
              ),
            _seccion('Datos del cliente'),
            _campo(_nombre, 'Nombre completo',
                obligatorio: true,
                mayusculas: true,
                validar: errorNombre,
                aviso: (_) => _repetido(DatoRepetido.nombre)),
            if (_sugerencias.isNotEmpty) _panelSugerencias(_sugerencias),
            _campo(_cedula, 'Cédula',
                obligatorio: true,
                teclado: TextInputType.number,
                formato: [FormatoCedula()],
                ejemplo: '001-1234567-8',
                // Cédula repetida sí bloquea: es la misma persona seguro.
                validar: (t) => errorCedula(t) ?? _repetido(DatoRepetido.cedula),
                aviso: avisoCedula),
            _campo(_telefono, 'Teléfono',
                obligatorio: true,
                teclado: TextInputType.phone,
                formato: [FormatoTelefono()],
                ejemplo: '809-555-1234',
                validar: errorTelefono,
                aviso: (_) => _repetido(DatoRepetido.telefono)),
            _campo(_direccion, 'Dirección'),
            Text('La casa donde vive es:', style: TextStyle(color: AppColors.grey)),
            const SizedBox(height: 8),
            Row(
              children: [
                for (final (valor, texto) in [('propia', 'Propia'), ('alquilada', 'Alquilada')]) ...[
                  ChoiceChip(
                    label: Text(texto),
                    selected: _tipoVivienda == valor,
                    selectedColor: AppColors.greenDark,
                    labelStyle: TextStyle(
                        color: _tipoVivienda == valor ? AppColors.green : AppColors.grey,
                        fontWeight: FontWeight.w700),
                    onSelected: (_) => setState(
                        () => _tipoVivienda = _tipoVivienda == valor ? null : valor),
                  ),
                  const SizedBox(width: 8),
                ],
              ],
            ),
            _seccion('Fotos (opcional)'),
            Row(
              children: [
                Expanded(
                  child: _foto('Cédula frente', _fotoCedulaFrente, () async {
                    final b = await _elegirFoto();
                    if (b != null) setState(() => _fotoCedulaFrente = b);
                  }),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _foto('Cédula atrás', _fotoCedulaReverso, () async {
                    final b = await _elegirFoto();
                    if (b != null) setState(() => _fotoCedulaReverso = b);
                  }),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _foto('Cara', _fotoCara, () async {
                    final b = await _elegirFoto();
                    if (b != null) setState(() => _fotoCara = b);
                  }),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _seccion('Trabajo e ingresos (opcional)'),
            _campo(_trabajo, 'Dónde trabaja'),
            _campo(_ingreso, '¿Cuánto gana al mes? (RD\$)',
                teclado: TextInputType.number, formato: [soloNumeros], validar: errorMonto),
            SelectorEvidencias(
              fotos: _evidencias,
              onCambio: (f) => setState(() => _evidencias = f),
            ),
            const SizedBox(height: 16),
            _campo(_jefe, 'Nombre del supervisor o de Recursos Humanos'),
            _campo(_jefeTel, 'Tel. del supervisor o de RR.HH.',
                teclado: TextInputType.phone,
                formato: [FormatoTelefono()],
                validar: (t) => errorTelefono(t, obligatorio: false)),
            _seccion('Referencia (opcional)'),
            Row(
              children: [
                Expanded(child: _campo(_ref, 'Nombre')),
                const SizedBox(width: 10),
                Expanded(child: _campo(_refParentesco, 'Parentesco')),
              ],
            ),
            _campo(_refTel, 'Tel. referencia',
                teclado: TextInputType.phone,
                formato: [FormatoTelefono()],
                validar: (t) => errorTelefono(t, obligatorio: false)),
            const SizedBox(height: 8),
            ElevatedButton.icon(
              onPressed: _guardando ? null : _guardar,
              icon: _guardando
                  ? const SizedBox(
                      width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.arrow_forward),
              label: const Text('Guardar y prestar'),
            ),
          ],
        ),
      ),
    );
  }

  /// "¿Ya lo tienes?": clientes existentes que coinciden con lo escrito.
  Widget _panelSugerencias(List<Map<String, dynamic>> clientes) {
    return Panel(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(12, 10, 4, 4),
      borde: AppColors.green.withValues(alpha: 0.5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('¿Es alguno de tus clientes? Tócalo para prestarle',
              style: TextStyle(color: AppColors.green, fontWeight: FontWeight.w700, fontSize: 13)),
          for (final c in clientes)
            ListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              leading: AvatarIniciales(
                  nombre: c['nombre'] ?? '', fotoUrl: c['foto_cara_url'] as String?, tamano: 36),
              title: Text(c['nombre'] ?? '', style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text(
                [c['cedula'], c['telefono']]
                    .where((x) => x != null && '$x'.isNotEmpty)
                    .join(' · '),
                style: TextStyle(color: AppColors.grey, fontSize: 12),
              ),
              trailing: Icon(Icons.arrow_forward, color: AppColors.green),
              onTap: () => _prestarAExistente(c),
            ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () => setState(() => _ocultarSugerencias = true),
              child: const Text('No, es una persona nueva'),
            ),
          ),
        ],
      ),
    );
  }

  /// Recuadro para tomar/elegir una foto; muestra la miniatura si ya hay.
  Widget _foto(String etiqueta, Uint8List? bytes, VoidCallback onTap) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        height: 96,
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: bytes != null ? AppColors.green : AppColors.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: bytes != null
            ? Image.memory(bytes, fit: BoxFit.cover, width: double.infinity)
            : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.add_a_photo_rounded, color: AppColors.grey),
                  const SizedBox(height: 6),
                  Text(etiqueta,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.grey, fontSize: 12)),
                ],
              ),
      ),
    );
  }

  Widget _seccion(String titulo) => Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 10),
        child: Text(titulo,
            style: TextStyle(color: AppColors.green, fontWeight: FontWeight.w800)),
      );

  Widget _campo(
    TextEditingController c,
    String etiqueta, {
    bool obligatorio = false,
    bool mayusculas = false,
    TextInputType teclado = TextInputType.text,
    String? Function(String?)? validar,
    String? Function(String?)? aviso,
    List<TextInputFormatter>? formato,
    String? ejemplo,
  }) {
    // Aviso en ámbar (no bloquea): repetido o cédula dudosa.
    final advertencia = aviso?.call(c.text);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: c,
        keyboardType: teclado,
        inputFormatters: formato,
        autovalidateMode: AutovalidateMode.onUserInteraction,
        textCapitalization: mayusculas ? TextCapitalization.words : TextCapitalization.none,
        validator: (v) {
          if (obligatorio && (v == null || v.trim().isEmpty)) return 'Obligatorio';
          return validar?.call(v);
        },
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(
          labelText: obligatorio ? '$etiqueta *' : etiqueta,
          hintText: ejemplo,
          helperText: advertencia,
          helperMaxLines: 2,
          helperStyle: TextStyle(color: AppColors.amber, fontWeight: FontWeight.w600),
          errorMaxLines: 2,
          filled: true,
          fillColor: AppColors.surface,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: advertencia != null
                ? BorderSide(color: AppColors.amber)
                : BorderSide.none,
          ),
        ),
      ),
    );
  }
}
