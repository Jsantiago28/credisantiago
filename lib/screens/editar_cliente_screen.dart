import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../logic/validacion.dart';
import '../services/errores.dart';
import '../services/supabase_service.dart';
import '../theme/app_theme.dart';
import '../widgets/elegir_foto.dart';
import '../widgets/formato_campos.dart';
import '../widgets/foto_privada.dart';

/// Corregir los datos de un cliente (nombre, cédula, teléfono, trabajo,
/// referencias). Mismas reglas que al crearlo: cédula de 11 dígitos,
/// teléfono de RD y aviso si otro cliente ya tiene esa cédula o teléfono.
/// Devuelve true si guardó.
class EditarClienteScreen extends StatefulWidget {
  final Map<String, dynamic> cliente;
  const EditarClienteScreen({super.key, required this.cliente});

  @override
  State<EditarClienteScreen> createState() => _EditarClienteScreenState();
}

class _EditarClienteScreenState extends State<EditarClienteScreen> {
  final _form = GlobalKey<FormState>();
  late final Map<String, TextEditingController> _c;
  String? _tipoVivienda;
  bool _guardando = false;
  List<Map<String, dynamic>> _otros = const [];

  /// Fotos cambiadas (columna → foto nueva); se suben al guardar.
  final _fotosNuevas = <String, Uint8List>{};

  static const _camposFoto = [
    ('foto_cara_url', 'Cara'),
    ('foto_cedula_frente_url', 'Cédula frente'),
    ('foto_cedula_reverso_url', 'Cédula atrás'),
  ];

  static const _campos = [
    'nombre',
    'cedula',
    'telefono',
    'direccion',
    'trabajo_lugar',
    'trabajo_direccion',
    'ingreso_mensual',
    'jefe_nombre',
    'jefe_telefono',
    'ref1_nombre',
    'ref1_parentesco',
    'ref1_telefono',
    'ref2_nombre',
    'ref2_parentesco',
    'ref2_telefono',
  ];

  @override
  void initState() {
    super.initState();
    final cl = widget.cliente;
    _c = {
      for (final campo in _campos)
        campo: TextEditingController(text: _textoInicial(cl[campo], campo)),
    };
    _tipoVivienda = cl['tipo_vivienda'] as String?;
    Future.sync(() => SupabaseService.instance.listarClientes(cl['prestamista_id'] as String))
        .then((lista) {
      if (mounted) setState(() => _otros = lista);
    }).catchError((_) {});
  }

  String _textoInicial(dynamic valor, String campo) {
    if (valor == null) return '';
    if (campo == 'ingreso_mensual') {
      final n = valor is num ? valor : num.tryParse('$valor');
      return n == null ? '' : n.toStringAsFixed(0);
    }
    if (campo == 'cedula') return formatearCedula('$valor');
    if (campo.endsWith('telefono')) return formatearTelefono('$valor');
    return '$valor';
  }

  @override
  void dispose() {
    for (final c in _c.values) {
      c.dispose();
    }
    super.dispose();
  }

  String? _repetido(DatoRepetido dato) {
    final r = buscarRepetidos(
      _otros,
      cedula: dato == DatoRepetido.cedula ? _c['cedula']!.text : null,
      telefono: dato == DatoRepetido.telefono ? _c['telefono']!.text : null,
      excluirId: widget.cliente['id'] as String?,
    );
    if (r.isEmpty) return null;
    final quien = r.map((x) => x.registro['nombre']).toSet().join(', ');
    return dato == DatoRepetido.cedula
        ? 'Esta cédula ya es de tu cliente $quien'
        : 'Este teléfono ya lo tiene tu cliente $quien';
  }

  String? _texto(String campo) {
    final t = _c[campo]!.text.trim();
    return t.isEmpty ? null : t;
  }

