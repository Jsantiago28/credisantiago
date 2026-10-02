import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:printing/printing.dart';

import '../logic/calculo_prestamo.dart';
import '../logic/validacion.dart';
import '../recibos/recibo_pdf.dart';
import '../services/supabase_service.dart';
import '../theme/app_theme.dart';
import '../widgets/elegir_foto.dart';
import '../widgets/formato_campos.dart';
import '../widgets/foto_privada.dart';
import '../widgets/ui.dart';

/// Perfil → Mi recibo: logo, nombre del negocio, teléfono, dirección y
/// mensaje al pie de los recibos. Todo es opcional.
class MiReciboScreen extends StatefulWidget {
  final Map<String, dynamic> perfil;
  const MiReciboScreen({super.key, required this.perfil});

  @override
  State<MiReciboScreen> createState() => _MiReciboScreenState();
}

class _MiReciboScreenState extends State<MiReciboScreen> {
  final _form = GlobalKey<FormState>();
  late final _negocio = TextEditingController(text: _valor('negocio'));
  late final _telefono = TextEditingController(text: _valor('recibo_telefono'));
  late final _direccion = TextEditingController(text: _valor('recibo_direccion'));
  late final _mensaje = TextEditingController(text: _valor('recibo_mensaje'));

  /// Logo guardado (ubicación en el bucket); null si no tiene o lo quitó.
  late String? _logoGuardado = _valor('recibo_logo').isEmpty ? null : _valor('recibo_logo');
  Uint8List? _logoNuevo;
  bool _guardando = false;

  String _valor(String campo) => ((widget.perfil[campo] as String?) ?? '').trim();

  @override
  void dispose() {
    for (final c in [_negocio, _telefono, _direccion, _mensaje]) {
      c.dispose();
    }
    super.dispose();
  }

  /// Lo que hay escrito ahora, como lo verá el recibo.
  NegocioRecibo get _negocioActual => NegocioRecibo.dePerfil({
        ...widget.perfil,
        'negocio': _negocio.text,
        'recibo_telefono': _telefono.text,
        'recibo_direccion': _direccion.text,
        'recibo_mensaje': _mensaje.text,
        'recibo_logo': _logoGuardado,
      });

  Future<void> _elegirLogo() async {
    final bytes = await elegirFoto(context, maxWidth: 400);
    if (bytes != null) setState(() => _logoNuevo = bytes);
  }

  void _quitarLogo() => setState(() {
        _logoNuevo = null;
        _logoGuardado = null;
      });