  Future<void> _guardar() async {
    if (!_form.currentState!.validate()) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Revisa los datos marcados en rojo')));
      return;
    }
    setState(() => _guardando = true);
    final mensajero = ScaffoldMessenger.of(context);
    try {
      String? tel(String campo) {
        final t = _texto(campo);
        return t == null ? null : formatearTelefono(t);
      }

      final fotos = <String, String>{
        for (final e in _fotosNuevas.entries)
          e.key: await SupabaseService.instance.subirFoto(
            bytes: e.value,
            prestamistaId: widget.cliente['prestamista_id'] as String,
            tipo: 'editado_${e.key.replaceAll('foto_', '').replaceAll('_url', '')}',
          ),
      };

      await SupabaseService.instance.actualizarCliente(widget.cliente, {
        'nombre': _texto('nombre'),
        'cedula': formatearCedula(_c['cedula']!.text),
        'telefono': formatearTelefono(_c['telefono']!.text),
        'direccion': _texto('direccion'),
        'tipo_vivienda': _tipoVivienda,
        'trabajo_lugar': _texto('trabajo_lugar'),
        'trabajo_direccion': _texto('trabajo_direccion'),
        'ingreso_mensual': double.tryParse(_c['ingreso_mensual']!.text),
        'jefe_nombre': _texto('jefe_nombre'),
        'jefe_telefono': tel('jefe_telefono'),
        'ref1_nombre': _texto('ref1_nombre'),
        'ref1_parentesco': _texto('ref1_parentesco'),
        'ref1_telefono': tel('ref1_telefono'),
        'ref2_nombre': _texto('ref2_nombre'),
        'ref2_parentesco': _texto('ref2_parentesco'),
        'ref2_telefono': tel('ref2_telefono'),
        ...fotos,
      });
      if (!mounted) return;
      mensajero.showSnackBar(const SnackBar(content: Text('Datos del cliente actualizados')));
      Navigator.of(context).pop(true);
    } on ClienteRepetido catch (e) {
      mensajero.showSnackBar(SnackBar(content: Text(mensajeError(e))));
    } catch (e, pila) {
      registrarError(e, pila, 'EDITAR CLIENTE');
      mensajero.showSnackBar(SnackBar(content: Text('No se pudo guardar. ${mensajeError(e)}')));
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    String? telOpcional(String? t) => errorTelefono(t, obligatorio: false);
    return Scaffold(
      appBar: AppBar(title: const Text('Corregir datos')),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            _seccion('Fotos'),
            _fotos(),
            const SizedBox(height: 8),
            _seccion('Datos del cliente'),
            _campo('nombre', 'Nombre completo', validar: errorNombre, mayusculas: true),
            _campo('cedula', 'Cédula',
                teclado: TextInputType.number,
                formato: [FormatoCedula()],
                validar: (t) => errorCedula(t) ?? _repetido(DatoRepetido.cedula),
                aviso: avisoCedula),
            _campo('telefono', 'Teléfono',
                teclado: TextInputType.phone,
                formato: [FormatoTelefono()],
                validar: errorTelefono,
                aviso: (_) => _repetido(DatoRepetido.telefono)),
            _campo('direccion', 'Dirección'),
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
            _seccion('Trabajo e ingresos'),
            _campo('trabajo_lugar', 'Dónde trabaja'),
            _campo('trabajo_direccion', 'Dirección del trabajo'),
            _campo('ingreso_mensual', '¿Cuánto gana al mes? (RD\$)',
                teclado: TextInputType.number, formato: [soloNumeros], validar: errorMonto),
            _campo('jefe_nombre', 'Nombre del supervisor o de Recursos Humanos'),
            _campo('jefe_telefono', 'Tel. del supervisor o de RR.HH.',
                teclado: TextInputType.phone, formato: [FormatoTelefono()], validar: telOpcional),
            _seccion('Referencia 1'),
            _campo('ref1_nombre', 'Nombre'),
            _campo('ref1_parentesco', 'Parentesco'),
            _campo('ref1_telefono', 'Teléfono',
                teclado: TextInputType.phone, formato: [FormatoTelefono()], validar: telOpcional),
            _seccion('Referencia 2'),
            _campo('ref2_nombre', 'Nombre'),
            _campo('ref2_parentesco', 'Parentesco'),
            _campo('ref2_telefono', 'Teléfono',
                teclado: TextInputType.phone, formato: [FormatoTelefono()], validar: telOpcional),
            const SizedBox(height: 8),
            ElevatedButton.icon(
              onPressed: _guardando ? null : _guardar,
              icon: _guardando
                  ? const SizedBox(
                      width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.check),
              label: const Text('Guardar cambios'),
            ),
          ],
        ),
      ),
    );
  }

  /// Las 3 fotos del cliente: la que tiene y "Cambiar" para poner otra. La
  /// foto vieja no se borra: queda en el historial de cambios.
  Widget _fotos() {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        for (final (campo, texto) in _camposFoto)
          SizedBox(
            width: 100,
            child: Column(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: SizedBox(
                    width: 100,
                    height: 72,
                    child: _fotosNuevas[campo] != null
                        ? Image.memory(_fotosNuevas[campo]!, fit: BoxFit.cover)
                        : FotoPrivada(
                            guardado: widget.cliente[campo] as String?,
                            width: 100,
                            height: 72,
                            sinFoto: Container(
                              color: AppColors.surface,
                              child: Icon(Icons.no_photography_rounded,
                                  color: AppColors.grey),
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(texto,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.grey, fontSize: 11)),
                TextButton(
                  onPressed: _guardando
                      ? null
                      : () async {
                          final bytes = await elegirFoto(context);
                          if (bytes != null) setState(() => _fotosNuevas[campo] = bytes);
                        },
                  child: Text(_fotosNuevas[campo] != null ? 'Otra' : 'Cambiar'),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _seccion(String titulo) => Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 10),
        child: Text(titulo,
            style: TextStyle(color: AppColors.green, fontWeight: FontWeight.w800)),
      );

  Widget _campo(
    String campo,
    String etiqueta, {
    TextInputType teclado = TextInputType.text,
    List<TextInputFormatter>? formato,
    String? Function(String?)? validar,
    String? Function(String?)? aviso,
    bool mayusculas = false,
  }) {
    final c = _c[campo]!;
    final advertencia = aviso?.call(c.text);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: c,
        keyboardType: teclado,
        inputFormatters: formato,
        autovalidateMode: AutovalidateMode.onUserInteraction,
        textCapitalization: mayusculas ? TextCapitalization.words : TextCapitalization.none,
        validator: validar,
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(
          labelText: etiqueta,
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
        ),
      ),
    );
  }
}