  Future<void> _verEjemplo() async {
    final negocio = _negocioActual;
    final logo = _logoNuevo ?? await SupabaseService.instance.bajarFoto(_logoGuardado);
    if (!mounted) return;
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => Scaffold(
        appBar: AppBar(title: const Text('Así se verá tu recibo')),
        body: PdfPreview(
          build: (_) => reciboPdf(
            r: reciboDeEjemplo(DateTime.now()),
            negocio: negocio,
            logo: logo,
            cliente: 'Juan Pérez',
            cedula: '001-0000000-1',
          ),
          allowPrinting: false,
          allowSharing: false,
          canChangePageFormat: false,
          canChangeOrientation: false,
          canDebug: false,
        ),
      ),
    ));
  }

  Future<void> _guardar() async {
    if (!_form.currentState!.validate()) return;
    final mensajero = ScaffoldMessenger.of(context);
    final servicio = SupabaseService.instance;
    final id = widget.perfil['id'] as String;
    setState(() => _guardando = true);
    try {
      var logo = _logoGuardado;
      if (_logoNuevo != null) {
        logo = await servicio.subirFoto(bytes: _logoNuevo!, prestamistaId: id, tipo: 'logo');
      }
      String? texto(TextEditingController c) => c.text.trim().isEmpty ? null : c.text.trim();
      final cambios = {
        'negocio': texto(_negocio),
        'recibo_telefono': texto(_telefono),
        'recibo_direccion': texto(_direccion),
        'recibo_mensaje': texto(_mensaje),
        'recibo_logo': logo,
      };
      await servicio.guardarMiRecibo(id, cambios);
      widget.perfil.addAll(cambios);
      if (!mounted) return;
      mensajero.showSnackBar(const SnackBar(content: Text('Tu recibo quedó guardado')));
      Navigator.of(context).pop(true);
    } catch (e) {
      // ignore: avoid_print
      print('ERROR REAL GUARDAR RECIBO: $e');
      mensajero.showSnackBar(SnackBar(content: Text('No se pudo guardar: $e')));
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final whatsapp = _valor('whatsapp');
    return Scaffold(
      appBar: AppBar(title: const Text('Mi recibo')),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            const Text(
              'Esto sale arriba y abajo de cada recibo que le mandas a tus clientes. '
              'Todo es opcional.',
              style: TextStyle(color: AppColors.grey),
            ),
            const SizedBox(height: 16),
            _logo(),
            const SizedBox(height: 16),
            _campo(_negocio, 'Nombre del negocio',
                ayuda: 'Si lo dejas vacío, sale tu nombre.', largo: 40, mayusculas: true),
            _campo(_telefono, 'Teléfono',
                ayuda: whatsapp.isEmpty
                    ? null
                    : 'Si lo dejas vacío, sale tu WhatsApp ($whatsapp).',
                teclado: TextInputType.phone,
                formato: [FormatoTelefono()],
                validar: (t) => errorTelefono(t, obligatorio: false)),
            _campo(_direccion, 'Dirección', largo: 60),
            _campo(_mensaje, 'Mensaje al pie',
                ayuda: 'Ej.: "Pague a tiempo y evite mora". '
                    'Si lo dejas vacío, dice "${NegocioRecibo.mensajeDeSiempre}"',
                largo: 120,
                lineas: 2),
            const SizedBox(height: 4),
            OutlinedButton.icon(
              onPressed: _guardando ? null : _verEjemplo,
              icon: const Icon(Icons.receipt_long_rounded),
              label: const Text('Ver cómo queda'),
            ),
            const SizedBox(height: 8),
            ElevatedButton.icon(
              onPressed: _guardando ? null : _guardar,
              icon: _guardando
                  ? const SizedBox(
                      width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.check),
              label: const Text('Guardar'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _logo() {
    final sinLogo = Container(
      color: AppColors.surfaceAlt,
      child: const Icon(Icons.storefront_rounded, color: AppColors.grey, size: 36),
    );
    final tieneLogo = _logoNuevo != null || _logoGuardado != null;
    return Panel(
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              width: 80,
              height: 80,
              child: _logoNuevo != null
                  ? Image.memory(_logoNuevo!, fit: BoxFit.contain)
                  : _logoGuardado != null
                      ? FotoPrivada(
                          guardado: _logoGuardado,
                          width: 80,
                          height: 80,
                          fit: BoxFit.contain,
                          sinFoto: sinLogo)
                      : sinLogo,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Logo', style: TextStyle(fontWeight: FontWeight.w800)),
                const Text('Sale arriba del recibo.',
                    style: TextStyle(color: AppColors.grey, fontSize: 12)),
                Wrap(
                  children: [
                    TextButton(
                      onPressed: _guardando ? null : _elegirLogo,
                      child: Text(tieneLogo ? 'Cambiar' : 'Poner logo'),
                    ),
                    if (tieneLogo)
                      TextButton(
                        onPressed: _guardando ? null : _quitarLogo,
                        style: TextButton.styleFrom(foregroundColor: AppColors.red),
                        child: const Text('Quitar'),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _campo(
    TextEditingController c,
    String etiqueta, {
    String? ayuda,
    int? largo,
    int lineas = 1,
    bool mayusculas = false,
    TextInputType teclado = TextInputType.text,
    List<TextInputFormatter>? formato,
    String? Function(String?)? validar,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: c,
        keyboardType: lineas > 1 ? TextInputType.multiline : teclado,
        inputFormatters: formato,
        maxLength: largo,
        minLines: 1,
        maxLines: lineas,
        autovalidateMode: AutovalidateMode.onUserInteraction,
        textCapitalization:
            mayusculas ? TextCapitalization.words : TextCapitalization.sentences,
        validator: validar,
        decoration: InputDecoration(
          labelText: etiqueta,
          helperText: ayuda,
          helperMaxLines: 3,
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

/// Un cobro inventado para mostrar el recibo: cuota #3 con un poco de mora.
DatosRecibo reciboDeEjemplo(DateTime hoy) => DatosRecibo(
      numero: 125,
      fecha: hoy,
      monto: 1100,
      aCuota: 1000,
      aMora: 100,
      cubre: ['Cuota #3 (${hoy.day}/${hoy.month}/${hoy.year})'],
      balanceDespues: 8000,
      moraPendienteDespues: 0,
      proximoPagoFecha: hoy.add(const Duration(days: 7)),
      proximoPagoMonto: 1000,
      saldado: false,
    );
